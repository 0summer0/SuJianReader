import Foundation
import CryptoKit

private enum FileInspectionError: Error {
    case nonText(sample: Data)
}

struct LibraryArchive: Codable {
    var records: [ReadingRecord]
    var dismissed: [DismissedSharedFile]
    var unreadableInbox: [UnreadableInboxFile]

    init(
        records: [ReadingRecord],
        dismissed: [DismissedSharedFile],
        unreadableInbox: [UnreadableInboxFile] = []
    ) {
        self.records = records
        self.dismissed = dismissed
        self.unreadableInbox = unreadableInbox
    }

    private enum CodingKeys: String, CodingKey {
        case records, dismissed, unreadableInbox
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decode([ReadingRecord].self, forKey: .records)
        dismissed = try container.decodeIfPresent([DismissedSharedFile].self, forKey: .dismissed) ?? []
        unreadableInbox = try container.decodeIfPresent([UnreadableInboxFile].self, forKey: .unreadableInbox) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
        try container.encode(dismissed, forKey: .dismissed)
        try container.encode(unreadableInbox, forKey: .unreadableInbox)
    }
}

private struct LibraryPersistenceError: Error {
    let underlying: Error
}

@Observable
final class LibraryStore {
    private(set) var records: [ReadingRecord] = []
    var errorMessage: String?
    var focusID: UUID?
    var readerPath: [ReaderRoute] = []

    private var dismissed: [DismissedSharedFile] = []
    private var unreadableInbox: [UnreadableInboxFile] = []
    private let fileManager = FileManager.default
    private let archiveURLOverride: URL?
    private let sampleReader: (URL) throws -> Data
    // Files does not display the app folder when it contains only hidden files.
    private static let sharedFolderMarkerName = "keep"

    var sortedRecords: [ReadingRecord] {
        records.sorted { $0.lastOpened > $1.lastOpened }
    }

    init(archiveURL: URL? = nil, sampleReader: @escaping (URL) throws -> Data = LibraryStore.readTextSample) {
        archiveURLOverride = archiveURL
        self.sampleReader = sampleReader
        #if DEBUG
        if usesDeletionUITestFixture {
            records = (1...3).map { index in
                ReadingRecord(
                    id: UUID(), title: "回归文稿 \(index)", fileName: "fixture-\(index).md",
                    bookmark: Data(), lastOpened: Date(timeIntervalSince1970: Double(4 - index)),
                    byteCount: 1024, origin: .external, relativePath: nil
                )
            }
            return
        }
        if usesReaderUITestFixture {
            installReaderUITestFixture()
            return
        }
        #endif
        load()
        syncSharedDocuments()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-openMatch"), index + 1 < arguments.count {
            let needle = arguments[index + 1]
            focusID = records.first { $0.title.contains(needle) || $0.fileName.contains(needle) }?.id
        } else if arguments.contains("-openFirst"), focusID == nil {
            focusID = sortedRecords.first?.id
        }
        #endif
    }

    func consumeFocus() -> UUID? {
        let id = focusID
        focusID = nil
        return id
    }

    func clearError() {
        errorMessage = nil
    }

    func importURLs(_ urls: [URL], openSingle: Bool) {
        var firstID: UUID?
        var failures = 0
        for url in urls {
            do {
                let id = try addFile(at: url)
                if firstID == nil { firstID = id }
            } catch {
                failures += 1
            }
        }
        if openSingle, urls.count == 1, let firstID {
            focusID = firstID
        }
        if failures > 0 {
            errorMessage = failures == urls.count
                ? String(localized: "没能打开这份文稿。")
                : String(localized: "有 \(failures) 份文稿没能加入文库。")
        }
    }

    func acceptIncoming(_ url: URL) {
        importURLs([url], openSingle: true)
    }

    func adoptFile(at url: URL) -> UUID? {
        do {
            return try addFile(at: url)
        } catch {
            errorMessage = String(localized: "没能打开这份文稿。")
            return nil
        }
    }

    func openRoot(_ id: UUID, anchor: String? = nil) {
        if readerPath.count == 1, readerPath[0].id == id, readerPath[0].anchor == anchor { return }
        readerPath = [ReaderRoute(id: id, anchor: anchor)]
    }

    @ObservationIgnored private(set) var consumedAnchorTokens: Set<UUID> = []

    func markAnchorConsumed(_ token: UUID) {
        consumedAnchorTokens.insert(token)
    }

    func present(_ id: UUID, anchor: String? = nil) {
        if let last = readerPath.last, last.id == id, last.anchor == anchor { return }
        readerPath = readerPath + [ReaderRoute(id: id, anchor: anchor)]
    }

    func syncSharedDocuments() {
        #if DEBUG
        if usesUITestFixture { return }
        #endif
        ensureSharedFolderListed()
        var changed = processInbox()
        changed = scanSharedFolder() || changed
        if changed { save() }
    }

    func beginAccess(_ record: ReadingRecord) throws -> DocumentAccess {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: record.bookmark,
            options: [.withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let started = url.startAccessingSecurityScopedResource()
        if stale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index].bookmark = refreshed
            save()
        }
        return DocumentAccess(url: url, started: started, byteCount: fileSize(url))
    }

    func noteReading(id: UUID, title: String?, byteCount: Int64) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].lastOpened = Date()
        records[index].byteCount = byteCount
        if let title, !title.isEmpty {
            records[index].title = title
        }
        save()
    }

    func delete(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let doomed = records.filter { ids.contains($0.id) }
        for record in doomed {
            switch record.origin {
            case .importedCopy:
                if let url = try? resolvedURL(record.bookmark) {
                    try? fileManager.removeItem(at: url)
                }
            case .sharedFolder:
                if let relativePath = record.relativePath {
                    let url = documentsDirectory.appendingPathComponent(relativePath)
                    let modified = modificationDate(url) ?? Date()
                    dismissed.removeAll { $0.relativePath == relativePath }
                    dismissed.append(DismissedSharedFile(relativePath: relativePath, modifiedAt: modified))
                }
            case .external:
                break
            }
        }
        records.removeAll { ids.contains($0.id) }
        if let focusID, ids.contains(focusID) {
            self.focusID = nil
        }

        let remaining = readerPath.filter { !ids.contains($0.id) }
        if remaining.count != readerPath.count {
            readerPath = remaining
        }
        save()
    }

    @discardableResult
    private func addFile(at url: URL, openedAt: Date? = nil) throws -> UUID {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
        let sample = try sampleReader(url)
        guard looksLikeText(sample) else { throw FileInspectionError.nonText(sample: sample) }

        // Delete a temporary source only after the copy and library archive are saved.
        let isTemporarySource = shouldImportCopy(url)
        let storedURL = isTemporarySource ? try copyIntoImports(url) : url
        var committed = false
        defer {
            if isTemporarySource {
                try? fileManager.removeItem(at: committed ? url : storedURL)
            }
        }
        if let index = indexOfRecord(matching: storedURL) {
            let id = try touchExisting(at: index, url: storedURL, bumpRecency: openedAt == nil)
            committed = true
            return id
        }

        let bookmark = try storedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let (origin, relative) = classify(storedURL)
        let previousDismissed = dismissed
        if let relative {
            dismissed.removeAll { $0.relativePath == relative }
        }
        let fileName = safeFileName(storedURL.lastPathComponent)
        let stem = (fileName as NSString).deletingPathExtension
        let record = ReadingRecord(
            id: UUID(),
            title: TextFile.peekTitle(url: storedURL, fallback: stem.isEmpty ? fileName : stem),
            fileName: fileName,
            bookmark: bookmark,
            lastOpened: openedAt ?? Date(),
            byteCount: fileSize(storedURL),
            origin: origin,
            relativePath: relative
        )
        records.append(record)
        do {
            try persist()
        } catch {
            records.removeAll { $0.id == record.id }
            dismissed = previousDismissed
            throw error
        }
        committed = true
        return record.id
    }

    private func touchExisting(at index: Int, url: URL, bumpRecency: Bool) throws -> UUID {
        let previousRecord = records[index]
        let previousDismissed = dismissed
        let fileName = safeFileName(url.lastPathComponent)
        let stem = (fileName as NSString).deletingPathExtension
        if bumpRecency {
            records[index].lastOpened = Date()
        }
        records[index].fileName = fileName
        records[index].byteCount = fileSize(url)
        records[index].title = TextFile.peekTitle(url: url, fallback: records[index].title.isEmpty ? stem : records[index].title)
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            records[index].bookmark = bookmark
        }
        let (origin, relative) = classify(url)
        records[index].origin = origin
        records[index].relativePath = relative
        if let relative {
            dismissed.removeAll { $0.relativePath == relative }
        }
        let id = records[index].id
        do {
            try persist()
        } catch {
            records[index] = previousRecord
            dismissed = previousDismissed
            throw error
        }
        return id
    }

    @discardableResult
    private func processInbox() -> Bool {
        let inbox = documentsDirectory.appendingPathComponent("Inbox", isDirectory: true)
        guard let items = try? fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var changed = false
        let onDisk = Dictionary(uniqueKeysWithValues: items.map { (safeFileName($0.lastPathComponent), $0) })
        let before = unreadableInbox.count
        unreadableInbox.removeAll { entry in
            guard let url = onDisk[entry.fileName] else { return true }
            return !inboxFile(url, matches: entry)
        }
        if unreadableInbox.count != before { changed = true }

        for url in items {
            guard MarkdownFile.supportsPathExtension(url.pathExtension) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            if unreadableInbox.contains(where: { inboxFile(url, matches: $0) }) { continue }
            do {
                try addFile(at: url)
                changed = true
            } catch {
                if case FileInspectionError.nonText(let sample) = error, let modified = modificationDate(url) {
                    let name = safeFileName(url.lastPathComponent)
                    unreadableInbox.removeAll { $0.fileName == name }
                    unreadableInbox.append(UnreadableInboxFile(
                        fileName: name,
                        byteCount: fileSize(url),
                        modifiedAt: modified,
                        sampleDigest: sampleDigest(sample)
                    ))
                    changed = true
                }
                errorMessage = String(localized: "没能打开这份文稿。")
            }
        }
        return changed
    }

    private func inboxFile(_ url: URL, matches entry: UnreadableInboxFile) -> Bool {
        guard safeFileName(url.lastPathComponent) == entry.fileName else { return false }
        guard fileSize(url) == entry.byteCount else { return false }
        guard let modified = modificationDate(url) else { return false }
        guard abs(modified.timeIntervalSince(entry.modifiedAt)) <= 1,
              let digest = entry.sampleDigest,
              let sample = try? sampleReader(url) else { return false }
        return sampleDigest(sample) == digest
    }

    private func sampleDigest(_ sample: Data) -> Data { Data(SHA256.hash(data: sample)) }

    private func scanSharedFolder() -> Bool {
        var changed = false
        let known = knownIdentities()
        var seenSharedIDs = Set<UUID>()

        guard let enumerator = fileManager.enumerator(
            at: documentsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return changed }

        for case let url as URL in enumerator {
            if url.lastPathComponent == Self.sharedFolderMarkerName { continue }
            if url.lastPathComponent == "Inbox",
               url.deletingLastPathComponent().standardizedFileURL.path == documentsDirectory.standardizedFileURL.path {
                enumerator.skipDescendants()
                continue
            }

            if url.lastPathComponent == ".Trash" {
                enumerator.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard MarkdownFile.supportsPathExtension(url.pathExtension) else { continue }

            let relative = relativePath(from: documentsDirectory, to: url)
            if let dismissedIndex = dismissed.firstIndex(where: { $0.relativePath == relative }) {
                let stored = dismissed[dismissedIndex].modifiedAt
                if let modified = modificationDate(url), modified.timeIntervalSince(stored) > 1 {
                    dismissed.remove(at: dismissedIndex)
                    changed = true
                } else {
                    continue
                }
            }

            if let index = known[FileIdentity.key(for: url)] {
                seenSharedIDs.insert(records[index].id)
                if records[index].relativePath != relative || records[index].origin != .sharedFolder {
                    records[index].relativePath = relative
                    records[index].origin = .sharedFolder
                    records[index].fileName = safeFileName(url.lastPathComponent)
                    changed = true
                }
                let size = fileSize(url)
                if records[index].byteCount != size {
                    records[index].byteCount = size
                    changed = true
                }
                let peeked = TextFile.peekTitle(url: url, fallback: records[index].title)
                if peeked != records[index].title {
                    records[index].title = peeked
                    changed = true
                }
                continue
            }
            let openedAt = modificationDate(url) ?? Date()
            do {
                let id = try addFile(at: url, openedAt: openedAt)
                seenSharedIDs.insert(id)
                changed = true
            } catch is LibraryPersistenceError {
                errorMessage = String(localized: "文库没能保存。")
            } catch {
            }
        }

        let seenPaths = Set(records.filter { seenSharedIDs.contains($0.id) }.compactMap(\.relativePath))
        let missing = records.filter { record in
            guard record.origin == .sharedFolder, !seenSharedIDs.contains(record.id) else { return false }
            if let relative = record.relativePath {
                if relativePathIsInTrash(relative) || seenPaths.contains(relative) { return true }
                let url = documentsDirectory.appendingPathComponent(relative)
                if fileManager.fileExists(atPath: url.path) { return false }
            }
            if let url = try? resolvedURL(record.bookmark),
               fileManager.fileExists(atPath: url.path),
               !isInTrash(url) {
                return false
            }
            return true
        }
        if !missing.isEmpty {
            let ids = Set(missing.map(\.id))
            records.removeAll { ids.contains($0.id) }
            readerPath.removeAll { ids.contains($0.id) }
            if let focusID, ids.contains(focusID) { self.focusID = nil }
            changed = true
        }

        let before = dismissed.count
        dismissed.removeAll { item in
            !fileManager.fileExists(atPath: documentsDirectory.appendingPathComponent(item.relativePath).path)
        }
        if dismissed.count != before { changed = true }
        return changed
    }

    private func isInTrash(_ url: URL) -> Bool {
        let root = FilePath.canonical(documentsDirectory)
        let path = FilePath.canonical(url)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(prefix) else { return false }
        return relativePathIsInTrash(String(path.dropFirst(prefix.count)))
    }

    private func relativePathIsInTrash(_ relative: String) -> Bool {
        relative.split(separator: "/").contains(".Trash")
    }

    private func knownIdentities() -> [String: Int] {
        var index: [String: Int] = [:]
        for (offset, record) in records.enumerated() {
            if let url = try? resolvedURL(record.bookmark) {
                index[FileIdentity.key(for: url)] = offset
            }
        }
        return index
    }

    private func indexOfRecord(matching url: URL) -> Int? {
        knownIdentities()[FileIdentity.key(for: url)]
    }

    private func resolvedURL(_ bookmark: Data) throws -> URL {
        var stale = false
        return try URL(
            resolvingBookmarkData: bookmark,
            options: [.withoutImplicitStartAccessing],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    private func classify(_ url: URL) -> (DocumentOrigin, String?) {
        let path = FilePath.canonical(url)
        let imports = FilePath.canonical(importsDirectory)
        let documents = FilePath.canonical(documentsDirectory)
        if path == imports || path.hasPrefix(imports + "/") {
            return (.importedCopy, nil)
        }
        if path.hasPrefix(documents + "/") {
            return (.sharedFolder, relativePath(from: documentsDirectory, to: url))
        }
        return (.external, nil)
    }

    private func shouldImportCopy(_ url: URL) -> Bool {
        let path = FilePath.canonical(url)
        if path.contains("/TemporaryItems/") { return true }
        let roots = [
            documentsDirectory.appendingPathComponent("Inbox", isDirectory: true),
            fileManager.temporaryDirectory,
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            URL(fileURLWithPath: "/tmp", isDirectory: true),
            URL(fileURLWithPath: "/private/tmp", isDirectory: true),
        ]
        return roots.contains { isWithin(path, $0) }
    }

    private func isWithin(_ path: String, _ directory: URL) -> Bool {
        var root = FilePath.canonical(directory)
        if root.count > 1, root.hasSuffix("/") { root.removeLast() }
        guard root.count > 1 else { return false }
        return path == root || path.hasPrefix(root + "/")
    }

    private func copyIntoImports(_ url: URL) throws -> URL {
        let destination = uniqueURL(in: importsDirectory, name: safeFileName(url.lastPathComponent))
        try fileManager.copyItem(at: url, to: destination)
        return destination
    }

    // Propagate sampling errors: file protection or permissions may recover later.
    static func readTextSample(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4096) ?? Data()
    }

    private func looksLikeText(_ sample: Data) -> Bool {
        if sample.isEmpty { return true }
        if sample.starts(with: [0xFF, 0xFE]) || sample.starts(with: [0xFE, 0xFF]) { return true }
        let zeros = sample.filter { $0 == 0 }.count
        if zeros == 0 { return true }
        return zeros > sample.count / 5
    }

    private func uniqueURL(in directory: URL, name: String) -> URL {
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }

    private func safeFileName(_ name: String) -> String {
        let base = (name as NSString).lastPathComponent
        if base.isEmpty || base == "." || base == ".." { return "未命名.md" }
        return base
    }

    private func relativePath(from base: URL, to url: URL) -> String {
        let root = FilePath.canonical(base)
        let path = FilePath.canonical(url)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return url.lastPathComponent
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func ensureSharedFolderListed() {
        let directory = documentsDirectory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var marker = directory.appendingPathComponent(Self.sharedFolderMarkerName)
        if !fileManager.fileExists(atPath: marker.path) {
            guard fileManager.createFile(atPath: marker.path, contents: Data()) else { return }
        }
        guard (try? marker.resourceValues(forKeys: [.isHiddenKey]).isHidden) == true else { return }
        var values = URLResourceValues()
        values.isHidden = false
        try? marker.setResourceValues(values)
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var supportDirectory: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var importsDirectory: URL {
        let url = supportDirectory.appendingPathComponent("Imports", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var archiveURL: URL {
        archiveURLOverride ?? supportDirectory.appendingPathComponent("library.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: archiveURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let archive = try? decoder.decode(LibraryArchive.self, from: data) {
            records = archive.records
            dismissed = archive.dismissed
            unreadableInbox = archive.unreadableInbox
            return
        }
        let broken = archiveURL.appendingPathExtension("bad")
        try? fileManager.removeItem(at: broken)
        try? fileManager.moveItem(at: archiveURL, to: broken)
        errorMessage = String(localized: "文库记录读不出来，已从空白开始。")
    }

    private func save() {
        do {
            try persist()
        } catch {
            errorMessage = String(localized: "文库没能保存。")
        }
    }

    private func persist() throws {
        #if DEBUG
        if usesUITestFixture { return }
        #endif
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(LibraryArchive(
                records: records,
                dismissed: dismissed,
                unreadableInbox: unreadableInbox
            ))
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            throw LibraryPersistenceError(underlying: error)
        }
    }

    #if DEBUG

    private var usesDeletionUITestFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-deletionUITestFixture")
    }

    private var usesReaderUITestFixture: Bool {
        ProcessInfo.processInfo.arguments.contains("-readerUITestFixture")
    }

    private var usesUITestFixture: Bool {
        usesDeletionUITestFixture || usesReaderUITestFixture
    }

    // UI tests use temporary files and an in-memory library, never the user's library.
    private func installReaderUITestFixture() {
        do {
            let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Markdown语法手册.md")
            let paragraph = "这一段用于检查阅读、滚动和目录跳转。\n\n"
            let body = "# Markdown语法手册\n\n" +
                ["1. 标题（Heading）", "7. 代码（Code）", "附：速查表"]
                    .map { "## \($0)\n\n" + String(repeating: paragraph, count: 35) }
                    .joined(separator: "\n")
            try body.write(to: url, atomically: true, encoding: .utf8)
            let record = ReadingRecord(
                id: UUID(), title: "Markdown语法手册", fileName: url.lastPathComponent,
                bookmark: try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
                lastOpened: Date(), byteCount: Int64(body.utf8.count), origin: .external, relativePath: nil
            )
            records = [record]
            if ProcessInfo.processInfo.arguments.contains("-openMatch") {
                focusID = record.id
            }
        } catch {
            errorMessage = "Unable to create UI test fixture: \(error.localizedDescription)"
        }
    }
    #endif
}

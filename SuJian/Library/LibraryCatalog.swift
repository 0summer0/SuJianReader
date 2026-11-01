import Foundation

struct LibraryFolder: Identifiable, Equatable {
    var id: String { path.isEmpty ? "/" : path }
    var path: String
    var name: String
    var folders: [LibraryFolder]
    var files: [ReadingRecord]

    var documentCount: Int {
        files.count + folders.reduce(0) { $0 + $1.documentCount }
    }
}

struct LibraryOutlineRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case folder(LibraryFolder)
        case file(ReadingRecord, alignsTitle: Bool)
    }

    var id: String
    var depth: Int
    var kind: Kind
}

enum LibraryCatalog {
    static func outline(from records: [ReadingRecord]) -> LibraryFolder {
        var root = LibraryFolder(path: "", name: "", folders: [], files: [])
        for record in records where record.origin == .sharedFolder {
            let relative = record.relativePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
            let parts = relative.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            insert(record, components: parts.isEmpty ? [record.fileName] : parts, at: 0, into: &root)
        }
        return sorted(root)
    }

    static func recent(from records: [ReadingRecord]) -> [ReadingRecord] {
        records
            .filter { $0.origin != .sharedFolder }
            .sorted { $0.lastOpened > $1.lastOpened }
    }

    static func keepingCollapsedSelection(
        current: Set<UUID>,
        proposed: Set<UUID>,
        records: [ReadingRecord],
        expanded: Set<String>
    ) -> Set<UUID> {
        let alive = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var next = proposed.intersection(Set(alive.keys))
        for id in current.subtracting(proposed) {
            guard let record = alive[id], isInsideCollapsedFolder(record, expanded: expanded) else { continue }
            next.insert(id)
        }
        return next
    }

    static func isInsideCollapsedFolder(_ record: ReadingRecord, expanded: Set<String>) -> Bool {
        guard record.origin == .sharedFolder else { return false }
        let relative = record.relativePath?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let parent = (relative as NSString).deletingLastPathComponent
        guard !parent.isEmpty else { return false }
        var path = ""
        for part in parent.split(separator: "/") where !part.isEmpty {
            path = path.isEmpty ? String(part) : path + "/" + String(part)
            if !expanded.contains(path) { return true }
        }
        return false
    }

    static func matches(_ record: ReadingRecord, keyword: String) -> Bool {
        if record.title.localizedStandardContains(keyword) { return true }
        if record.fileName.localizedStandardContains(keyword) { return true }
        if let path = record.relativePath, path.localizedStandardContains(keyword) { return true }
        return false
    }

    static func rows(in folder: LibraryFolder, expanded: Set<String>, depth: Int = 0) -> [LibraryOutlineRow] {
        var output: [LibraryOutlineRow] = []
        let alignFiles = depth > 0 || !folder.folders.isEmpty
        for child in folder.folders {
            output.append(LibraryOutlineRow(id: "folder:\(child.path)", depth: depth, kind: .folder(child)))
            if expanded.contains(child.path) {
                output.append(contentsOf: rows(in: child, expanded: expanded, depth: depth + 1))
            }
        }
        for file in folder.files {
            output.append(LibraryOutlineRow(
                id: "file:\(file.id.uuidString)",
                depth: depth,
                kind: .file(file, alignsTitle: alignFiles)
            ))
        }
        return output
    }

    private static func insert(_ record: ReadingRecord, components: [String], at index: Int, into folder: inout LibraryFolder) {
        let name = components[index]
        let isFile = index == components.count - 1
        if isFile {
            folder.files.append(record)
            return
        }
        let path = folder.path.isEmpty ? name : folder.path + "/" + name
        if let existing = folder.folders.firstIndex(where: { $0.path == path }) {
            insert(record, components: components, at: index + 1, into: &folder.folders[existing])
        } else {
            var child = LibraryFolder(path: path, name: name, folders: [], files: [])
            insert(record, components: components, at: index + 1, into: &child)
            folder.folders.append(child)
        }
    }

    private static func sorted(_ folder: LibraryFolder) -> LibraryFolder {
        var copy = folder
        copy.folders = folder.folders.map(sorted).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        copy.files = folder.files.sorted {
            $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
        }
        return copy
    }
}

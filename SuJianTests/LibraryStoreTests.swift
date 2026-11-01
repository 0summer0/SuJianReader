import XCTest
@testable import SuJian

final class LibraryStoreTests: XCTestCase {
    func testSharedFolderFindsPlainTextFiles() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "Text-\(UUID().uuidString).TXT"
        let file = documents.appendingPathComponent(name)
        defer {
            try? FileManager.default.removeItem(at: file)
            store.syncSharedDocuments()
        }
        try Data("# 标题\n正文".utf8).write(to: file)
        store.syncSharedDocuments()
        XCTAssertTrue(store.records.contains { $0.fileName == name && $0.origin == .sharedFolder })
    }

    func testFailedArchiveKeepsTemporarySourcesAndRemovesUnregisteredCopies() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let archiveDirectory = root.appendingPathComponent("archive", isDirectory: true)
        try manager.createDirectory(at: archiveDirectory, withIntermediateDirectories: true)
        let store = LibraryStore(archiveURL: archiveDirectory)
        let names = ["Import-\(UUID().uuidString).md", "Import-\(UUID().uuidString).md"]
        let sources = names.map { root.appendingPathComponent($0) }
        let imports = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Imports", isDirectory: true)
        for source in sources { try Data("# 标题\n".utf8).write(to: source) }

        store.importURLs(sources, openSingle: false)

        XCTAssertNotNil(store.errorMessage)
        for (source, name) in zip(sources, names) {
            XCTAssertTrue(manager.fileExists(atPath: source.path))
            XCTAssertFalse(manager.fileExists(atPath: imports.appendingPathComponent(name).path))
            XCTAssertFalse(store.records.contains { $0.fileName == name })
        }
    }

    func testUnreadableInboxFileIsReportedOnceUntilItChanges() throws {
        let manager = FileManager.default
        let store = LibraryStore()
        let inbox = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        let name = "Bad-\(UUID().uuidString).txt"
        let file = inbox.appendingPathComponent(name)
        defer {
            try? manager.removeItem(at: file)

            LibraryStore().syncSharedDocuments()
        }
        try manager.createDirectory(at: inbox, withIntermediateDirectories: true)

        try Data([0x01, 0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]).write(to: file)

        store.syncSharedDocuments()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(manager.fileExists(atPath: file.path))
        XCTAssertFalse(store.records.contains { $0.fileName == name })

        store.clearError()
        store.syncSharedDocuments()
        XCTAssertNil(store.errorMessage)

        let reloaded = LibraryStore()
        XCTAssertNil(reloaded.errorMessage)
        XCTAssertFalse(reloaded.records.contains { $0.fileName == name })

        try Data([0x01, 0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]).write(to: file)
        reloaded.clearError()
        reloaded.syncSharedDocuments()
        XCTAssertNotNil(reloaded.errorMessage)
        XCTAssertFalse(reloaded.records.contains { $0.fileName == name })
    }

    func testOldLibraryArchiveDecodesWithoutUnreadableInbox() throws {
        let json = Data(#"{"dismissed":[],"records":[]}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LibraryArchive.self, from: json)
        XCTAssertTrue(archive.records.isEmpty)
        XCTAssertTrue(archive.dismissed.isEmpty)
        XCTAssertTrue(archive.unreadableInbox.isEmpty)
    }

    func testSharedFolderMarkerStaysOutOfTheLibrary() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let marker = documents.appendingPathComponent("keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let hidden = try marker.resourceValues(forKeys: [.isHiddenKey]).isHidden
        XCTAssertNotEqual(hidden, true)
        XCTAssertEqual(marker.pathExtension, "")
        XCTAssertFalse(store.records.contains { $0.fileName == "keep" })
    }

    func testDeletingSharedFolderDropsThoseRecords() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "Prune-\(UUID().uuidString.prefix(8))"
        let folder = documents.appendingPathComponent(name, isDirectory: true)
        let keeper = documents.appendingPathComponent("\(name)-keep.md")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: keeper)
            let leftover = store.records.filter {
                $0.relativePath?.hasPrefix(name) == true
            }.map(\.id)
            if !leftover.isEmpty { store.delete(ids: Set(leftover)) }
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# 标题\n\n正文\n".utf8).write(to: folder.appendingPathComponent("note.md"))
        try Data("# 留下\n".utf8).write(to: keeper)
        store.syncSharedDocuments()

        let note = store.records.first { $0.relativePath == "\(name)/note.md" }
        XCTAssertEqual(note?.origin, .sharedFolder)
        let noteID = try XCTUnwrap(note?.id)
        store.present(noteID)
        XCTAssertTrue(store.records.contains { $0.relativePath == "\(name)-keep.md" })

        try FileManager.default.removeItem(at: folder)
        store.syncSharedDocuments()

        XCTAssertFalse(store.records.contains { $0.relativePath?.hasPrefix("\(name)/") == true })
        XCTAssertFalse(store.readerPath.contains { $0.id == noteID })
        XCTAssertTrue(store.records.contains { $0.relativePath == "\(name)-keep.md" })
    }

    func testRecentlyDeletedFolderLeavesTheLibraryUntilRestored() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "Trash-\(UUID().uuidString.prefix(8))"
        let folder = documents.appendingPathComponent(name, isDirectory: true)
        let trash = documents.appendingPathComponent(".Trash", isDirectory: true)
        let trashed = trash.appendingPathComponent(name, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: trashed)
            let leftover = store.records.filter { $0.relativePath?.hasPrefix(name) == true }.map(\.id)
            if !leftover.isEmpty { store.delete(ids: Set(leftover)) }
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("# 标题\n\n正文\n".utf8).write(to: folder.appendingPathComponent("note.md"))
        store.syncSharedDocuments()
        XCTAssertTrue(store.records.contains { $0.relativePath == "\(name)/note.md" })

        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: folder, to: trashed)
        store.syncSharedDocuments()
        XCTAssertFalse(store.records.contains { record in
            guard let relative = record.relativePath else { return false }
            return relative.hasPrefix(name) || relative.contains("/.Trash/") || relative.hasPrefix(".Trash/")
        })

        try FileManager.default.moveItem(at: trashed, to: folder)
        store.syncSharedDocuments()
        XCTAssertTrue(store.records.contains { $0.relativePath == "\(name)/note.md" })
    }

    func testUserFolderNamedTmpIsLeftInPlace() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let token = "KeepTmp-\(UUID().uuidString.prefix(8))"
        let root = documents.appendingPathComponent(token, isDirectory: true)
        let file = root.appendingPathComponent("tmp", isDirectory: true).appendingPathComponent("\(token).md")
        defer { try? FileManager.default.removeItem(at: root) }
        defer { store.delete(ids: Set(store.records.filter { $0.fileName == "\(token).md" }.map(\.id))) }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# 标题\n".utf8).write(to: file)
        store.importURLs([file], openSingle: false)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.records.first { $0.fileName == "\(token).md" }?.origin, .sharedFolder)
    }

    func testUserFolderNamedInboxIsLeftInPlace() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let token = "KeepInbox-\(UUID().uuidString.prefix(8))"
        let root = documents.appendingPathComponent(token, isDirectory: true)
        let file = root.appendingPathComponent("Inbox", isDirectory: true).appendingPathComponent("\(token).md")
        defer { try? FileManager.default.removeItem(at: root) }
        defer { store.delete(ids: Set(store.records.filter { $0.fileName == "\(token).md" }.map(\.id))) }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# 标题\n".utf8).write(to: file)
        store.importURLs([file], openSingle: false)

        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.records.first { $0.fileName == "\(token).md" }?.origin, .sharedFolder)
    }

    func testTemporaryDirectoryFileIsCopiedIntoImports() throws {
        let store = LibraryStore()
        let token = "TempCopy-\(UUID().uuidString.prefix(8))"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(token).md")
        defer { try? FileManager.default.removeItem(at: file) }
        defer { store.delete(ids: Set(store.records.filter { $0.fileName == "\(token).md" }.map(\.id))) }

        try Data("# 标题\n".utf8).write(to: file)
        store.importURLs([file], openSingle: false)

        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.records.first { $0.fileName == "\(token).md" }?.origin, .importedCopy)
    }

    func testAppInboxFileIsCopiedIntoImports() throws {
        let store = LibraryStore()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let token = "InboxCopy-\(UUID().uuidString.prefix(8))"
        let file = documents.appendingPathComponent("Inbox", isDirectory: true).appendingPathComponent("\(token).md")
        defer { try? FileManager.default.removeItem(at: file) }
        defer { store.delete(ids: Set(store.records.filter { $0.fileName == "\(token).md" }.map(\.id))) }

        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# 标题\n".utf8).write(to: file)
        store.importURLs([file], openSingle: false)

        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(store.records.first { $0.fileName == "\(token).md" }?.origin, .importedCopy)
    }
}

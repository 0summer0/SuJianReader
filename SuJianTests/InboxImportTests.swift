import XCTest
@testable import SuJian

final class InboxImportTests: XCTestCase {
    func testTransientSampleReadFailureIsRetried() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let inbox = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        try manager.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent("Retry-\(UUID().uuidString).txt")
        var failRead = true
        let store = LibraryStore(archiveURL: root.appendingPathComponent("library.json")) { url in
            if url == file && failRead { throw CocoaError(.fileReadNoPermission) }
            return try LibraryStore.readTextSample(url)
        }
        defer {
            try? manager.removeItem(at: file)
            store.delete(ids: Set(store.records.filter { $0.fileName == file.lastPathComponent }.map(\.id)))
        }
        try Data("# 文稿\n".utf8).write(to: file)

        store.syncSharedDocuments()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertTrue(manager.fileExists(atPath: file.path))
        XCTAssertFalse(store.records.contains { $0.fileName == file.lastPathComponent })

        failRead = false
        store.clearError()
        store.syncSharedDocuments()
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.records.contains { $0.fileName == file.lastPathComponent })
    }

    func testSameSizeAndTimestampInPlaceRewriteIsRechecked() throws {
        try verifySameSizeReplacement(options: [])
    }

    func testSameSizeAndTimestampAtomicReplacementIsRechecked() throws {
        try verifySameSizeReplacement(options: .atomic)
    }

    private func verifySameSizeReplacement(options: Data.WritingOptions) throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let inbox = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Inbox", isDirectory: true)
        try manager.createDirectory(at: inbox, withIntermediateDirectories: true)
        let file = inbox.appendingPathComponent("Replace-\(UUID().uuidString).txt")
        let store = LibraryStore(archiveURL: root.appendingPathComponent("library.json"))
        defer {
            try? manager.removeItem(at: file)
            store.delete(ids: Set(store.records.filter { $0.fileName == file.lastPathComponent }.map(\.id)))
        }
        let invalid = Data([0x01, 0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])
        let valid = Data("# Heading\n".utf8)
        XCTAssertEqual(invalid.count, valid.count)
        try invalid.write(to: file)
        let modified = try XCTUnwrap(manager.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        store.syncSharedDocuments()
        XCTAssertNotNil(store.errorMessage)

        try valid.write(to: file, options: options)
        try manager.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        store.clearError()
        store.syncSharedDocuments()
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.records.contains { $0.fileName == file.lastPathComponent })
    }

    func testUnreadableEntryFromOldArchiveHasNoDigest() throws {
        let json = Data(#"{"fileName":"old.txt","byteCount":10,"modifiedAt":"2026-01-01T00:00:00Z"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(UnreadableInboxFile.self, from: json)
        XCTAssertNil(entry.sampleDigest)
    }
}

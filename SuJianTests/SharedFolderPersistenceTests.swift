import XCTest
@testable import SuJian

final class SharedFolderPersistenceTests: XCTestCase {
    func testFailedArchiveReportsErrorAndRetriesSharedDocument() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archive = root.appendingPathComponent("library.json")
        try manager.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let store = LibraryStore(archiveURL: archive)
        store.clearError()
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "Scan-\(UUID().uuidString).md"
        let source = documents.appendingPathComponent(name)
        defer { try? manager.removeItem(at: source) }
        try Data("# Shared document\n".utf8).write(to: source)

        store.syncSharedDocuments()
        XCTAssertNotNil(store.errorMessage)
        XCTAssertFalse(store.records.contains { $0.fileName == name })
        XCTAssertTrue(manager.fileExists(atPath: source.path))

        try manager.removeItem(at: archive)
        store.clearError()
        store.syncSharedDocuments()
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.records.contains { $0.fileName == name && $0.origin == .sharedFolder })
    }

    func testInvalidSharedDocumentDoesNotRaisePersistenceAlert() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let store = LibraryStore(archiveURL: root.appendingPathComponent("library.json"))
        store.clearError()
        let documents = manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = "Invalid-\(UUID().uuidString).md"
        let source = documents.appendingPathComponent(name)
        defer { try? manager.removeItem(at: source) }
        try Data([0x01, 0x00, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09]).write(to: source)

        store.syncSharedDocuments()
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.records.contains { $0.fileName == name })
    }
}

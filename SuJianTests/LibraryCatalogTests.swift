import XCTest
@testable import SuJian

final class LibraryCatalogTests: XCTestCase {
    func testSharedFolderBecomesATreeAndOtherFilesStayRecent() {
        let older = Date(timeIntervalSince1970: 10)
        let newer = Date(timeIntervalSince1970: 20)
        let records = [
            sample("loose", "00-loose.md", .sharedFolder, "00-loose.md", older),
            sample("readme", "README.md", .sharedFolder, "Archive/README.md", older),
            sample("beta", "10-b.md", .sharedFolder, "Examples/10-b.md", older),
            sample("alpha", "2-a.md", .sharedFolder, "Examples/2-a.md", older),
            sample("outside-new", "outside.md", .external, nil, newer),
            sample("copy", "copy.md", .importedCopy, nil, older)
        ]

        let root = LibraryCatalog.outline(from: records)
        XCTAssertEqual(root.folders.map(\.name), ["Archive", "Examples"])
        XCTAssertEqual(root.files.map(\.fileName), ["00-loose.md"])
        XCTAssertEqual(root.folders[1].files.map(\.fileName), ["2-a.md", "10-b.md"])
        XCTAssertEqual(root.folders[1].documentCount, 2)
        XCTAssertEqual(root.documentCount, 4)

        let recent = LibraryCatalog.recent(from: records)
        XCTAssertEqual(recent.map(\.fileName), ["outside.md", "copy.md"])

        let collapsed = LibraryCatalog.rows(in: root, expanded: [])
        XCTAssertEqual(collapsed.map(\.id), [
            "folder:Archive",
            "folder:Examples",
            "file:\(root.files[0].id.uuidString)"
        ])

        let opened = LibraryCatalog.rows(in: root, expanded: ["Examples"])
        XCTAssertEqual(opened.count, 5)
        if case .file(let first, let aligns) = opened[2].kind {
            XCTAssertEqual(first.fileName, "2-a.md")
            XCTAssertTrue(aligns)
            XCTAssertEqual(opened[2].depth, 1)
        } else {
            XCTFail("展开后应是文稿")
        }
    }

    func testCollapsedFolderKeepsSelectionAndVisibleDeselectDoesNot() {
        let nested = sample("章节", "01.md", .sharedFolder, "示例文稿/章节/01.md", Date())
        let chapter = sample("文稿", "02.md", .sharedFolder, "示例文稿/02.md", Date())
        let loose = sample("散篇", "00.md", .sharedFolder, "00.md", Date())
        let records = [nested, chapter, loose]
        let selected: Set = [nested.id, chapter.id, loose.id]

        let collapsed = LibraryCatalog.keepingCollapsedSelection(
            current: selected,
            proposed: [loose.id],
            records: records,
            expanded: []
        )
        XCTAssertEqual(collapsed, selected)

        let parentOpen = LibraryCatalog.keepingCollapsedSelection(
            current: selected,
            proposed: [chapter.id, loose.id],
            records: records,
            expanded: ["示例文稿"]
        )
        XCTAssertEqual(parentOpen, selected)

        let bothOpen = LibraryCatalog.keepingCollapsedSelection(
            current: selected,
            proposed: [chapter.id, loose.id],
            records: records,
            expanded: ["示例文稿", "示例文稿/章节"]
        )
        XCTAssertEqual(bothOpen, [chapter.id, loose.id])

        let deselected = LibraryCatalog.keepingCollapsedSelection(
            current: [loose.id],
            proposed: [],
            records: records,
            expanded: []
        )
        XCTAssertTrue(deselected.isEmpty)
    }

    func testSearchMatchesTheFolderPath() {
        let record = sample("示例标题", "01-示例标题.md", .sharedFolder, "示例文稿/01-示例标题.md", Date())
        XCTAssertTrue(LibraryCatalog.matches(record, keyword: "示例文稿"))
        XCTAssertTrue(LibraryCatalog.matches(record, keyword: "示例标题"))
        XCTAssertFalse(LibraryCatalog.matches(record, keyword: "没有"))
    }

    private func sample(
        _ title: String,
        _ fileName: String,
        _ origin: DocumentOrigin,
        _ relativePath: String?,
        _ opened: Date
    ) -> ReadingRecord {
        ReadingRecord(
            id: UUID(),
            title: title,
            fileName: fileName,
            bookmark: Data(),
            lastOpened: opened,
            byteCount: 1024,
            origin: origin,
            relativePath: relativePath
        )
    }
}

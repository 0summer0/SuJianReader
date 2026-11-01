import XCTest
@testable import SuJian

final class DocumentLinkTests: XCTestCase {
    private var note: URL!

    override func setUp() {
        note = URL(fileURLWithPath: "/Users/example/Documents/示例文稿/章节/01-示例文章.md")
    }

    func testDirectoryBaseKeepsRelativeLinksInTheFolder() {
        let base = DocumentLink.baseDirectory(for: note)
        XCTAssertTrue(base.hasDirectoryPath)
        let resolved = URL(string: "02.md", relativeTo: base)?.absoluteURL
        XCTAssertEqual(resolved?.lastPathComponent, "02.md")
        XCTAssertTrue(resolved?.path.hasSuffix("/示例文稿/章节/02.md") == true)
    }

    func testSiblingAndParentNotes() {
        guard case .open(let sibling, nil) = DocumentLink.resolve("02-示例.md", from: note) else {
            return XCTFail("同级文稿")
        }
        XCTAssertTrue(sibling.path.hasSuffix("/示例文稿/章节/02-示例.md"))

        guard case .open(let parent, let anchor) = DocumentLink.resolve("../../Examples/主题/简介/01-示例文档.md#q1-示例", from: note) else {
            return XCTFail("上层文稿")
        }
        XCTAssertTrue(parent.path.hasSuffix("/Examples/主题/简介/01-示例文档.md"))
        XCTAssertEqual(anchor, "q1-示例")
    }

    func testSameNoteScrollsToTheHeading() {
        guard case .scroll(let anchor) = DocumentLink.resolve("#q9-章节标题", from: note) else {
            return XCTFail("文内锚点")
        }
        XCTAssertEqual(anchor, "q9-章节标题")

        guard case .scroll("q1-示例") = DocumentLink.resolve("01-示例文章.md#q1-示例", from: note) else {
            return XCTFail("指向自己的锚点")
        }
    }

    func testWebLinksAndNonNotes() {
        guard case .external(let web) = DocumentLink.resolve("https://example.com/a", from: note) else {
            return XCTFail("网页")
        }
        XCTAssertEqual(web.host, "example.com")
        guard case .external(let section) = DocumentLink.resolve("https://example.com/a?q=1#section", from: note) else {
            return XCTFail("带片段的网页")
        }
        XCTAssertEqual(section.absoluteString, "https://example.com/a?q=1#section")
        guard case .external(let mail) = DocumentLink.resolve("mailto:reader@example.com?subject=Note#part", from: note) else {
            return XCTFail("邮件链接")
        }
        XCTAssertEqual(mail.fragment, "part")
        guard case .ignore = DocumentLink.resolve("javascript:alert(1)", from: note) else { return XCTFail("脚本") }
        guard case .ignore = DocumentLink.resolve("/Users/example/outside.md", from: note) else { return XCTFail("绝对路径") }
        guard case .ignore = DocumentLink.resolve("示例文件夹/", from: note) else { return XCTFail("文件夹") }
        guard case .ignore = DocumentLink.resolve("templates/LinkedList.swift", from: note) else { return XCTFail("代码") }
    }
}

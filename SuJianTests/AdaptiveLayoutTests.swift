import XCTest
@testable import SuJian

final class AdaptiveLayoutTests: XCTestCase {
    private func makeRecord(_ store: LibraryStore, name: String) throws -> (UUID, URL) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("\(name).md")
        try Data("# \(name)\n\n正文\n".utf8).write(to: url)
        store.syncSharedDocuments()
        let id = try XCTUnwrap(store.records.first { $0.relativePath == "\(name).md" }?.id)
        return (id, url)
    }

    func testOpenRootReplacesTheStackAndPresentPushes() throws {
        let store = LibraryStore()
        let a = UUID(), b = UUID()
        store.openRoot(a)
        store.present(b, anchor: "h1")
        XCTAssertEqual(store.readerPath.map(\.id), [a, b])
        store.openRoot(b)
        XCTAssertEqual(store.readerPath.map(\.id), [b])
        let token = store.readerPath[0].token
        store.openRoot(b)
        XCTAssertEqual(store.readerPath[0].token, token, "同一篇重复打开不该换掉这一页")
    }

    func testDeletingARecordDropsItsPagesFromTheReaderStack() throws {
        let store = LibraryStore()
        let name = "Adapt-\(UUID().uuidString.prefix(8))"
        let (id, url) = try makeRecord(store, name: name)
        defer { try? FileManager.default.removeItem(at: url) }
        let other = UUID()
        store.openRoot(other)
        store.present(id)
        store.present(other)
        store.delete(ids: [id])
        XCTAssertEqual(store.readerPath.map(\.id), [other, other])
        XCTAssertFalse(store.records.contains { $0.id == id })
    }

    func testAnchorIsConsumedOncePerPage() {
        let store = LibraryStore()
        store.openRoot(UUID(), anchor: "intro")
        let token = store.readerPath[0].token
        XCTAssertFalse(store.consumedAnchorTokens.contains(token))
        store.markAnchorConsumed(token)
        XCTAssertTrue(store.consumedAnchorTokens.contains(token))
    }

    func testWideTypographyIsOptIn() {
        let rendered = MarkdownRender.render("# 标题\n\n正文")
        let narrow = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: false)
        let wide = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: false, wide: true)
        XCTAssertFalse(narrow.contains("<html class=\"paper\" data-wide"))
        XCTAssertTrue(wide.contains("<html class=\"paper\" data-wide"))
        XCTAssertTrue(narrow.contains("padding: 4.6rem 1.45rem 4.5rem"), "窄屏的版式不能变")
        XCTAssertTrue(narrow.contains("@media (min-width: 700px)"), "横屏和 Duo、iPad 的宽画布要放开 40rem")
        XCTAssertTrue(wide.contains("html[data-wide] article {"), "宽屏要单独放宽正文")
        XCTAssertTrue(wide.contains("max-width: none;"), "宽屏正文跟着阅读栏走")
        XCTAssertFalse(wide.contains("max-width: 42rem;"))
    }

    func testTopChromeInsetOnlyAppliesWithoutStatusBar() {
        XCTAssertEqual(TopChromeMetrics.extra(forSafeTop: 0), 24)
        XCTAssertEqual(TopChromeMetrics.extra(forSafeTop: 20), 0, "iPhone SE")
        XCTAssertEqual(TopChromeMetrics.extra(forSafeTop: 24), 0, "iPad")
        XCTAssertEqual(TopChromeMetrics.extra(forSafeTop: 47), 0, "刘海")
        XCTAssertEqual(TopChromeMetrics.extra(forSafeTop: 62), 0, "灵动岛")
    }

    func testReaderTopInsetTracksExtraChromeSpace() {
        let rendered = MarkdownRender.render("# 标题\n\n正文")
        let ipad = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: false, wide: true)
        let duo = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: false, topInset: Double(TopChromeMetrics.extra(forSafeTop: 0)))
        XCTAssertTrue(ipad.contains("--chrome-top-extra: 0.0px"))
        XCTAssertTrue(duo.contains("--chrome-top-extra: 24.0px"))
        XCTAssertTrue(duo.contains("padding-top: calc(4.6rem + var(--chrome-top-extra, 0px))"))
    }
}

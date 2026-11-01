import XCTest

final class LocalizationTests: XCTestCase {
    func testSimplifiedStaysTheSourceCopy() {
        XCTAssertEqual(text("最近阅读", language: "zh-Hans"), "最近阅读")
        XCTAssertEqual(text("已选 \(2)", language: "zh-Hans"), "已选 2")
        XCTAssertEqual(text("删除 \(1) 条记录", language: "zh-Hans"), "删除 1 条记录")
    }

    func testEnglishInterface() {
        XCTAssertEqual(text("最近阅读", language: "en"), "Recent")
        XCTAssertEqual(text("打开", language: "en"), "Open")
        XCTAssertEqual(text("目录", language: "en"), "Contents")
        XCTAssertEqual(text("已选 \(2)", language: "en"), "2 selected")
        XCTAssertEqual(text("删除 \(1) 条记录", language: "en"), "Delete 1 Record")
        XCTAssertEqual(text("删除 \(3) 条记录", language: "en"), "Delete 3 Records")
        XCTAssertEqual(
            text("有 \(1) 份文稿没能加入文库。", language: "en"),
            "1 document couldn’t be added to the library."
        )
        XCTAssertEqual(
            text("有 \(2) 份文稿没能加入文库。", language: "en"),
            "2 documents couldn’t be added to the library."
        )
        XCTAssertEqual(text("第 \(2) 页，共 \(5) 页", language: "en"), "Page 2 of 5")
        XCTAssertEqual(text("全选", language: "en"), "Select All")
        XCTAssertEqual(text("全选", language: "zh-Hant"), "全選")
        XCTAssertEqual(text("文稿", language: "en"), "Documents")
        XCTAssertEqual(text("文稿", language: "zh-Hant"), "文稿")
        XCTAssertEqual(text("\(1) 篇", language: "en"), "1 document")
        XCTAssertEqual(text("\(2) 篇", language: "en"), "2 documents")
        XCTAssertEqual(text("\(3) 篇", language: "zh-Hant"), "3 篇")
        let count = "1,234"
        XCTAssertEqual(
            text("\(count) 字 · 约 \(3) 分钟", language: "en"),
            "1,234 characters · about 3 min"
        )
        XCTAssertEqual(
            text("移除 \(2) 条打开记录。原稿仍留在「文件」里。", language: "en"),
            "Removes 2 entries. The originals stay in Files."
        )
        XCTAssertEqual(
            text("移除 \(1) 条打开记录。原稿仍留在「文件」里。", language: "en"),
            "Removes 1 entry. The original stays in Files."
        )
        XCTAssertEqual(
            text("移除 \(2) 条打开记录。分享时复制进素笺的 \(1) 份副本会一起删除，其余原稿仍留在「文件」里。", language: "en"),
            "Removes 2 from the library. 1 copied in from Share will be deleted too. Originals stay in Files."
        )
        XCTAssertEqual(text("警告", language: "en"), "Warning")
        XCTAssertEqual(text("脚注", language: "en"), "Footnotes")
    }

    func testTraditionalInterface() {
        XCTAssertEqual(text("最近阅读", language: "zh-Hant"), "最近閱讀")
        XCTAssertEqual(text("搜索文稿", language: "zh-Hant"), "搜尋文稿")
        XCTAssertEqual(text("目录", language: "zh-Hant"), "目錄")
        XCTAssertEqual(text("已选 \(2)", language: "zh-Hant"), "已選 2")
        XCTAssertEqual(text("删除 \(3) 条记录", language: "zh-Hant"), "刪除 3 筆記錄")
        XCTAssertEqual(text("警告", language: "zh-Hant"), "警告")
        XCTAssertEqual(text("备注", language: "zh-Hant"), "備註")
        XCTAssertEqual(text("脚注", language: "zh-Hant"), "註腳")
    }

    func testHomeScreenName() {
        XCTAssertEqual(displayName("en"), "SuJian")
        XCTAssertEqual(displayName("zh-Hans"), "素笺")
        XCTAssertEqual(displayName("zh-Hant"), "素箋")
    }

    private func text(_ value: String.LocalizationValue, language: String) -> String {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return "missing \(language)"
        }
        return String(localized: value, bundle: bundle, locale: Locale(identifier: language))
    }

    private func displayName(_ language: String) -> String? {
        guard let path = Bundle.main.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: language),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else { return nil }
        return table["CFBundleDisplayName"]
    }
}

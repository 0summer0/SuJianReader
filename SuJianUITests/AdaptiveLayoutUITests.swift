import XCTest

final class AdaptiveLayoutUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-readerUITestFixture"]
        app.launch()
        return app
    }

    private func isRegularWidth(_ app: XCUIApplication) -> Bool {
        let frame = app.windows.firstMatch.frame
        return frame.width >= 700 && frame.height >= 700
    }

    private func firstFile(_ app: XCUIApplication) -> XCUIElement {
        let marked = app.descendants(matching: .any).matching(identifier: "library-file").firstMatch
        if marked.waitForExistence(timeout: 8) { return marked }
        return app.cells.firstMatch
    }

    func testWideWindowKeepsLibraryBesideTheReader() throws {
        let app = launchApp()
        try XCTSkipUnless(isRegularWidth(app), "只在常规宽度的窗口里有文库 + 正文两栏")
        let row = firstFile(app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let outline = app.buttons["目录"]
        XCTAssertTrue(outline.waitForExistence(timeout: 5))

        let toggle = app.buttons["文库"]
        XCTAssertTrue(toggle.exists, "宽屏阅读栏左上角要有收放文库的按钮")
        let sideBySide = app.windows.firstMatch.frame.width >= 900
        let select = app.buttons["选择"]
        if sideBySide {
            XCTAssertTrue(select.exists, "窗口够宽时读文稿也看得见文库")
            toggle.tap()
            XCTAssertTrue(waitUntilGone(select), "收起后文库消失")
            toggle.tap()
            XCTAssertTrue(select.waitForExistence(timeout: 3), "再点一次文库回来")
        } else {
            XCTAssertTrue(waitUntilGone(select), "窗口较窄时读文稿把文库收起")
            toggle.tap()
            XCTAssertTrue(select.waitForExistence(timeout: 3), "点按钮，文库浮在正文上")
        }
    }

    func testWideWindowOpensOutlineAsPopover() throws {
        let app = launchApp()
        try XCTSkipUnless(isRegularWidth(app), "宽屏才用浮层目录")
        let row = firstFile(app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let outline = app.buttons["目录"]
        XCTAssertTrue(outline.waitForExistence(timeout: 5))
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: outline)
        waitForExpectations(timeout: 10)
        outline.tap()
        XCTAssertTrue(app.staticTexts["目录"].waitForExistence(timeout: 3) || app.navigationBars["目录"].waitForExistence(timeout: 3))
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 4) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: timeout)
        return result == .completed
    }
}

import XCTest

final class SelectionUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-readerUITestFixture"]
        app.launch()
        return app
    }

    func testRowOpensDocument() {
        let app = launchApp()

        let row = firstFile(app)
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.buttons["目录"].waitForExistence(timeout: 3))
    }

    func testSelectionCirclesStayUntilDone() {
        let app = launchApp()

        let select = app.buttons["选择"]
        XCTAssertTrue(select.waitForExistence(timeout: 8))
        select.tap()

        let done = app.buttons["完成"]
        XCTAssertTrue(done.waitForExistence(timeout: 2))
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        XCTAssertTrue(done.exists)
        XCTAssertFalse(app.buttons["选择"].exists)
        XCTAssertTrue(app.buttons["全选"].exists)

        let row = firstFile(app)
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
        XCTAssertTrue(app.staticTexts["已选 1"].waitForExistence(timeout: 2))

        done.tap()
        XCTAssertTrue(app.buttons["选择"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["全选"].exists)
    }

    private func firstFile(_ app: XCUIApplication) -> XCUIElement {
        let marked = app.descendants(matching: .any).matching(identifier: "library-file").firstMatch
        if marked.waitForExistence(timeout: 8) { return marked }
        return app.cells.firstMatch
    }
}

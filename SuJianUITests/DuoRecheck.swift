import XCTest

final class DuoRecheck: XCTestCase {
    func testChromeStaysWhileScrollingOnVerticalBarPhone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-readerUITestFixture", "-openMatch", "Markdown语法手册"]
        app.launch()
        let win = app.windows.firstMatch
        XCTAssertTrue(win.waitForExistence(timeout: 8))

        try XCTSkipUnless(win.frame.width > 400 && win.frame.width < 500 && win.frame.height > 600 && win.frame.height < 750,
                          "只在 Duo 外屏这类窄高窗口上跑")

        let outline = app.buttons["目录"]
        XCTAssertTrue(outline.waitForExistence(timeout: 10))

        let back = app.buttons["返回"]
        XCTAssertTrue(back.exists)
        XCTAssertGreaterThanOrEqual(back.frame.minY, 28, "返回按钮离屏幕上沿太近")
        XCTAssertGreaterThanOrEqual(outline.frame.minY, 28, "目录按钮离屏幕上沿太近")
        XCTAssertLessThanOrEqual(outline.frame.maxX, win.frame.width - 84, "目录/Aa 不能压进右侧竖条")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        start.press(forDuration: 0.05, thenDragTo: end)
        sleep(1)
        XCTAssertTrue(outline.exists, "有系统竖条时，滚动后顶栏仍应可见")
    }
}

extension DuoRecheck {
    func testLibraryChromeClearsTheTopEdgeOnVerticalBarPhone() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-readerUITestFixture"]
        app.launch()
        let win = app.windows.firstMatch
        XCTAssertTrue(win.waitForExistence(timeout: 8))
        try XCTSkipUnless(win.frame.width > 400 && win.frame.width < 500 && win.frame.height > 600 && win.frame.height < 750,
                          "只在 Duo 外屏这类窄高窗口上跑")
        let select = app.buttons["选择"]
        XCTAssertTrue(select.waitForExistence(timeout: 8))

        XCTAssertGreaterThanOrEqual(select.frame.minY - 12, 30, "文库标题栏离屏幕上沿太近")
    }
}

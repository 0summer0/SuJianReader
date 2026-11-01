import XCTest

final class AnchorJumpUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-readerUITestFixture", "-openMatch", "Markdown语法手册"]
        app.launch()
        return app
    }

    private func chromeBottom(_ app: XCUIApplication) -> CGFloat? {
        for name in ["返回", "文库"] {
            let b = app.buttons[name]
            if b.exists, b.isHittable { return b.frame.maxY }
        }
        return nil
    }

    private func heading(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.webViews.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func jump(_ app: XCUIApplication, to entry: String, heading text: String) throws {
        let outline = app.buttons["目录"]
        XCTAssertTrue(outline.waitForExistence(timeout: 10))

        for _ in 0..<14 { app.swipeUp(velocity: .fast) }
        sleep(1)

        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: to)
        XCTAssertTrue(outline.waitForHittable(timeout: 5), "顶栏没有回来")
        outline.tap()
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", entry)).firstMatch

        var tries = 0

        let popover = app.popovers.firstMatch
        let up = popover.exists
            ? popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.88))
        let down = popover.exists
            ? popover.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            : app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        while !(row.exists && row.isHittable) && tries < 40 {
            up.press(forDuration: 0.05, thenDragTo: down)
            tries += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "目录里没有 \(entry)")
        row.tap()
        sleep(2)
        let title = heading(app, text)
        XCTAssertTrue(title.waitForExistence(timeout: 5), "页面里找不到标题 \(text)")
        let bottom = try XCTUnwrap(chromeBottom(app), "找不到顶栏左上角按钮")
        print("ANCHORNUM \(text) headingTop=\(title.frame.minY) chromeBottom=\(bottom) gap=\(title.frame.minY - bottom) window=\(app.windows.firstMatch.frame.size)")

        XCTAssertGreaterThanOrEqual(title.frame.minY, bottom + 6,
                                    "「\(text)」被顶栏盖住：标题上沿 \(title.frame.minY)，顶栏下沿 \(bottom)")
    }

    func testOutlineFirstEntryClearsTheChrome() throws {
        let app = launchApp()
        try jump(app, to: "1. 标题", heading: "1. 标题（Heading）")
    }

    func testOutlineMiddleEntryClearsTheChrome() throws {
        let app = launchApp()
        try jump(app, to: "7. 代码", heading: "7. 代码（Code）")
    }

    func testOutlineLastEntryClearsTheChrome() throws {
        let app = launchApp()
        try jump(app, to: "附：速查表", heading: "附：速查表")
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: self)], timeout: timeout) == .completed
    }
}

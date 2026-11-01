import XCTest

final class DeletionUITests: XCTestCase {
    func testRepeatedSwipeCancellationKeepsLastRecordAndAnchorsConfirmationToIt() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-deletionUITestFixture"
        ]
        app.launch()

        let first = app.staticTexts["回归文稿 1"]
        let second = app.staticTexts["回归文稿 2"]
        let last = app.staticTexts["回归文稿 3"]
        XCTAssertTrue(last.waitForExistence(timeout: 8))
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)

        for _ in 0..<2 {
            openDeletion(for: last, in: app)
            XCTAssertTrue(last.exists, "取消之前记录仍应显示")
            assertConfirmationIsNear(last, in: app)

            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
            let confirmation = app.buttons["删除 1 条记录"]
            XCTAssertTrue(waitUntilGone(confirmation))
            XCTAssertTrue(last.waitForExistence(timeout: 3))
            XCTAssertTrue(last.isHittable, "取消后最后一条记录应恢复可见且可操作")
            XCTAssertTrue(first.exists)
            XCTAssertTrue(second.exists)
        }

        openDeletion(for: last, in: app)
        assertConfirmationIsNear(last, in: app)
        app.buttons["删除 1 条记录"].tap()
        XCTAssertTrue(waitUntilGone(last))
        XCTAssertTrue(first.exists)
        XCTAssertTrue(second.exists)
    }

    private func openDeletion(for row: XCUIElement, in app: XCUIApplication) {
        row.swipeLeft()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        delete.tap()
        XCTAssertTrue(app.buttons["删除 1 条记录"].waitForExistence(timeout: 3))
    }

    private func assertConfirmationIsNear(_ row: XCUIElement, in app: XCUIApplication) {
        let action = app.buttons["删除 1 条记录"]

        XCTAssertGreaterThanOrEqual(action.frame.maxY, row.frame.minY - 60)
    }

    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 4
        ) == .completed
    }
}

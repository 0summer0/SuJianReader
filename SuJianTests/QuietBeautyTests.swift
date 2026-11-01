import XCTest
@testable import SuJian

final class QuietBeautyTests: XCTestCase {
    func testNightInkIsWarmAndNotPureWhite() {
        let ink = QuietBeauty.ink.dark
        let paper = QuietBeauty.paper.dark
        XCTAssertEqual(ink.hex, "#CFCAC1")
        XCTAssertEqual(paper.hex, "#1E1B17")
        XCTAssertNotEqual(ink.hex, "#FFFFFF")
        XCTAssertNotEqual(paper.hex, "#000000")
        XCTAssertGreaterThan(ink.red, 0.78)
        XCTAssertLessThan(ink.red, 0.86)
        XCTAssertGreaterThan(ink.red, ink.green)
        XCTAssertGreaterThan(ink.green, ink.blue)
        XCTAssertGreaterThan(paper.red, 0.09)
        XCTAssertLessThan(paper.red, 0.16)
        XCTAssertGreaterThan(paper.red, paper.blue)

        let ratio = ink.contrast(against: paper)
        XCTAssertGreaterThan(ratio, 9, "夜读要能读")
        XCTAssertLessThan(ratio, 12.5, "近黑纸上的高亮会刺眼")
    }

    func testHierarchyKeepsSecondaryReadableAndCalloutsQuieterThanBody() {
        let day = QuietBeauty.soft.light.contrast(against: QuietBeauty.paper.light)
        let night = QuietBeauty.soft.dark.contrast(against: QuietBeauty.paper.dark)
        XCTAssertGreaterThan(day, 4.5)
        XCTAssertGreaterThan(night, 4.5)
        XCTAssertGreaterThan(
            QuietBeauty.ink.light.contrast(against: QuietBeauty.paper.light),
            day
        )

        let body = QuietBeauty.ink.dark.relativeLuminance
        for tone in [QuietBeauty.note, QuietBeauty.tip, QuietBeauty.important, QuietBeauty.warning, QuietBeauty.caution] {
            XCTAssertLessThan(tone.dark.relativeLuminance, body, tone.dark.hex)
        }
    }

    func testDeletionBackgroundKeepsSystemWhiteLabelReadable() {
        let white = QuietBeauty.Chroma(hex: 0xFFFFFF)
        for background in [QuietBeauty.deletionBackground.light, QuietBeauty.deletionBackground.dark] {
            XCTAssertGreaterThan(white.contrast(against: background), 4.5)
        }
    }

    func testReaderStylesUseTheSameInk() throws {
        let rendered = MarkdownRender.render("# 标题\n\n正文")
        let day = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: false)
        let night = ReaderDocument.html(rendered: rendered, fallbackTitle: "x", scale: 1, dark: true)

        XCTAssertTrue(day.contains(QuietBeauty.themeCSS))
        XCTAssertTrue(night.contains(QuietBeauty.themeCSS))
        XCTAssertTrue(night.contains("#CFCAC1"))
        XCTAssertTrue(night.contains("#1E1B17"))
        XCTAssertTrue(day.contains("#2A2622"))
        XCTAssertTrue(day.contains("#F7F4EE"))
        XCTAssertFalse(night.contains("#E8E2D6"))
        XCTAssertFalse(night.contains("#141311"))
        XCTAssertFalse(night.contains("#FFFFFF"))
        XCTAssertTrue(day.contains("line-height: \(QuietBeauty.bodyLineHeight)"))
        XCTAssertTrue(day.contains("line-height: \(QuietBeauty.headingLineHeight)"))
        XCTAssertTrue(day.contains("letter-spacing: \(QuietBeauty.headingTrackingCSS)"))
        XCTAssertTrue(day.contains("letter-spacing: \(QuietBeauty.bodyTracking)"))
        XCTAssertEqual(QuietBeauty.seal.light.hex, "#8B3F32")
        XCTAssertEqual(QuietBeauty.bronze.light.hex, "#7A5A3A")
        XCTAssertEqual(QuietBeauty.bronze.dark.hex, "#C0A07A")
        XCTAssertGreaterThan(
            QuietBeauty.bronze.light.contrast(against: QuietBeauty.paper.light),
            4.5
        )
        XCTAssertLessThan(
            QuietBeauty.bronze.dark.relativeLuminance,
            QuietBeauty.ink.dark.relativeLuminance
        )
        XCTAssertEqual(QuietBeauty.paper.light.hex, "#F7F4EE")
        XCTAssertEqual(QuietBeauty.paperDeep.light.hex, "#F3ECE4")
        XCTAssertEqual(QuietBeauty.field.light.hex, "#EBE5DC")
        XCTAssertEqual(QuietBeauty.hairline.light.hex, "#DEDBD6")
        XCTAssertEqual(QuietBeauty.selectionWashDark, 0.08, accuracy: 0.0001)
        let stack = QuietBeauty.serifStack
        let latin = try XCTUnwrap(stack.range(of: "New York"))
        let cjk = try XCTUnwrap(stack.range(of: "Songti SC"))
        XCTAssertLessThan(latin.lowerBound, cjk.lowerBound)
        XCTAssertTrue(day.contains("unicode-range"))
        XCTAssertEqual(QuietBeauty.check.light.hex, "#86643C")
        XCTAssertTrue(day.contains(stack))
        XCTAssertTrue(day.contains("font-size: \(QuietBeauty.heading1Size)"))
        XCTAssertTrue(day.contains("font-size: \(QuietBeauty.heading4Size)"))
        XCTAssertTrue(day.contains("font-size: \(QuietBeauty.heading5Size)"))
        XCTAssertTrue(day.contains("font-size: \(QuietBeauty.heading6Size)"))
        XCTAssertTrue(day.contains("letter-spacing: \(QuietBeauty.codeLabelTracking)"))
        XCTAssertTrue(day.contains("border: 1px solid var(--code-rule);"))
        XCTAssertFalse(day.contains("tr:last-child td"))
        XCTAssertFalse(day.contains("--line-double"))
        XCTAssertTrue(day.contains("background-image: linear-gradient(var(--hairline), var(--hairline))"))
        XCTAssertTrue(day.contains("background-image: linear-gradient(var(--rule-solid), var(--rule-solid))"))
        XCTAssertEqual(QuietBeauty.ruleSolid.light.hex, QuietBeauty.rule.light.composited(over: QuietBeauty.paper.light).hex)
        XCTAssertTrue(day.contains("border-radius: \(QuietBeauty.codeRadius)"))
        XCTAssertTrue(day.contains("border: 1px solid var(--line);"))
        XCTAssertFalse(day.contains("letter-spacing: 0.14em"))
    }
}

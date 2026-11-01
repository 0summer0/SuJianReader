import SwiftUI
import UIKit

enum QuietBeauty {
    struct Chroma: Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var alphaUnits: Int

        init(hex: UInt32, alphaUnits: Int = 10_000) {
            red = Double((hex >> 16) & 0xFF) / 255
            green = Double((hex >> 8) & 0xFF) / 255
            blue = Double(hex & 0xFF) / 255
            self.alphaUnits = alphaUnits
        }

        var hex: String {
            String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
        }

        var css: String {
            let r = channel(red)
            let g = channel(green)
            let b = channel(blue)
            guard alphaUnits < 10_000 else { return hex }
            var digits = String(format: "%04d", alphaUnits)
            while digits.last == "0" { digits.removeLast() }
            return "rgba(\(r), \(g), \(b), 0.\(digits))"
        }

        var uiColor: UIColor {
            UIColor(red: red, green: green, blue: blue, alpha: Double(alphaUnits) / 10_000)
        }

        var relativeLuminance: Double {
            func curve(_ channel: Double) -> Double {
                channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * curve(red) + 0.7152 * curve(green) + 0.0722 * curve(blue)
        }

        func contrast(against other: Chroma) -> Double {
            let lighter = max(relativeLuminance, other.relativeLuminance)
            let darker = min(relativeLuminance, other.relativeLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        func composited(over background: Chroma) -> Chroma {
            let alpha = Double(alphaUnits) / 10_000
            return Chroma(
                red: red * alpha + background.red * (1 - alpha),
                green: green * alpha + background.green * (1 - alpha),
                blue: blue * alpha + background.blue * (1 - alpha)
            )
        }

        init(red: Double, green: Double, blue: Double, alphaUnits: Int = 10_000) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alphaUnits = alphaUnits
        }

        private func channel(_ value: Double) -> Int {
            Int((value * 255).rounded())
        }
    }

    struct Tone {
        var light: Chroma
        var dark: Chroma

        var uiColor: UIColor {
            UIColor { traits in
                (traits.userInterfaceStyle == .dark ? dark : light).uiColor
            }
        }

        var color: Color { Color(uiColor: uiColor) }

        func chroma(dark: Bool) -> Chroma { dark ? self.dark : light }
    }

    static let paper = Tone(light: Chroma(hex: 0xF7F4EE), dark: Chroma(hex: 0x1E1B17))

    static let paperDeep = Tone(light: Chroma(hex: 0xF3ECE4), dark: Chroma(hex: 0x2A2620))

    static let field = Tone(light: Chroma(hex: 0xEBE5DC), dark: Chroma(hex: 0x2A2620))

    static let columnRule = Tone(
        light: Chroma(hex: 0x2A2622, alphaUnits: 900),
        dark: Chroma(hex: 0xF6F1E6, alphaUnits: 1_000)
    )

    static let ink = Tone(light: Chroma(hex: 0x2A2622), dark: Chroma(hex: 0xCFCAC1))

    static let soft = Tone(light: Chroma(hex: 0x6E665C), dark: Chroma(hex: 0x9B978F))

    static let quote = Tone(light: Chroma(hex: 0x5C554C), dark: Chroma(hex: 0xBAB5AC))

    static let hairline = Tone(light: Chroma(hex: 0xDEDBD6), dark: Chroma(hex: 0x45423C))

    static let bronze = Tone(light: Chroma(hex: 0x7A5A3A), dark: Chroma(hex: 0xC0A07A))

    static let check = Tone(light: Chroma(hex: 0x86643C), dark: Chroma(hex: 0xB49670))

    static let seal = Tone(light: Chroma(hex: 0x8B3F32), dark: Chroma(hex: 0xC99288))

    static let deletionBackground = Tone(light: Chroma(hex: 0x8B7151), dark: Chroma(hex: 0x8C7052))

    static let codeRule = Tone(
        light: Chroma(hex: 0x2A2622, alphaUnits: 450),
        dark: Chroma(hex: 0xF6F1E6, alphaUnits: 600)
    )

    static let codeRadius = "8px"

    static let line = Tone(
        light: Chroma(hex: 0x2A2622, alphaUnits: 1_200),
        dark: Chroma(hex: 0xF6F1E6, alphaUnits: 1_800)
    )
    static let rule = Tone(
        light: Chroma(hex: 0x7A5A3A, alphaUnits: 5_500),
        dark: Chroma(hex: 0xC0A07A, alphaUnits: 5_000)
    )

    static let ruleSolid = Tone(
        light: rule.light.composited(over: paper.light),
        dark: rule.dark.composited(over: paper.dark)
    )
    static let select = Tone(
        light: Chroma(hex: 0x7A5A3A, alphaUnits: 2_000),
        dark: Chroma(hex: 0xC0A07A, alphaUnits: 2_800)
    )
    static let mark = Tone(
        light: Chroma(hex: 0xB89452, alphaUnits: 2_800),
        dark: Chroma(hex: 0xC0A07A, alphaUnits: 2_200)
    )

    static let note = Tone(light: Chroma(hex: 0x5C6A76), dark: Chroma(hex: 0x8FA3B3))
    static let tip = Tone(light: Chroma(hex: 0x5A6B56), dark: Chroma(hex: 0x93A890))
    static let important = Tone(light: Chroma(hex: 0x6C6174), dark: Chroma(hex: 0xB0A2BE))
    static let warning = Tone(light: Chroma(hex: 0x8A6840), dark: Chroma(hex: 0xC0A07A))
    static let caution = Tone(light: Chroma(hex: 0x8B3F32), dark: Chroma(hex: 0xC99288))

    static let veil = Tone(
        light: Chroma(hex: 0x2A2622, alphaUnits: 2_200),
        dark: Chroma(hex: 0x100E0C, alphaUnits: 4_000)
    )

    static let shadow = Tone(
        light: Chroma(hex: 0x2A2622, alphaUnits: 1_600),
        dark: Chroma(hex: 0x0C0A08, alphaUnits: 5_000)
    )

    static let selectionWashLight = 0.10
    static let selectionWashDark = 0.08

    static let wordmarkSize: CGFloat = 22
    static let listTitleSize: CGFloat = 18
    static let emptyTitleSize: CGFloat = 30
    static let proseSize: CGFloat = 16
    static let metaSize: CGFloat = 13

    static let headingTracking: CGFloat = 0.04
    static let wordmarkTracking: CGFloat = 0.04

    static let metaTracking: CGFloat = 0.12

    static let proseLineSpacing: CGFloat = 7

    static let bodyLineHeight = "1.82"
    static let headingLineHeight = "1.46"
    static let bodyTracking = "0.01em"
    static let headingTrackingCSS = "0.04em"

    static let heading1Size = "1.65rem"
    static let heading1Margin = "0.85rem 0 0.8rem"
    static let heading2Size = "1.38rem"
    static let heading3Size = "1.16rem"

    static let heading4Size = "1.08rem"
    static let heading5Size = "0.96rem"
    static let heading6Size = "0.86rem"

    static let serifStack = "\"New York\", \"NewYork-Regular\", \"Songti SC\", \"STSongti-SC-Regular\", \"Songti TC\", ui-serif, serif"

    static let headingFaceCSS = """
    @font-face {
      font-family: "Suxuan Heading";
      src: local("New York"), local("NewYork-Regular");
      unicode-range: U+0000-024F, U+2000-206F, U+20A0-20CF, U+2100-214F, U+2190-21FF, U+2200-22FF;
    }
    @font-face {
      font-family: "Suxuan Heading";
      src: local("Songti SC"), local("STSongti-SC-Regular"), local("Songti TC");
      unicode-range: U+2E80-2EFF, U+2F00-2FDF, U+3000-303F, U+31C0-31EF, U+3200-33FF, U+3400-4DBF, U+4E00-9FFF, U+F900-FAFF, U+FE30-FE4F, U+FF00-FFEF;
    }
    """

    static let codeLabelTracking = "0.02em"

    static let chromeFade: CGFloat = 44

    static let pageInset: CGFloat = 24
    static let rowVertical: CGFloat = 16
    static let hairlineWidth: CGFloat = 0.5
    static let ruleWidth: CGFloat = 28
    static let ruleWidthEmpty: CGFloat = 36
    static let ruleHeight: CGFloat = 1

    static let controlStroke: CGFloat = 1.5

    static let themeCSS: String = {
        func block(_ className: String, _ scheme: String, dark: Bool) -> String {
            let pick: (Tone) -> String = { $0.chroma(dark: dark).css }
            return """
            html.\(className) {
              color-scheme: \(scheme);
              --bg: \(pick(paper));
              --ink: \(pick(ink));
              --soft: \(pick(soft));
              --line: \(pick(line));
              --hairline: \(pick(hairline));
              --bronze: \(pick(bronze));
              --rule: \(pick(rule));
              --rule-solid: \(pick(ruleSolid));
              --code-bg: \(pick(paperDeep));
              --code-rule: \(pick(codeRule));
              --quote: \(pick(quote));
              --select: \(pick(select));
              --mark: \(pick(mark));
              --note: \(pick(note));
              --tip: \(pick(tip));
              --important: \(pick(important));
              --warning: \(pick(warning));
              --caution: \(pick(caution));
            }
            """
        }
        return block("paper", "light", dark: false) + "\n" + block("ink", "dark", dark: true)
    }()
}

extension View {
    func inkSongti(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        em: CGFloat = QuietBeauty.headingTracking
    ) -> some View {
        inkSerif(size, relativeTo: style)
            .tracking(size * em)
    }

    func inkWordmark() -> some View {
        inkSerif(QuietBeauty.wordmarkSize, relativeTo: .title2, bold: true)
            .tracking(QuietBeauty.wordmarkSize * QuietBeauty.wordmarkTracking)
    }

    func inkSectionLabel() -> some View {
        font(.system(size: QuietBeauty.metaSize))
            .tracking(QuietBeauty.metaSize * QuietBeauty.metaTracking)
    }
}

#if DEBUG

private struct QuietBeautySample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("素笺")
                .inkWordmark()
                .foregroundStyle(Ink.primary)
                .padding(.horizontal, QuietBeauty.pageInset)
                .padding(.top, 28)
                .padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 10) {
                InkRule()
                Text("最近阅读")
                    .inkSectionLabel()
                    .foregroundStyle(Ink.soft)
            }
            .padding(.horizontal, QuietBeauty.pageInset)
            .padding(.bottom, 8)
            row("灯下", "今天 · 12 KB")
            row("素笺", "昨天 · 4 KB")
            VStack(alignment: .leading, spacing: 12) {
                Text("夜读")
                    .inkSongti(28, relativeTo: .title)
                    .foregroundStyle(Ink.primary)
                Text("一千二百字 · 约 3 分钟")
                    .font(.system(size: 12))
                    .tracking(1.9)
                    .foregroundStyle(Ink.soft)
                Text("纸抬起来，墨收回去。字沉在纸里，不浮在玻璃上。")
                    .font(.system(size: QuietBeauty.proseSize))
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(QuietBeauty.proseLineSpacing)
            }
            .padding(QuietBeauty.pageInset)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Ink.paper)
    }

    private func row(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .inkSongti(QuietBeauty.listTitleSize)
                .foregroundStyle(Ink.primary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Ink.soft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, QuietBeauty.rowVertical)
        .padding(.horizontal, QuietBeauty.pageInset)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.hairline).frame(height: QuietBeauty.hairlineWidth)
        }
    }
}

#Preview("素宣") {
    HStack(spacing: 0) {
        QuietBeautySample()
        QuietBeautySample()
            .environment(\.colorScheme, .dark)
    }
    .frame(width: 720, height: 640)
}
#endif

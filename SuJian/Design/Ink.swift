import CoreText
import SwiftUI
import UIKit

enum Ink {
    static let paper = QuietBeauty.paper.color
    static let primary = QuietBeauty.ink.color
    static let soft = QuietBeauty.soft.color
    static let hairline = QuietBeauty.hairline.color
    static let bronze = QuietBeauty.bronze.color
    static let seal = QuietBeauty.seal.color

    static func chrome(active: Bool) -> Color {
        active ? bronze : soft
    }
}

struct InkRule: View {
    var width: CGFloat = QuietBeauty.ruleWidth

    var body: some View {
        Capsule()
            .fill(Ink.bronze)
            .frame(width: width, height: QuietBeauty.ruleHeight)
    }
}

enum InkFont {
    static func uiFont(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle = .body,
        bold: Bool = false,
        scaled: Bool = true
    ) -> UIFont {
        let system = UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        var descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        let cjkName = bold ? "STSongti-SC-Bold" : "STSongti-SC-Regular"
        var cascade = [UIFontDescriptor(fontAttributes: [.name: cjkName])]
        if let existing = descriptor.fontAttributes[.cascadeList] as? [UIFontDescriptor] {
            cascade.append(contentsOf: existing)
        }
        descriptor = descriptor.addingAttributes([.cascadeList: cascade])
        let font = UIFont(descriptor: descriptor, size: size)
        guard scaled else { return font }
        return UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledFont(for: font)
    }

    static func scaled(
        _ size: CGFloat,
        relativeTo style: Font.TextStyle,
        bold: Bool,
        category: DynamicTypeSize
    ) -> UIFont {
        let base = uiFont(size, relativeTo: style, bold: bold, scaled: false)
        let traits = UITraitCollection(preferredContentSizeCategory: category.uiCategory)
        return UIFontMetrics(forTextStyle: uiTextStyle(style)).scaledFont(for: base, compatibleWith: traits)
    }

    private static func uiTextStyle(_ style: Font.TextStyle) -> UIFont.TextStyle {
        if style == .largeTitle { return .largeTitle }
        if style == .title { return .title1 }
        if style == .title2 { return .title2 }
        if style == .title3 { return .title3 }
        if style == .headline { return .headline }
        if style == .subheadline { return .subheadline }
        if style == .callout { return .callout }
        if style == .footnote { return .footnote }
        if style == .caption { return .caption1 }
        if style == .caption2 { return .caption2 }
        return .body
    }
}

extension DynamicTypeSize {
    var uiCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

struct MixedSerif: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var size: CGFloat
    var style: Font.TextStyle
    var bold = false

    func body(content: Content) -> some View {
        content.font(Font(InkFont.scaled(size, relativeTo: style, bold: bold, category: dynamicTypeSize) as CTFont))
    }
}

extension View {
    func inkSerif(_ size: CGFloat, relativeTo style: Font.TextStyle = .body, bold: Bool = false) -> some View {
        modifier(MixedSerif(size: size, style: style, bold: bold))
    }
}

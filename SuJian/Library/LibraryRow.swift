import SwiftUI

struct LibraryRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    let subtitle: String
    var showsChevron = false
    var chevronOpen = false

    static let chevronColumn: CGFloat = 22

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Ink.bronze)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(chevronOpen ? 90 : 0))
                    .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: chevronOpen)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .inkSongti(QuietBeauty.listTitleSize)
                    .foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.soft)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, QuietBeauty.rowVertical)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.hairline).frame(height: QuietBeauty.hairlineWidth)
        }
        .contentShape(Rectangle())
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
    }
}

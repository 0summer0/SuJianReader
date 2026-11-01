import SwiftUI

extension View {
    @ViewBuilder
    func sheetSkipsVerticalBar() -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
    }
}

struct VerticalBarPresence: View {
    @Binding var isPresent: Bool

    var body: some View {
        if #available(iOS 27.1, *) {
            VerticalBarPresenceReader(isPresent: $isPresent)
        } else {
            Color.clear.onAppear { isPresent = false }
        }
    }
}

@available(iOS 27.1, *)
private struct VerticalBarPresenceReader: View {
    @Environment(\.toolbarVerticalEdge) private var toolbarVerticalEdge
    @Binding var isPresent: Bool

    var body: some View {
        Color.clear
            .onChange(of: toolbarVerticalEdge, initial: true) { _, edge in
                isPresent = edge != nil
            }
    }
}

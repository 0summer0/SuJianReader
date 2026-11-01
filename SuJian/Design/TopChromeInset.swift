import SwiftUI

enum TopChromeMetrics {
    static let comfortableTop: CGFloat = 24

    static let statusBarFloor: CGFloat = 16

    static func extra(forSafeTop safeTop: CGFloat) -> CGFloat {
        safeTop < statusBarFloor ? comfortableTop - safeTop : 0
    }
}

private struct TopChromeInset: ViewModifier {
    var onExtraChange: (CGFloat) -> Void = { _ in }

    @State private var safeTop: CGFloat = TopChromeMetrics.comfortableTop

    func body(content: Content) -> some View {
        content
            .padding(.top, TopChromeMetrics.extra(forSafeTop: safeTop))
            .background {
                Color.clear
                    .ignoresSafeArea(edges: .top)
                    .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeTop = $0 }
            }
            .onChange(of: TopChromeMetrics.extra(forSafeTop: safeTop), initial: true) { _, extra in
                onExtraChange(extra)
            }
    }
}

extension View {
    func topChromeInset(onExtraChange: @escaping (CGFloat) -> Void = { _ in }) -> some View {
        modifier(TopChromeInset(onExtraChange: onExtraChange))
    }
}

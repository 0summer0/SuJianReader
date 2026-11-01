import SwiftUI
import UIKit

struct MacPaperTitlebar: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        let coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onWindow = { [weak view] in
            guard let view else { return }
            coordinator.apply(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        context.coordinator.apply(from: uiView)
    }

    final class Probe: UIView {
        var onWindow: () -> Void = {}
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            onWindow()
        }
    }

    final class Coordinator {
        private var toolbar: UIToolbar?

        func apply(from view: UIView) {
            DispatchQueue.main.async { [weak view] in
                guard let window = view?.window else { return }
                window.backgroundColor = QuietBeauty.paper.uiColor
                #if targetEnvironment(macCatalyst)
                guard let titlebar = window.windowScene?.titlebar else { return }
                titlebar.titleVisibility = .hidden
                titlebar.separatorStyle = UITitlebarSeparatorStyle.none
                let bar = self.toolbar ?? UIToolbar()
                self.toolbar = bar
                let appearance = UIToolbarAppearance()
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = QuietBeauty.paper.uiColor
                appearance.shadowColor = .clear
                bar.standardAppearance = appearance
                bar.scrollEdgeAppearance = appearance
                bar.compactAppearance = appearance
                bar.compactScrollEdgeAppearance = appearance
                bar.isTranslucent = false
                if titlebar.toolbar !== bar {
                    titlebar.toolbar = bar
                }
                #endif
            }
        }
    }
}

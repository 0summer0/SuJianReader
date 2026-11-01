import SwiftUI
import UIKit

struct SearchChrome: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.apply()
    }

    final class Probe: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.applyNow()
            }
        }

        private func applyNow() {
            guard let item = navigationItemInChain() else { return }
            let search = item.searchController
            search?.obscuresBackgroundDuringPresentation = false
            search?.hidesNavigationBarDuringPresentation = false
            item.searchBarPlacementAllowsToolbarIntegration = true
        }

        private func navigationItemInChain() -> UINavigationItem? {
            var responder: UIResponder? = self
            while let next = responder?.next {
                if let controller = next as? UIViewController,
                   let navigation = controller.navigationController,
                   navigation.viewControllers.contains(controller) {
                    return controller.navigationItem
                }
                responder = next
            }
            return nil
        }
    }
}

@Observable
final class DialogGate {
    var isPresented = false {
        didSet {
            if oldValue, !isPresented {
                hiddenAt = Date()
            }
        }
    }

    private var hiddenAt: Date?
    private var ignoreNextDismiss = false
    private var generation = 0

    func present() {
        let justClosed = hiddenAt.map { Date().timeIntervalSince($0) < 0.5 } ?? false
        generation += 1
        let token = generation
        if isPresented || justClosed {
            ignoreNextDismiss = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard token == self.generation, self.ignoreNextDismiss else { return }
                self.ignoreNextDismiss = false
            }
        }
        if isPresented {
            isPresented = false
            Task { @MainActor in
                await Task.yield()
                guard token == self.generation else { return }
                self.isPresented = true
            }
        } else {
            isPresented = true
        }
    }

    fileprivate func receive(_ shown: Bool) {
        if !shown, ignoreNextDismiss {
            ignoreNextDismiss = false
            return
        }
        isPresented = shown
    }
}

struct DeletionDialog: ViewModifier {
    var gate: DialogGate
    let count: Int
    let message: String
    let confirm: () -> Void

    func body(content: Content) -> some View {
        let _ = gate.isPresented
        content.confirmationDialog(
            "删除打开记录？",
            isPresented: Binding(get: { gate.isPresented }, set: { gate.receive($0) }),
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                confirm()
            } label: {
                Text("删除 \(count) 条记录")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct RowDeletionDialog: ViewModifier {
    @State private var isPresented = false
    let message: String
    let confirm: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("删除") { isPresented = true }
                    .tint(QuietBeauty.deletionBackground.color)
            }
            .contextMenu {
                Button("删除记录", role: .destructive) { isPresented = true }
            }
            .confirmationDialog("删除打开记录？", isPresented: $isPresented, titleVisibility: .visible) {
                Button("删除 \(1) 条记录", role: .destructive, action: confirm)
                Button("取消", role: .cancel) {}
            } message: {
                Text(message)
            }
    }
}

struct LibrarySearch: ViewModifier {
    let enabled: Bool
    @Binding var query: String
    var focus: FocusState<Bool>.Binding

    func body(content: Content) -> some View {
        if enabled {
            content
                .searchable(text: $query, prompt: "搜索文稿")
                .searchFocused(focus)
        } else {
            content
        }
    }
}

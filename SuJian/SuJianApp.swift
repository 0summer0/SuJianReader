import SwiftUI
import UIKit

// Remove system shortcuts before registering app shortcuts to avoid UIKit conflicts.

final class MenuCleanupDelegate: UIResponder, UIApplicationDelegate {
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        builder.remove(menu: UIMenu.Identifier("com.apple.menu.open"))
        builder.remove(menu: UIMenu.Identifier("com.apple.menu.find"))
    }
}

@main
struct SuJianApp: App {
    @UIApplicationDelegateAdaptor(MenuCleanupDelegate.self) private var menuCleanup
    @State private var store: LibraryStore
    @State private var places: ReadingPlaceStore
    @State private var intents = WindowIntents()

    init() {
        _store = State(initialValue: LibraryStore())
        _places = State(initialValue: ReadingPlaceStore.shared)
        let ink = QuietBeauty.ink.uiColor
        let bronze = QuietBeauty.bronze.uiColor
        let appearance = UINavigationBarAppearance()

        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = QuietBeauty.paper.uiColor
        appearance.shadowColor = QuietBeauty.hairline.uiColor
        let titleFont = InkFont.uiFont(20, relativeTo: .title3, scaled: false)
        appearance.titleTextAttributes = [
            .foregroundColor: ink,
            .font: titleFont,
            .kern: NSNumber(value: Double(20 * QuietBeauty.headingTracking))
        ]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
        bar.tintColor = bronze
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(store)
                .environment(\.readingPlaces, places)
                .environment(intents)
                .onOpenURL { url in
                    store.acceptIncoming(url)
                }
        }
        .commands {
            SuJianCommands(store: store, intents: intents)
        }
    }
}

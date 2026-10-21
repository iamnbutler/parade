import SwiftUI

/// The system chrome SwiftUI can't style directly — navigation bar titles,
/// tab bar labels, the search field — set once through UIKit's appearance
/// proxies. Native bars stay; they just speak in the book's type.
enum Chrome {
    static func install() {
        #if os(iOS)
        let ink = UIColor(Palette.leather.ink)

        func font(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont(name: name, size: size) ?? .systemFont(ofSize: size)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: base)
        }
        let title = font(Typeface.displayName(italic: false, heavy: true), 20, .headline)
        let largeTitle = font(Typeface.displayName(italic: false, heavy: false), 38, .largeTitle)

        func configure(_ appearance: UINavigationBarAppearance) {
            appearance.titleTextAttributes = [.font: title, .foregroundColor: ink]
            appearance.largeTitleTextAttributes = [.font: largeTitle, .foregroundColor: ink]
        }

        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        configure(scrollEdge)

        let standard = UINavigationBarAppearance()
        if #available(iOS 26, *) {
            // The system's scroll-edge blur does the separating.
            standard.configureWithTransparentBackground()
        } else {
            standard.configureWithDefaultBackground()
            standard.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            standard.backgroundColor = UIColor(Palette.leather.leather).withAlphaComponent(0.7)
            standard.shadowColor = UIColor(Palette.leather.rule)
        }
        configure(standard)

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = standard
        bar.compactAppearance = standard
        bar.scrollEdgeAppearance = scrollEdge
        bar.compactScrollEdgeAppearance = scrollEdge

        let tabFont = font(Typeface.readingName(italic: false, heavy: false), 11, .caption2)
        let tabs = UITabBarAppearance()
        for layout in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            layout.normal.titleTextAttributes = [.font: tabFont]
            layout.selected.titleTextAttributes = [.font: tabFont]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs

        let searchFont = font(Typeface.readingName(italic: false, heavy: false), 17, .body)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = searchFont
        #endif
    }
}

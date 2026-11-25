#if DEBUG
import SwiftUI

/// Debug builds only: `PARADE_SCREEN=<screen>` opens the app on one screen,
/// for screenshots without tapping through. Use it with a test library
/// (`PARADE_TEST_LIBRARY`, or the simulator's own Documents).
///
/// - `tab:to-read`, `tab:collections`, `tab:search`, `tab:settings`: the
///   iPhone opens on that tab; the Mac on that sidebar section
///   (`tab:favorites` and `tab:browse` too).
/// - `tab:settings@age`: Settings with the 18+ confirmation up;
///   `@links`, `@search`, `@about` scroll Settings to that section.
/// - `add`, `add:to-read`: the Add fics sheet alone.
/// - `restore`, `restore@confirm`: Settings › Restore, optionally asking
///   to restore its first earlier version.
/// - `fic:<title>`: that fic's page (on the Mac, selected in the library).
///   `@change` opens its Change Link box; `@restore` asks to restore its
///   earlier version.
/// - `reader:<title>`: the reader on that fic.
/// - `search-form[@section]`: the search form alone (see ContentView).
enum DebugScreen {
    static let requested: String? = ProcessInfo.processInfo.environment["PARADE_SCREEN"]

    /// The screen without its "@variant".
    static var base: String? { requested?.components(separatedBy: "@").first }
    static var variant: String? {
        guard let parts = requested?.components(separatedBy: "@"), parts.count > 1 else { return nil }
        return parts[1]
    }

    static func `is`(_ screen: String, _ variant: String? = nil) -> Bool {
        base == screen && (variant == nil || self.variant == variant)
    }

    /// The tab or sidebar section named by `tab:<name>`.
    static var tab: String? {
        guard let base, base.hasPrefix("tab:") else { return nil }
        return String(base.dropFirst(4))
    }

    /// The fic title named by `fic:` or `reader:`.
    static func title(_ prefix: String) -> String? {
        guard let base, base.hasPrefix(prefix + ":") else { return nil }
        return String(base.dropFirst(prefix.count + 1))
    }

    /// Screens drawn alone, in place of the app (as their sheet or page
    /// shows them); nil for the app itself.
    static var standalone: Bool {
        guard let base else { return false }
        #if os(macOS)
        // The Mac shows a fic selected in its own window.
        if base.hasPrefix("fic:") { return false }
        #endif
        return base == "add" || base.hasPrefix("add:") || base == "restore"
            || base.hasPrefix("fic:") || base.hasPrefix("reader:")
    }

    static var opensChangeLink: Bool { variant == "change" }
}

/// A screen from `PARADE_SCREEN`, drawn alone once the library has loaded.
struct DebugScreenView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
            .onAppear { model.refreshLibrary() }
    }

    private func item(titled title: String) -> LibraryItem? {
        (model.flatItems(.title) + model.toRead).first { $0.title == title }
    }

    @ViewBuilder
    private var content: some View {
        if DebugScreen.base == "add" {
            AddFicSheet()
        } else if DebugScreen.base == "add:to-read" {
            AddFicSheet(toRead: true)
        } else if DebugScreen.base == "restore" {
            NavigationStack { RestoreView() }
        } else if let title = DebugScreen.title("fic") {
            if let item = item(titled: title) {
                NavigationStack {
                    FicDetailView(item: item)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).leatherBackground()
            }
        } else if let title = DebugScreen.title("reader") {
            if let item = item(titled: title) {
                NavigationStack {
                    ReaderView(item: item)
                        .navigationTitle(item.title)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Done") {} }
                        }
                        #endif
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).leatherBackground()
            }
        }
    }
}
#endif

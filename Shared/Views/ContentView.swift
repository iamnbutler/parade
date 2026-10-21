import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        themedRoot
            .palette(.leather)
            .font(TextRole.body.font)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var themedRoot: some View {
        #if DEBUG
        if ThemeGallery.requested != nil {
            ThemeGallery()
                .palette(ThemeGallery.requested?.contains("noir") == true ? .noir : .leather)
        } else {
            appRoot
        }
        #else
        appRoot
        #endif
    }

    private var appRoot: some View {
        root
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    ToastView(text: toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.toast)
    }

    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        MacRootView()
            .frame(minWidth: 700, minHeight: 420)
        #else
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("Browse", systemImage: "tag") }
            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "star") }
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "rectangle.stack.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        #endif
    }
}

/// A short floating message, e.g. the result of updating one fic.
private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TextRole.dek.font)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .embossed(cornerRadius: 22, lifted: true)
            .padding(.horizontal, 24)
            #if os(iOS)
            .padding(.bottom, 96)  // clear the tab bar
            #else
            .padding(.bottom, 20)
            #endif
            .allowsHitTesting(false)
    }
}

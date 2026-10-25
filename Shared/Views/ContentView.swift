import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var themeStore = ThemeStore.shared
    #if os(iOS)
    /// The fic open to read. Presented here, at the root, not from the fic's
    /// page: the pager rebuilds its pages as the library refreshes, and a
    /// cover hung off one of them was dismissed along with it.
    @State private var reading: LibraryItem?
    #endif

    var body: some View {
        themedRoot
            .themedWindow()
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
            // Settings › Type: every text role reads this, so a change shows
            // everywhere at once.
            .environment(\.typeTheme, themeStore.theme)
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
        .environment(\.readFic) { reading = $0 }
        .fullScreenCover(item: $reading) { item in
            NavigationStack {
                ReaderView(item: item)
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { reading = nil }
                        }
                    }
            }
            .themedWindow()
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

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(macOS)
        MacRootView()
            .frame(minWidth: 700, minHeight: 420)
        #else
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            BrowseView()
                .tabItem { Label("Fandoms", systemImage: "theatermasks") }
            FavoritesView()
                .tabItem { Label("Favorites", systemImage: "star") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        #endif
    }
}

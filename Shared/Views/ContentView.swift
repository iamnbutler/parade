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
            SeriesView()
                .tabItem { Label("Series", systemImage: "square.stack") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        #endif
    }
}

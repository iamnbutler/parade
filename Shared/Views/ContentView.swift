import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 400)
        #endif
    }
}

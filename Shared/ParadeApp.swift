import SwiftUI

@main
struct ParadeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
        }
        #if os(macOS)
        MenuBarExtra("Parade", systemImage: "books.vertical.fill") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

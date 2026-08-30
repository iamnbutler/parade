import SwiftUI

@main
struct ParadeApp: App {
    @StateObject private var model = AppModel()
    #if os(macOS)
    @StateObject private var updater = UpdaterModel()
    #endif

    var body: some Scene {
        #if os(macOS)
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
        }
        MenuBarExtra("Parade", systemImage: "books.vertical.fill") {
            MenuBarView()
                .environmentObject(model)
                .environmentObject(updater)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
        }
        #endif
    }
}

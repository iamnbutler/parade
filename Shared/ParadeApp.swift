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
            CommandMenu("Library") {
                Button("Check AO3 for Updates") {
                    Task { await model.checkForUpdates() }
                }
                Button("Import All to Apple Books") {
                    Task { await model.importAllToBooks() }
                }
                Button("Scan Now") { model.scan() }
                    .keyboardShortcut("r")
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

import SwiftUI

@main
struct ParadeApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @StateObject private var updater = UpdaterModel()
    #endif

    init() {
        Typeface.register()
        Chrome.install()
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .defaultAppStorage(AppModel.settingsStore)
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
        // A fic opened to read, in a window of its own.
        WindowGroup("Reader", id: "reader", for: String.self) { $id in
            ReaderWindow(id: id)
                .environmentObject(model)
                .defaultAppStorage(AppModel.settingsStore)
                .themedWindow()
        }
        .defaultSize(width: 760, height: 900)
        // Just the page: no title bar over the text.
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Parade", systemImage: "books.vertical.fill") {
            MenuBarView()
                .environmentObject(model)
                .defaultAppStorage(AppModel.settingsStore)
                .environmentObject(updater)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .defaultAppStorage(AppModel.settingsStore)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refreshLibrary()
                        model.buildDetailsIndex()
                    }
                }
        }
        #endif
    }
}

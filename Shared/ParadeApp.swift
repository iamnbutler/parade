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
                .environment(\.appModel, model)
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
        MenuBarExtra("Parade", systemImage: "books.vertical.fill") {
            MenuBarView()
                .environmentObject(model)
                .environment(\.appModel, model)
                .defaultAppStorage(AppModel.settingsStore)
                .environmentObject(updater)
        }
        .menuBarExtraStyle(.window)
        #else
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(model)
                .environment(\.appModel, model)
                .defaultAppStorage(AppModel.settingsStore)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        model.refreshLibrary()
                        model.buildDetailsIndex()
                    } else {
                        model.flushReadingPositions()
                    }
                }
        }
        #endif
    }
}

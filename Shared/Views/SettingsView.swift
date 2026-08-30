import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFolderPicker = false
    #if os(macOS)
    @State private var showImportPicker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                folderSection
                #if os(macOS)
                booksSection
                #endif
                if !model.statusLines.isEmpty {
                    Section("Activity") {
                        ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.callout.monospaced())
                                .foregroundStyle(line.hasPrefix("⚠️") ? .red : .secondary)
                        }
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Settings")
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setDestination(url) }
        }
        #if os(macOS)
        .fileImporter(isPresented: $showImportPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                Task {
                    await model.mergeFolder(url)
                    if ok { url.stopAccessingSecurityScopedResource() }
                }
            }
        }
        #endif
    }

    private var folderSection: some View {
        Section {
            LabeledContent("Saving to", value: model.destinationLabel)
            Button("Choose Folder…") { showFolderPicker = true }
            if model.usesCustomDestination {
                Button("Use Default Folder", role: .destructive) { model.resetDestination() }
            }
        } header: {
            Text("Library Folder")
        } footer: {
            #if os(iOS)
            Text("Pick a folder in iCloud Drive to sync your library everywhere. Fics are filed as Author/Title.epub. Tap “Books” on a fic to add it to Apple Books.")
            #else
            Text("The library folder is watched: fics that appear in it — downloaded here or synced from the phone — are imported into Apple Books automatically.")
            #endif
        }
    }

    #if os(macOS)
    private var booksSection: some View {
        Section {
            Toggle("Auto-import new fics into Apple Books", isOn: $model.autoImport)
            Button("Add a Folder to Library…") { showImportPicker = true }
            Button("Import All to Apple Books") {
                Task { await model.importAllToBooks() }
            }
            Button("Scan Now") { model.scan() }
        } header: {
            Text("Apple Books")
        } footer: {
            Text("“Add a Folder to Library…” moves an existing [Author]/[epub] tree (like a Calibre library) into the library folder — the watcher then imports new arrivals into Apple Books. “Import All” re-sends everything in the library to Books.")
        }
    }
    #endif
}

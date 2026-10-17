import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    #if os(macOS)
    @State private var showImportPicker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                folderSection
                updatesSection
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
        #if os(macOS)
        .modifier(NeutralFileDialogStart())
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
        } header: {
            Text("Library Folder")
        } footer: {
            if AppModel.testLibrary != nil {
                Text("Test library (debug build): a scratch folder with its own settings. Nothing here touches the real library, iCloud, or Apple Books.")
            } else {
                libraryFooter
            }
        }
    }

    private var libraryFooter: Text {
        #if os(iOS)
        model.inCloud
            ? Text("The library lives in Parade's own iCloud Drive folder and syncs to all your devices automatically. Fics are filed by source: ao3/Author/Title.epub.")
            : Text("iCloud isn't available, so the library is kept on this device only. Fics are filed by source: ao3/Author/Title.epub.")
        #else
        Text("The library lives in iCloud Drive › Parade, synced with your other devices. The folder is watched: fics that appear in it — downloaded here or synced from the phone — can be imported into Apple Books.")
        #endif
    }

    private var updatesSection: some View {
        Section {
            Button {
                Task { await model.checkForUpdates() }
            } label: {
                if model.isCheckingUpdates {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    }
                } else {
                    Text("Check AO3 for Updates")
                }
            }
            .disabled(model.isCheckingUpdates || model.isWorking)
        } header: {
            Text("Fic Updates")
        } footer: {
            #if os(iOS)
            Text("Asks AO3 whether each fic changed since its download — one request per fic, politely spaced, so a big library takes a while. Only runs when you tap it. Fics with an update get a yellow dot; nothing downloads until you swipe one and tap Update. Updating keeps the old version in the Backups folder.")
            #else
            Text("Asks AO3 whether each fic changed since its download — one request per fic, politely spaced, so a big library takes a while. Only runs when you click it. Fics with an update get a yellow dot; nothing downloads until you right-click one and choose Update from AO3. Updating keeps the old version in the Backups folder.")
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

#if os(macOS)
/// "Add a Folder to Library…" moves what it's given, so its picker should
/// never open inside the library itself (the last place a panel showed).
private struct NeutralFileDialogStart: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.fileDialogDefaultDirectory(FileManager.default.homeDirectoryForCurrentUser)
        } else {
            content
        }
    }
}
#endif

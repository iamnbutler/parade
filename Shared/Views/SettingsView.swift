import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    #if os(macOS)
    @State private var showImportPicker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                PageHeader(title: "Settings")
                #endif
                folderSection
                updatesSection
                linkSection
                searchSection
                #if os(macOS)
                folderImportSection
                #endif
                if !model.statusLines.isEmpty {
                    LeatherSection("Activity") {
                        ForEach(Array(model.statusLines.enumerated()), id: \.offset) { _, line in
                            ActivityLine(line: line)
                        }
                    }
                }
            }
            .leatherForm()
            #if os(macOS)
            .formStyle(.grouped)
            .buttonStyle(.leather)
            #endif
            .navigationTitle("Settings")
            .pageTitleInContent()
            #if os(iOS)
            .tabHeader("Settings")
            #endif
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
        // After .fileImporter so it applies to that picker.
        .modifier(NeutralFileDialogStart())
        #endif
    }

    private var folderSection: some View {
        LeatherSection(title: "Library folder") {
            LabeledContent("Saving to", value: model.destinationLabel)
        } footer: {
            if AppModel.testLibrary != nil {
                Text("Test library (debug build): a scratch folder with its own settings. Nothing here touches the real library or iCloud.")
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
        Text("The library lives in iCloud Drive › Parade, synced with your other devices. Fics that appear in it — downloaded here or synced from the phone — show up in the library.")
        #endif
    }

    private var updatesSection: some View {
        LeatherSection(title: "Fic updates") {
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
            .disabled(model.isCheckingUpdates)
        } footer: {
            #if os(iOS)
            Text("Asks AO3 which of your fics changed since the last check, a few hundred per request (the first check of a big library takes a while). Only runs when you tap it. Fics with an update get a gold dot; nothing downloads until you swipe one and tap Update. Updating keeps the old version in the Backups folder.")
            #else
            Text("Asks AO3 which of your fics changed since the last check, a few hundred per request (the first check of a big library takes a while). Only runs when you click it. Fics with an update get a gold dot; nothing downloads until you right-click one and choose Update from AO3. Updating keeps the old version in the Backups folder.")
            #endif
        }
    }

    private var linkSection: some View {
        let count = model.unlinkedItems.count
        return LeatherSection(title: "AO3 links") {
            Button {
                Task { await model.linkNextUnlinked() }
            } label: {
                if model.isLinking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Linking…")
                    }
                } else if count == 0 {
                    Text("Every fic is linked to AO3")
                } else {
                    Text("Link \(min(count, AppModel.linkBatch)) of \(count) Unlinked Fic\(count == 1 ? "" : "s")")
                }
            }
            .disabled(count == 0)
        } footer: {
            Text("Fics downloaded outside Parade have no AO3 link, tags or series. This finds them on AO3 by title and author, 20 at a time and gently paced, and swaps in AO3's own copy where there's exactly one sure match, keeping the old file in Backups. The rest can be matched by hand on their own page.")
        }
    }

    private var searchSection: some View {
        LeatherSection(title: "Search") {
            Button("Clear Search History") { model.clearSearchHistory() }
                .disabled(model.recentSearches.isEmpty)
        } footer: {
            Text("Recent searches show when you tap a search field. They stay on this device.")
        }
    }

    #if os(macOS)
    private var folderImportSection: some View {
        LeatherSection(title: "Bring Fics In") {
            Button("Add a Folder to Library…") { showImportPicker = true }
            Button("Scan Now") { model.scan() }
        } footer: {
            Text("“Add a Folder to Library…” moves an existing [Author]/[epub] tree (like a Calibre library) into the library folder.")
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

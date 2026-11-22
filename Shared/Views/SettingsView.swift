import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    #if os(macOS)
    @State private var showImportPicker = false
    #endif
    @State private var confirmingAge = false

    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                PageHeader(title: "Settings")
                #endif
                folderSection
                updatesSection
                restoreSection
                linkSection
                searchSection
                matureSection
                aboutSection
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
            Text("Asks AO3 which of your fics changed since the last check, a few hundred per request (the first check of a big library takes a while). Only runs when you tap it. Fics with an update get a gold dot; nothing downloads until you swipe one and tap Update. Updating keeps the old version for 30 days, under Restore.")
            #else
            Text("Asks AO3 which of your fics changed since the last check, a few hundred per request (the first check of a big library takes a while). Only runs when you click it. Fics with an update get a gold dot; nothing downloads until you right-click one and choose Update from AO3. Updating keeps the old version for 30 days, under Restore.")
            #endif
        }
    }

    private var restoreSection: some View {
        LeatherSection(title: "Restore") {
            NavigationLink {
                RestoreView()
            } label: {
                Text("Earlier Versions and Deleted Fics")
            }
        } footer: {
            Text("Versions an update replaced, and fics you delete, are kept for 30 days and then removed automatically. They sync with your library through iCloud.")
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
            Text("Fics downloaded outside Parade have no AO3 link, tags or series. This finds them on AO3 by title and author, 20 at a time and gently paced, and swaps in AO3's own copy where there's exactly one sure match, keeping the old file for 30 days, under Restore. The rest can be matched by hand on their own page.")
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

    private var matureSection: some View {
        LeatherSection(title: "Mature works") {
            Toggle("Show mature and explicit works", isOn: Binding(
                get: { model.matureContentAllowed },
                set: { on in
                    if on { confirmingAge = true } else { model.setMatureContent(false) }
                }
            ))
        } footer: {
            Text("Off, Search leaves out works AO3 rates Mature, Explicit or Not Rated. Authors choose their own ratings. Turning this on means you are 18 or older. It only changes Search: fics you save yourself are always in your library.")
        }
        .confirmationDialog("Show mature and explicit works?", isPresented: $confirmingAge, titleVisibility: .visible) {
            Button("I'm 18 or older") { model.setMatureContent(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Works rated Mature or Explicit contain adult themes. Only turn this on if you are 18 or older.")
        }
    }

    private var aboutSection: some View {
        LeatherSection(title: "About Parade") {
            Link("Privacy Policy", destination: ParadeLinks.privacy)
            Link("Support", destination: ParadeLinks.support)
            Link("Report a Work on AO3", destination: ParadeLinks.ao3Report())
        } footer: {
            Text("Parade is unofficial. It isn't affiliated with or endorsed by the Archive of Our Own or the Organization for Transformative Works. It only saves works you choose, to your own device.")
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

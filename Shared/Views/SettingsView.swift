import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    #if os(macOS)
    @State private var showImportPicker = false
    #endif
    @State private var confirmingAge = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                #if os(macOS)
                PageHeader(title: "Settings")
                #endif
                folderSection
                updatesSection
                restoreSection
                linkSection.id("links")
                searchSection.id("search")
                aboutSection.id("about")
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
            #if DEBUG
            .task { await debugScreen(proxy) }
            #endif
            }
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
        LeatherSection("Library") {
            LabeledContent("Saving to", value: model.destinationLabel)
        }
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
            Text("Marks updated fics with a gold dot. Nothing downloads until you update one.")
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
            Text("Kept for 30 days.")
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
            if count > 0 {
                Text("Swaps in AO3's copy where the match is sure. The old file goes to Restore.")
            }
        }
    }

    /// Search's two settings: what it may show, and what it remembers.
    private var searchSection: some View {
        LeatherSection(title: "Search") {
            Toggle("Show mature and explicit works", isOn: Binding(
                get: { model.matureContentAllowed },
                set: { on in
                    if on { confirmingAge = true } else { model.setMatureContent(false) }
                }
            ))
            Button("Clear Search History") { model.clearSearchHistory() }
                .disabled(model.recentSearches.isEmpty)
        } footer: {
            Text("Off, Search also hides works that aren't rated.")
        }
        .confirmationDialog("Show mature and explicit works?", isPresented: $confirmingAge, titleVisibility: .visible) {
            Button("I'm 18 or older") { model.setMatureContent(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Works rated Mature or Explicit contain adult themes.")
        }
    }

    private var aboutSection: some View {
        LeatherSection(title: "About Parade") {
            Link("Privacy Policy", destination: ParadeLinks.privacy)
            Link("Support", destination: ParadeLinks.support)
            Link("Report a Work on AO3", destination: ParadeLinks.ao3Report())
        } footer: {
            Text("Unofficial: not affiliated with or endorsed by the Archive of Our Own or the Organization for Transformative Works.")
        }
    }

    #if os(macOS)
    private var folderImportSection: some View {
        LeatherSection(title: "Import") {
            Button("Add a Folder to Library…") { showImportPicker = true }
        } footer: {
            Text("Moves an Author/Title.epub folder, like a Calibre library, into the library.")
        }
    }
    #endif
}

#if DEBUG
extension SettingsView {
    /// `tab:settings@<section>` scrolls to a section; `@age` asks the 18+
    /// question.
    private func debugScreen(_ proxy: ScrollViewProxy) async {
        guard DebugScreen.tab == "settings", let variant = DebugScreen.variant else { return }
        try? await Task.sleep(for: .milliseconds(600))
        if variant == "age" {
            proxy.scrollTo("search", anchor: .center)
            try? await Task.sleep(for: .milliseconds(300))
            confirmingAge = true
        } else {
            proxy.scrollTo(variant, anchor: .top)
        }
    }
}
#endif

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

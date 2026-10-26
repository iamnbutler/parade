import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var themeStore = ThemeStore.shared
    #if os(macOS)
    @State private var showImportPicker = false
    #endif

    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                PageHeader(title: "Settings")
                #endif
                typeSection
                folderSection
                updatesSection
                linkSection
                searchSection
                #if os(macOS)
                booksSection
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
            .disabled(model.isCheckingUpdates || model.isWorking)
        } footer: {
            #if os(iOS)
            Text("Asks AO3 whether each fic changed since its download — one request per fic, politely spaced, so a big library takes a while. Only runs when you tap it. Fics with an update get a gold dot; nothing downloads until you swipe one and tap Update. Updating keeps the old version in the Backups folder.")
            #else
            Text("Asks AO3 whether each fic changed since its download — one request per fic, politely spaced, so a big library takes a while. Only runs when you click it. Fics with an update get a gold dot; nothing downloads until you right-click one and choose Update from AO3. Updating keeps the old version in the Backups folder.")
            #endif
        }
    }

    private var typeSection: some View {
        LeatherSection(title: "Type") {
            facePicker("Headings", selection: $themeStore.theme.display)
            facePicker("Text", selection: $themeStore.theme.reading)
            themeSlider("Text size", value: $themeStore.theme.textScale, in: 0.85...1.3, step: 0.05, percent: true)
            themeSlider("Headings size", value: $themeStore.theme.headingScale, in: 0.8...1.3, step: 0.05, percent: true)
            themeSlider("Line spacing", value: $themeStore.theme.lineSpacing, in: 0.5...1.8, step: 0.1, percent: true)
            themeSlider("Row spacing", value: $themeStore.theme.rowPadding, in: 0...12, step: 1, percent: false)
            VStack(alignment: .leading, spacing: 6) {
                Text("Preview").textRole(.kicker)
                Text("The Long Way Round").textRole(.title)
                Text("by quillheart · 22,108 words · updated Oct 17").textRole(.meta)
                Text("The road out of the Shire was longer than any of them had guessed, and wetter, and full of second breakfasts.")
                    .textRole(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            Button("Reset to Leather & Ink") { themeStore.theme = .standard }
                .disabled(themeStore.theme == .standard)
        } footer: {
            Text("Changes show everywhere as you make them, the reader included. Stored on this device.")
        }
    }

    private func facePicker(_ label: String, selection: Binding<Face>) -> some View {
        Picker(label, selection: selection) {
            Section("Serif") {
                ForEach(Face.allCases.filter(\.isSerif)) { Text($0.label).tag($0) }
            }
            Section("Sans serif") {
                ForEach(Face.allCases.filter { !$0.isSerif }) { Text($0.label).tag($0) }
            }
        }
    }

    private func themeSlider(_ label: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>,
                             step: CGFloat, percent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(percent ? "\(Int((value.wrappedValue * 100).rounded()))%" : "\(Int(value.wrappedValue)) pt")
                    .textRole(.meta)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: step)
        }
    }

    private var linkSection: some View {
        let count = model.unlinkedItems.count
        return LeatherSection(title: "AO3 links") {
            Button {
                Task { await model.linkAllUnlinked() }
            } label: {
                if model.isLinking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Linking…")
                    }
                } else {
                    Text(count == 0 ? "Every fic is linked to AO3" : "Link \(count) Fic\(count == 1 ? "" : "s") to AO3")
                }
            }
            .disabled(count == 0 || model.isWorking)
        } footer: {
            Text("Fics downloaded outside Parade have no AO3 link, tags or series. This finds each on AO3 by title and author — one request at a time — and swaps in AO3's own copy where there's exactly one sure match, keeping the old file in Backups. The rest can be matched by hand on their own page.")
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
    private var booksSection: some View {
        LeatherSection(title: "Apple Books") {
            Toggle("Auto-import new fics into Apple Books", isOn: $model.autoImport)
            Button("Add a Folder to Library…") { showImportPicker = true }
            Button("Import All to Apple Books") {
                Task { await model.importAllToBooks() }
            }
            Button("Scan Now") { model.scan() }
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

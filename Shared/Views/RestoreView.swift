import SwiftUI
import AO3Kit

/// Settings › Restore: earlier versions that updates replaced, and fics
/// that were deleted, each kept about a month and put back with one tap.
struct RestoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirming: KeptCopy?

    var body: some View {
        Group {
            if model.recentBackups.isEmpty && model.recentlyDeleted.isEmpty {
                EmptyPage(
                    title: "Nothing to restore",
                    message: "When an update replaces a fic, or you delete one, Parade keeps the copy here for 30 days.")
            } else {
                Form {
                    #if os(macOS)
                    PageHeader(title: "Restore")
                    #endif
                    Section {
                        Text("Parade keeps the version an update replaced, and every fic you delete, for 30 days, then removes them on its own. Restoring keeps the copy it replaces, so you can switch back.")
                            .textRole(.meta)
                            .listRowBackground(Color.clear)
                    }
                    LeatherSection("Recently Updated") {
                        if model.recentBackups.isEmpty {
                            Text("No earlier versions from the last 30 days.").textRole(.meta)
                        }
                        ForEach(model.recentBackups) { copy in
                            KeptCopyRow(copy: copy, when: "Backed up") { confirming = copy }
                        }
                    }
                    LeatherSection("Recently Deleted") {
                        if model.recentlyDeleted.isEmpty {
                            Text("Nothing deleted in the last 30 days.").textRole(.meta)
                        }
                        ForEach(model.recentlyDeleted) { copy in
                            KeptCopyRow(copy: copy, when: "Deleted") {
                                Task { await model.restore(copy) }
                            }
                        }
                    }
                }
                .leatherForm()
                #if os(macOS)
                .formStyle(.grouped)
                #endif
            }
        }
        .leatherBackground()
        .navigationTitle("Restore")
        .pageTitleInContent()
        .task { model.refreshKeptCopies() }
        .confirmationDialog(
            "Restore the earlier version of \(confirming?.title.quoted ?? "this fic")?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { copy in
            Button("Restore") { Task { await model.restore(copy) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The copy there now is kept as a backup, so you can switch back.")
        }
    }
}

/// One kept copy: its title, then "by Author · Backed up 3 days ago ·
/// 152 KB", and a Restore button.
struct KeptCopyRow: View {
    let copy: KeptCopy
    /// "Backed up" or "Deleted".
    let when: String
    let restore: () -> Void
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.title).textRole(.rowTitle).lineLimit(2)
                Text(KeptCopyRow.details(copy, when: when)).textRole(.meta)
            }
            Spacer(minLength: 8)
            Button("Restore", action: restore)
                .buttonStyle(.leather)
                .disabled(model.isWorking)
                .help(copy.kind == .trash
                      ? "Put this fic back in \(copy.isToRead ? "To Read" : "your library")"
                      : "Put this version back in place of the current one")
        }
        .padding(.vertical, 2)
    }

    static func details(_ copy: KeptCopy, when: String) -> String {
        var parts = ["by \(copy.author)", "\(when) \(copy.date.formatted(.relative(presentation: .named)))"]
        if let size = copy.size {
            parts.append(Int64(size).formatted(.byteCount(style: .file)))
        } else if !copy.isDownloaded {
            parts.append("in iCloud")
        }
        if copy.isToRead { parts.append("To Read") }
        return parts.joined(separator: " · ")
    }
}

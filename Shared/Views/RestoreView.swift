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
                    message: "Earlier versions and deleted fics stay here for 30 days.")
            } else {
                Form {
                    #if os(macOS)
                    PageHeader(title: "Restore")
                    #endif
                    // A list that's empty says nothing: its heading goes too.
                    if !model.recentBackups.isEmpty {
                        LeatherSection("Recently Updated") {
                            ForEach(model.recentBackups) { copy in
                                KeptCopyRow(copy: copy, when: "Backed up") { confirming = copy }
                            }
                        }
                    }
                    if !model.recentlyDeleted.isEmpty {
                        LeatherSection("Recently Deleted") {
                            ForEach(model.recentlyDeleted) { copy in
                                KeptCopyRow(copy: copy, when: "Deleted") {
                                    Task { await model.restore(copy) }
                                }
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
        .task {
            model.refreshKeptCopies()
            #if DEBUG
            if DebugScreen.is("restore", "confirm") {
                try? await Task.sleep(for: .milliseconds(800))
                confirming = model.recentBackups.first
            }
            #endif
        }
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
                // One line where it fits (the Mac); on a phone, the author
                // on one line and the rest on the next, rather than a wrap
                // that strands "· 2 kB" on a line of its own.
                ViewThatFits(in: .horizontal) {
                    Text(KeptCopyRow.details(copy, when: when)).lineLimit(1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(KeptCopyRow.byline(copy))
                        Text(KeptCopyRow.facts(copy, when: when))
                    }
                }
                .textRole(.meta)
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
        byline(copy) + " · " + facts(copy, when: when)
    }

    static func byline(_ copy: KeptCopy) -> String { "by \(copy.author)" }

    /// "Backed up 3 days ago · 152 KB · To Read".
    static func facts(_ copy: KeptCopy, when: String) -> String {
        var parts = ["\(when) \(copy.date.formatted(.relative(presentation: .named)))"]
        if let size = copy.size {
            parts.append(Int64(size).formatted(.byteCount(style: .file)))
        } else if !copy.isDownloaded {
            parts.append("in iCloud")
        }
        if copy.isToRead { parts.append("To Read") }
        return parts.joined(separator: " · ")
    }
}

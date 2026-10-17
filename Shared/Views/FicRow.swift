import SwiftUI

/// One fic row, shared by every fic list on both platforms.
struct FicRow: View {
    let item: LibraryItem
    /// Show the author in the subtitle (for flat lists without author sections).
    var showsAuthor = false
    /// Set when the row is in a collection's own list: the trailing swipe takes
    /// it out of the collection instead of deleting the file.
    var collection: String?
    /// Which date the subtitle shows — the one the list is sorted by.
    var date: RowDate = .saved
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false
    @State private var showNewCollection = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                    if model.isFavorite(item) {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                subtitle.font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.updating.contains(item.id) {
                ProgressView()
                    .controlSize(.small)
            } else if model.hasUpdate(item) {
                // An update is waiting on AO3.
                Circle()
                    .fill(.yellow)
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("Update available")
            }
            if !item.isDownloaded {
                Label("iCloud…", systemImage: "icloud.and.arrow.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                model.toggleFavorite(item)
            } label: {
                Label(model.isFavorite(item) ? "Unfavorite" : "Favorite",
                      systemImage: model.isFavorite(item) ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
        .swipeActions(edge: .trailing) {
            if let collection {
                Button { model.remove(item, fromCollection: collection) } label: {
                    Label("Remove", systemImage: "rectangle.stack.badge.minus")
                }
                .tint(.orange)
            } else {
                // No .destructive role: that would collapse the row before the
                // confirmation dialog can ask.
                Button { confirmDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(.red)
            }
            Button { Task { await model.update(item) } } label: {
                Label("Update", systemImage: "arrow.down.circle")
            }
            .tint(.blue)
            .disabled(model.isWorking)
        }
        .confirmationDialog(
            "Delete \(item.title.quoted)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.delete(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.inCloud
                ? "Removes the file from your library folder — and, via iCloud, from your other devices. Copies already in Apple Books stay."
                : "Removes the file from your library folder. Copies already in Apple Books stay.")
        }
        .contextMenu {
            Button {
                model.toggleFavorite(item)
            } label: {
                Label(model.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: model.isFavorite(item) ? "star.slash" : "star")
            }
            Menu {
                CollectionMenuItems(item: item, showNewCollection: $showNewCollection)
            } label: {
                Label("Collections", systemImage: "rectangle.stack")
            }
            Button {
                Task { await model.update(item) }
            } label: {
                Label("Update from AO3", systemImage: "arrow.down.circle")
            }
            .disabled(model.isWorking)
            #if os(macOS)
            Button("Add to Apple Books") { model.addToBooks(item) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            #endif
            Divider()
            if let collection {
                Button {
                    model.remove(item, fromCollection: collection)
                } label: {
                    Label("Remove from “\(collection)”", systemImage: "rectangle.stack.badge.minus")
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .newCollectionAlert(isPresented: $showNewCollection, adding: item, model: model)
    }

    private var subtitle: Text {
        let (date, prefix): (Date, String) = switch self.date {
        case .saved: (item.date, "downloaded ")
        case .added: (item.added, "added ")
        case .updated: (model.contentDate(item), "updated ")
        }
        // AO3's update dates are calendar days (stored as UTC midnight);
        // shown in local time they'd land a day early west of UTC.
        var style = Date.FormatStyle(date: showsAuthor ? .abbreviated : .long, time: .omitted)
        if self.date == .updated { style.timeZone = TimeZone(identifier: "UTC")! }
        if showsAuthor {
            return Text("\(item.author) · \(prefix)\(date.formatted(style))")
        } else {
            return Text("\(prefix)\(date.formatted(style))")
        }
    }

}

/// The date a fic row shows.
enum RowDate {
    /// When this EPUB was saved.
    case saved
    /// When the fic first arrived.
    case added
    /// The fic's last content update (from inside the EPUB).
    case updated

    init(_ sort: LibrarySort) {
        switch sort {
        case .added: self = .added
        case .updated: self = .updated
        default: self = .saved
        }
    }
}

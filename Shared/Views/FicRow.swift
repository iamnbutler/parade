import SwiftUI

/// One fic row, shared by the Library and Series lists on both platforms.
struct FicRow: View {
    let item: LibraryItem
    /// Show the author in the subtitle (for flat lists without author sections).
    var showsAuthor = false
    @EnvironmentObject private var model: AppModel
    @State private var confirmDelete = false

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
            if item.isDownloaded {
                booksButton
            } else {
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
            // No .destructive role: that would collapse the row before the
            // confirmation dialog can ask.
            Button { confirmDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
        .confirmationDialog(
            "Delete “\(item.title)”?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { model.delete(item) }
        } message: {
            Text("Removes the file from your library folder — and, via iCloud, from your other devices. Copies already in Apple Books stay.")
        }
        #if os(macOS)
        .contextMenu {
            Button(model.isFavorite(item) ? "Remove from Favorites" : "Add to Favorites") {
                model.toggleFavorite(item)
            }
            Button("Add to Apple Books") { model.addToBooks(item) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        #endif
    }

    private var subtitle: Text {
        if showsAuthor {
            Text("\(item.author) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
        } else {
            Text(item.date, style: .date)
        }
    }

    @ViewBuilder
    private var booksButton: some View {
        #if os(iOS)
        ShareLink(item: item.url) {
            Label("Books", systemImage: "book.closed.fill")
                .labelStyle(.iconOnly)
                .font(.callout)
        }
        .buttonStyle(.borderless)
        #else
        Button {
            model.addToBooks(item)
        } label: {
            Label("Books", systemImage: "book.closed.fill")
                .labelStyle(.titleAndIcon)
                .font(.callout)
        }
        .buttonStyle(.bordered)
        #endif
    }
}

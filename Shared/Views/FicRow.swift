import SwiftUI

/// One fic row, shared by the Library and Series lists on both platforms.
struct FicRow: View {
    let item: LibraryItem
    /// Series part number, when shown inside a series group.
    var part: Int? = nil
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            if let part {
                Text("\(part)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .frame(minWidth: 22)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
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
        .swipeActions {
            Button(role: .destructive) { model.delete(item) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #if os(macOS)
        .contextMenu {
            Button("Add to Apple Books") { model.addToBooks(item) }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            }
            Divider()
            Button("Delete", role: .destructive) { model.delete(item) }
        }
        #endif
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

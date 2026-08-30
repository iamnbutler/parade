import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.libraryError {
                    ContentUnavailableView {
                        Label("Can't read library folder", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") { model.refreshLibrary() }
                    }
                } else if model.library.isEmpty {
                    ContentUnavailableView(
                        "No fics yet",
                        systemImage: "books.vertical",
                        description: Text("Tap + and paste an AO3 link to download your first fic.")
                    )
                } else {
                    List {
                        ForEach(model.library, id: \.author) { group in
                            Section(group.author) {
                                ForEach(group.items) { item in
                                    row(item)
                                }
                            }
                        }
                    }
                    #if os(iOS)
                    .refreshable { model.refreshLibrary() }
                    #endif
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add fic")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFicSheet()
        }
        .onAppear { model.refreshLibrary() }
    }

    private func row(_ item: LibraryItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body.weight(.medium)).lineLimit(1)
                Text(item.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if item.isDownloaded {
                booksButton(item)
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
    private func booksButton(_ item: LibraryItem) -> some View {
        #if os(iOS)
        ShareLink(item: item.url) {
            Label("Books", systemImage: "book.closed.fill")
                .labelStyle(.titleAndIcon)
                .font(.callout)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
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

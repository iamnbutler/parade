import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddSheet = false
    #if os(macOS)
    @State private var selectedID: String?
    #endif

    var body: some View {
        NavigationStack {
            content
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
            #if os(iOS)
                .navigationDestination(for: LibraryItem.self) { item in
                    FicDetailView(item: item)
                }
            #endif
        }
        .sheet(isPresented: $showAddSheet) {
            AddFicSheet()
        }
        .onAppear { model.refreshLibrary() }
    }

    @ViewBuilder
    private var content: some View {
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
            #if os(macOS)
            HStack(spacing: 0) {
                list
                if let item = selectedItem {
                    Divider()
                    FicDetailView(item: item)
                        .frame(width: 320)
                }
            }
            #else
            list
            #endif
        }
    }

    #if os(macOS)
    private var selectedItem: LibraryItem? {
        guard let selectedID else { return nil }
        return model.library.flatMap(\.items).first { $0.id == selectedID }
    }
    #endif

    private var list: some View {
        #if os(macOS)
        List(selection: $selectedID) {
            ForEach(model.library, id: \.author) { group in
                Section(group.author) {
                    ForEach(group.items) { item in
                        row(item).tag(item.id)
                    }
                }
            }
        }
        #else
        List {
            ForEach(model.library, id: \.author) { group in
                Section(group.author) {
                    ForEach(group.items) { item in
                        NavigationLink(value: item) {
                            row(item)
                        }
                    }
                }
            }
        }
        .refreshable { model.refreshLibrary() }
        #endif
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

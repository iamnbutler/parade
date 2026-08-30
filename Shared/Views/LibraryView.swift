#if os(iOS)
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAddSheet = false
    @State private var searchText = ""

    private var groups: [(author: String, items: [LibraryItem])] {
        model.library
            .map { (author: $0.author, items: $0.items.filter { model.item($0, matches: searchText) }) }
            .filter { !$0.items.isEmpty }
    }

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
                .navigationDestination(for: LibraryItem.self) { item in
                    FicDetailView(item: item)
                }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFicSheet()
        }
        .onAppear {
            model.refreshLibrary()
            model.buildDetailsIndex()
        }
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
            List {
                ForEach(groups, id: \.author) { group in
                    Section(group.author) {
                        ForEach(group.items) { item in
                            NavigationLink(value: item) {
                                FicRow(item: item)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
            .refreshable { model.refreshLibrary() }
        }
    }
}
#endif

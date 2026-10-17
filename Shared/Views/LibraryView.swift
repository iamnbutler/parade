#if os(iOS)
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("librarySort.v1") private var sortRaw = LibrarySort.author.rawValue
    @State private var showAddSheet = false
    @State private var searchText = ""

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .author }

    private var sections: [(name: String, items: [LibraryItem])] {
        model.sections(sort)
            .map { (name: $0.name, items: $0.items.filter { model.item($0, matches: searchText) }) }
            .filter { !$0.items.isEmpty }
    }

    private var flatItems: [LibraryItem] {
        // Ordering comes pre-sorted from the model's cache; only the search
        // filter runs per render.
        model.flatItems(sort).filter { model.item($0, matches: searchText) }
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Library")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Picker("Sort", selection: $sortRaw) {
                                ForEach(LibrarySort.allCases) { s in
                                    Text(s.label).tag(s.rawValue)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                        .accessibilityLabel("Sort")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add fic")
                    }
                }
                .ficDestinations()
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
            if model.isMigrating {
                LibraryLoadingView(text: "Moving your library into \(model.destinationLabel)…")
            } else if model.isScanning || !model.hasLoadedOnce {
                LibraryLoadingView(text: "Loading your library…")
            } else {
                ContentUnavailableView(
                    "No fics yet",
                    systemImage: "books.vertical",
                    description: Text("Tap + and paste AO3 links to download your first fics.")
                )
            }
        } else {
            List {
                if sort.isGrouped {
                    ForEach(sections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.items) { item in
                                NavigationLink(value: route(item)) {
                                    // Series sections hold many authors.
                                    FicRow(item: item, showsAuthor: sort == .series)
                                }
                            }
                        }
                    }
                } else {
                    ForEach(flatItems) { item in
                        NavigationLink(value: route(item)) {
                            FicRow(item: item, showsAuthor: true, date: RowDate(sort))
                        }
                    }
                }
                if model.isScanning, !model.hasLoadedOnce {
                    // The first scan is still streaming results in.
                    LibraryLoadingFooter()
                }
            }
            .noSearchResults(for: searchText, when: sort.isGrouped ? sections.isEmpty : flatItems.isEmpty)
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
            .refreshable { model.refreshLibrary() }
        }
    }

    private func route(_ item: LibraryItem) -> FicRoute {
        FicRoute(item: item, list: .library(sort, query: searchText))
    }
}

/// Favorited fics, sorted by title.
struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var items: [LibraryItem] {
        model.favoriteItems.filter { model.item($0, matches: searchText) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.favoriteItems.isEmpty {
                    if model.isMigrating || model.isScanning || !model.hasLoadedOnce {
                        LibraryLoadingView(text: "Loading your library…")
                    } else {
                        ContentUnavailableView(
                            "No favorites yet",
                            systemImage: "star",
                            description: Text("Swipe right on a fic in the Library and tap the star.")
                        )
                    }
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink(value: FicRoute(item: item, list: .favorites(query: searchText))) {
                                FicRow(item: item, showsAuthor: true)
                            }
                        }
                    }
                    .noSearchResults(for: searchText, when: items.isEmpty)
                    .searchable(text: $searchText, prompt: "Filter favorites…")
                    .refreshable { await model.refreshLibraryNow() }
                }
            }
            .navigationTitle("Favorites")
            .ficDestinations()
        }
        .onAppear { model.refreshLibrary() }
    }
}
#endif

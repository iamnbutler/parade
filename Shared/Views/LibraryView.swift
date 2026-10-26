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
                .navigationDestination(for: ToReadRoute.self) { _ in ToReadView() }
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
            EmptyPage(title: "Parade can't read your library folder", message: error) {
                Button("Try again") { model.refreshLibrary() }
            }
            .leatherBackground()
        } else if model.library.isEmpty {
            if model.isMigrating {
                LibraryLoadingView(text: "Moving your library into \(model.destinationLabel)…")
            } else if model.isScanning || !model.hasLoadedOnce {
                LibraryLoadingView(text: "Loading your library…")
            } else {
                EmptyPage(
                    drawing: "EmptyShelf",
                    title: "Nothing on the shelf yet",
                    message: "Paste a link to a work on AO3 and Parade will bring it home.")
                {
                    Button { showAddSheet = true } label: { Label("Add a fic", systemImage: "plus") }
                }
                .leatherBackground()
            }
        } else {
            List {
                if searchText.isEmpty {
                    ContinueReadingRow()
                        .id(ListTop.id)
                    if !model.toRead.isEmpty {
                        NavigationLink(value: ToReadRoute()) {
                            HStack(alignment: .firstTextBaseline) {
                                Label("To Read", systemImage: "bookmark")
                                    .textRole(.rowTitle)
                                Spacer()
                                Numeral(value: model.toRead.count)
                            }
                        }
                        .leatherRows()
                        .id(ToReadRoute())
                    }
                }
                if sort.isGrouped {
                    ForEach(sections, id: \.name) { section in
                        Section {
                            SectionHeading(name: section.name)
                            ForEach(section.items) { item in
                                NavigationLink(value: route(item)) {
                                    // Series sections hold many authors.
                                    FicRow(item: item, showsAuthor: sort.mixesAuthors)
                                }
                            }
                            .leatherRows()
                        }
                    }
                } else {
                    ForEach(flatItems) { item in
                        NavigationLink(value: route(item)) {
                            FicRow(item: item, showsAuthor: true, date: RowDate(sort))
                        }
                    }
                    .leatherRows()
                }
                if model.isScanning, !model.hasLoadedOnce {
                    // The first scan is still streaming results in.
                    LibraryLoadingFooter()
                        .leatherRows()
                }
            }
            .leatherList()
            .backToTop { topRowID }
            .noSearchResults(for: searchText, when: sort.isGrouped ? sections.isEmpty : flatItems.isEmpty)
            .ficSearch(text: $searchText, prompt: "Search titles, tags, summaries…")
            .refreshable { model.refreshLibrary() }
        }
    }

    /// The list's first row, for Back to Top: Continue Reading, To Read, or
    /// the first fic.
    private var topRowID: AnyHashable? {
        if searchText.isEmpty, model.lastReadItem != nil { return ListTop.id }
        if searchText.isEmpty, !model.toRead.isEmpty { return ToReadRoute() }
        return (sort.isGrouped ? sections.first?.items.first : flatItems.first)?.id
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
                        EmptyPage(
                            drawing: "EmptyFavorites",
                            title: "No favorites yet",
                            message: "Swipe right on a fic in your library and tap the star. The ones you keep coming back to gather here.")
                        .leatherBackground()
                    }
                } else {
                    List {
                        ForEach(items) { item in
                            NavigationLink(value: FicRoute(item: item, list: .favorites(query: searchText))) {
                                FicRow(item: item, showsAuthor: true)
                            }
                        }
                        .leatherRows()
                    }
                    .leatherList()
                    .backToTop { items.first?.id }
                    .noSearchResults(for: searchText, when: items.isEmpty)
                    .ficSearch(text: $searchText, prompt: "Filter favorites…")
                    .refreshable { await model.refreshLibraryNow() }
                }
            }
            .navigationTitle("Favorites")
            .ficDestinations()
        }
        // Favorites is the after-hours room: black leather, garnet, gold.
        .palette(.noir)
        .onAppear { model.refreshLibrary() }
    }
}
/// Opens To Read from the library.
struct ToReadRoute: Hashable {}

/// Fics saved to read later, newest first.
struct ToReadView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var showAddSheet = false

    private var items: [LibraryItem] { model.items(for: .toRead(query: searchText)) }

    var body: some View {
        Group {
            if model.toRead.isEmpty {
                EmptyPage(
                    drawing: "EmptyShelf",
                    title: "Nothing to read yet",
                    message: "Fics saved for later wait here, in a folder of their own. Add one to the library when it's a keeper.")
                .leatherBackground()
            } else {
                List {
                    ForEach(items) { item in
                        NavigationLink(value: FicRoute(item: item, list: .toRead(query: searchText))) {
                            FicRow(item: item, showsAuthor: true, date: .added)
                        }
                    }
                    .leatherRows()
                }
                .leatherList()
                .backToTop { items.first?.id }
                .noSearchResults(for: searchText, when: items.isEmpty)
                .ficSearch(text: $searchText, prompt: "Filter to read…")
            }
        }
        .navigationTitle("To Read")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add to To Read")
            }
        }
        .sheet(isPresented: $showAddSheet) { AddFicSheet(toRead: true) }
    }
}
#endif

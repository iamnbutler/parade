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
                .tabHeader(
                    "Library",
                    search: $searchText,
                    prompt: "Search titles, tags, summaries…",
                    onSubmitSearch: { model.rememberSearch($0) },
                    add: ("Add fic", { showAddSheet = true })
                ) {
                    OrderMenu(sortRaw: $sortRaw)
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
            .refreshable { model.refreshLibrary() }
        }
    }

    /// The list's first row, for Back to Top: Continue Reading, To Read, or
    /// the first fic.
    private var topRowID: AnyHashable? {
        if searchText.isEmpty, model.lastReadItem != nil { return ListTop.id }
        return (sort.isGrouped ? sections.first?.items.first : flatItems.first)?.id
    }

    private func route(_ item: LibraryItem) -> FicRoute {
        FicRoute(item: item, list: .library(sort, query: searchText))
    }
}

/// Opens Favorites from the Collections tab.
struct FavoritesRoute: Hashable {}

/// Favorited fics, sorted by title.
struct FavoritesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var items: [LibraryItem] {
        model.favoriteItems.filter { model.item($0, matches: searchText) }
    }

    var body: some View {
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
        // Favorites is the after-hours room: black leather, garnet, gold.
        .palette(.noir)
        .onAppear { model.refreshLibrary() }
    }
}
/// The To Read tab: fics saved to read later, newest first.
struct ToReadView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""
    @State private var showAddSheet = false

    private var items: [LibraryItem] { model.items(for: .toRead(query: searchText)) }

    var body: some View {
        NavigationStack {
            list
                .tabHeader(
                    "To Read",
                    search: $searchText,
                    prompt: "Filter to read…",
                    add: ("Add to To Read", { showAddSheet = true }))
                .ficDestinations()
        }
        .sheet(isPresented: $showAddSheet) { AddFicSheet(toRead: true) }
    }

    @ViewBuilder
    private var list: some View {
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
        }
    }
}

/// "Order ⌄": how the library is sorted and grouped.
private struct OrderMenu: View {
    @Binding var sortRaw: String
    @Environment(\.palette) private var palette

    var body: some View {
        Menu {
            Picker("Order", selection: $sortRaw) {
                ForEach(LibrarySort.allCases) { s in
                    Text(s.label).tag(s.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text("Order").textRole(.small)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.inkSoft)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .embossed(cornerRadius: 15)
        }
        .accessibilityLabel("Order")
    }
}
#endif

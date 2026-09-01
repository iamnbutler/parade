#if os(macOS)
import SwiftUI

/// Standard macOS three-column layout: sidebar (sections) / list / detail,
/// with the system sidebar toggle, collapsing, and resizable columns.
struct MacRootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case library, fandoms, favorites, settings
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .library: "books.vertical"
            case .fandoms: "theatermasks"
            case .favorites: "star"
            case .settings: "gearshape"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @AppStorage("librarySort.v1") private var sortRaw = LibrarySort.author.rawValue
    @State private var section: SidebarSection? = .library
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var showAddSheet = false

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 170)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 280, ideal: 340)
                .toolbar {
                    if section == .library {
                        ToolbarItem {
                            Menu {
                                Picker("Sort", selection: $sortRaw) {
                                    ForEach(LibrarySort.allCases) { s in
                                        Text(s.label).tag(s.rawValue)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .help("Sort the library")
                        }
                    }
                    if section != .settings {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .help("Add fic from an AO3 link")
                        }
                    }
                }
        } detail: {
            if section == .settings {
                ContentUnavailableView("", systemImage: "gearshape")
            } else if let item = selectedItem {
                FicDetailView(item: item)
                    .frame(minWidth: 260)
            } else {
                ContentUnavailableView(
                    "Select a fic", systemImage: "book.closed",
                    description: Text("Details, tags, and the summary show here."))
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

    private var selectedItem: LibraryItem? {
        guard let selectedID else { return nil }
        return model.library.flatMap(\.items).first { $0.id == selectedID }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .settings:
            SettingsView()
        case .fandoms:
            fandomsList
        case .favorites:
            favoritesList
        default:
            libraryList
        }
    }

    // MARK: - favorites

    @ViewBuilder
    private var favoritesList: some View {
        if model.favoriteItems.isEmpty {
            ContentUnavailableView(
                "No favorites yet",
                systemImage: "star",
                description: Text("Right-click a fic and choose Add to Favorites.")
            )
        } else {
            List(selection: $selectedID) {
                ForEach(model.favoriteItems.filter { model.item($0, matches: searchText) }) { item in
                    FicRow(item: item, showsAuthor: true).tag(item.id)
                }
            }
            .searchable(text: $searchText, prompt: "Filter favorites…")
        }
    }

    // MARK: - fandoms (drill into a fandom)

    private var filteredFandoms: [(name: String, items: [LibraryItem])] {
        model.fandomGroups.filter { group in
            searchText.isEmpty
                || group.name.localizedCaseInsensitiveContains(searchText)
                || group.items.contains { model.item($0, matches: searchText) }
        }
    }

    @ViewBuilder
    private var fandomsList: some View {
        if model.fandomGroups.isEmpty {
            if model.isMigrating || model.isScanning || model.isIndexing || !model.hasLoadedOnce {
                LibraryLoadingView(text: "Reading fic details…")
            } else {
                ContentUnavailableView(
                    "Nothing to browse yet",
                    systemImage: "theatermasks",
                    description: Text("Fandom info loads in the background after fics download.")
                )
            }
        } else {
            NavigationStack {
                List {
                    ForEach(filteredFandoms, id: \.name) { group in
                        NavigationLink(value: group.name) {
                            HStack {
                                Text(group.name).lineLimit(1)
                                Spacer()
                                Text("\(group.items.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .navigationDestination(for: String.self) { fandom in
                    List(selection: $selectedID) {
                        ForEach(model.fandomGroups.first { $0.name == fandom }?.items ?? []) { item in
                            FicRow(item: item).tag(item.id)
                        }
                    }
                    .navigationTitle(fandom)
                }
            }
            .searchable(text: $searchText, prompt: "Filter fandoms…")
        }
    }

    // MARK: - library

    private var filteredLibrary: [(author: String, items: [LibraryItem])] {
        model.library
            .map { (author: $0.author, items: $0.items.filter { model.item($0, matches: searchText) }) }
            .filter { !$0.items.isEmpty }
    }

    @ViewBuilder
    private var libraryList: some View {
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
                    description: Text("Click + and paste an AO3 link.")
                )
            }
        } else {
            List(selection: $selectedID) {
                if LibrarySort(rawValue: sortRaw) ?? .author != .author {
                    ForEach(libraryFlat) { item in
                        FicRow(item: item, showsAuthor: true).tag(item.id)
                    }
                } else {
                    ForEach(filteredLibrary, id: \.author) { group in
                        Section(group.author) {
                            ForEach(group.items) { item in
                                FicRow(item: item).tag(item.id)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
        }
    }

    private var libraryFlat: [LibraryItem] {
        // Ordering comes pre-sorted from the model's cache; only the search
        // filter runs per render.
        model.flatItems(LibrarySort(rawValue: sortRaw) ?? .updated)
            .filter { model.item($0, matches: searchText) }
    }

}
#endif

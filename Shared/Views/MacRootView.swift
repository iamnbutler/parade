#if os(macOS)
import SwiftUI

/// Standard macOS three-column layout: sidebar (sections) / list / detail,
/// with the system sidebar toggle, collapsing, and resizable columns.
struct MacRootView: View {
    enum SidebarSection: Hashable {
        case library, browse, favorites, settings
        case collection(String)

        static let main: [SidebarSection] = [.library, .browse, .favorites, .settings]

        var title: String {
            switch self {
            case .library: "Library"
            case .browse: "Browse"
            case .favorites: "Favorites"
            case .settings: "Settings"
            case .collection(let name): name
            }
        }
        var icon: String {
            switch self {
            case .library: "books.vertical"
            case .browse: "tag"
            case .favorites: "star"
            case .settings: "gearshape"
            case .collection: "rectangle.stack"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @AppStorage("librarySort.v1") private var sortRaw = LibrarySort.author.rawValue
    @AppStorage("browseKind.v1") private var kindRaw = TagKind.fandoms.rawValue
    @State private var section: SidebarSection? = .library
    @State private var selectedID: String?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showNewCollection = false
    @State private var renamingCollection: String?
    @State private var deletingCollection: String?

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .author }
    private var kind: TagKind { TagKind(rawValue: kindRaw) ?? .fandoms }

    var body: some View {
        NavigationSplitView {
            sidebar
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
                    if section == .browse {
                        ToolbarItem {
                            Picker("Browse by", selection: $kindRaw) {
                                ForEach(TagKind.allCases) { k in
                                    Text(k.label).tag(k.rawValue)
                                }
                            }
                            .help("Browse by fandom, series, relationship, character, or tag")
                        }
                    }
                    if section != .settings {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showAddSheet = true
                            } label: {
                                Image(systemName: "plus")
                            }
                            .help("Add fics from AO3 links")
                        }
                    }
                }
        } detail: {
            if section == .settings {
                ContentUnavailableView("", systemImage: "gearshape")
            } else if let item = selectedItem {
                // Its own stack, so tags and series in the details can be
                // followed; reset whenever the selection changes.
                NavigationStack {
                    FicDetailView(item: item)
                        .ficDestinations()
                }
                .id(item.id)
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
        .newCollectionAlert(isPresented: $showNewCollection, model: model)
        .collectionNameAlert(
            "Rename Collection",
            isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } }),
            initial: renamingCollection ?? "",
            action: "Rename"
        ) { name in
            guard let old = renamingCollection else { return }
            let clean = name.trimmingCharacters(in: .whitespaces)
            if model.renameCollection(old, to: clean), section == .collection(old) {
                section = .collection(clean)
            }
        }
        .confirmationDialog(
            "Delete the collection “\(deletingCollection ?? "")”?",
            isPresented: Binding(get: { deletingCollection != nil }, set: { if !$0 { deletingCollection = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Collection", role: .destructive) {
                guard let name = deletingCollection else { return }
                if section == .collection(name) { section = .library }
                model.deleteCollection(name)
            }
        } message: {
            Text("The fics in it stay in your library.")
        }
        .onAppear {
            model.refreshLibrary()
            model.buildDetailsIndex()
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(SidebarSection.main, id: \.self) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            Section("Collections") {
                ForEach(model.collections.names, id: \.self) { name in
                    Label(name, systemImage: "rectangle.stack")
                        .tag(SidebarSection.collection(name))
                        .contextMenu {
                            Button("Rename…") { renamingCollection = name }
                            Button("Delete Collection", role: .destructive) { deletingCollection = name }
                        }
                }
                Button {
                    showNewCollection = true
                } label: {
                    Label("New Collection…", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedItem: LibraryItem? {
        guard let selectedID else { return nil }
        return model.item(withID: selectedID)
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch section {
        case .settings:
            SettingsView()
        case .browse:
            browseList
        case .favorites:
            favoritesList
        case .collection(let name):
            collectionList(name)
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

    // MARK: - collections

    @ViewBuilder
    private func collectionList(_ name: String) -> some View {
        let items = model.items(inCollection: name)
        if items.isEmpty {
            ContentUnavailableView(
                "Nothing in this collection yet",
                systemImage: "rectangle.stack",
                description: Text("Right-click any fic and choose Collections › \(name).")
            )
            .navigationTitle(name)
        } else {
            List(selection: $selectedID) {
                ForEach(items.filter { model.item($0, matches: searchText) }) { item in
                    FicRow(item: item, showsAuthor: true, collection: name).tag(item.id)
                }
            }
            .searchable(text: $searchText, prompt: "Filter collection…")
            .navigationTitle(name)
        }
    }

    // MARK: - browse (drill into a fandom, series, tag…)

    private var filteredGroups: [(name: String, items: [LibraryItem])] {
        model.tagGroups(kind).filter { group in
            searchText.isEmpty
                || group.name.localizedCaseInsensitiveContains(searchText)
                || group.items.contains { model.item($0, matches: searchText) }
        }
    }

    @ViewBuilder
    private var browseList: some View {
        if model.tagGroups(kind).isEmpty {
            if model.isMigrating || model.isScanning || model.isIndexing || !model.hasLoadedOnce {
                LibraryLoadingView(text: "Reading fic details…")
            } else {
                ContentUnavailableView(
                    "No \(kind.label.lowercased()) yet",
                    systemImage: "tag",
                    description: Text("Details load in the background after fics download.")
                )
            }
        } else {
            NavigationStack {
                List {
                    ForEach(filteredGroups, id: \.name) { group in
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
                .navigationDestination(for: String.self) { name in
                    List(selection: $selectedID) {
                        ForEach(model.items(for: .tag(TagSelection(kind: kind, name: name)))) { item in
                            FicRow(item: item, showsAuthor: true).tag(item.id)
                        }
                    }
                    .navigationTitle(name)
                }
            }
            // A new kind starts back at its top-level list.
            .id(kind)
            .searchable(text: $searchText, prompt: "Filter \(kind.label.lowercased())…")
        }
    }

    // MARK: - library

    private var filteredSections: [(name: String, items: [LibraryItem])] {
        model.sections(sort)
            .map { (name: $0.name, items: $0.items.filter { model.item($0, matches: searchText) }) }
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
                    description: Text("Click + and paste AO3 links.")
                )
            }
        } else {
            List(selection: $selectedID) {
                if sort.isGrouped {
                    ForEach(filteredSections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.items) { item in
                                FicRow(item: item, showsAuthor: sort == .series).tag(item.id)
                            }
                        }
                    }
                } else {
                    ForEach(libraryFlat) { item in
                        FicRow(item: item, showsAuthor: true, showsAddedDate: sort == .added).tag(item.id)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
        }
    }

    private var libraryFlat: [LibraryItem] {
        // Ordering comes pre-sorted from the model's cache; only the search
        // filter runs per render.
        model.flatItems(sort).filter { model.item($0, matches: searchText) }
    }

}
#endif

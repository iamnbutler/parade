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
    /// The tag opened inside Browse, if any (nil = the list of tags).
    @State private var browseTag: String?
    /// Where Back returns to after following tags from fic details.
    @State private var browseHistory: [(kind: String, tag: String?)] = []

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
                                .pickerStyle(.inline)
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                            .help("Sort the library")
                        }
                    }
                    if section == .browse, browseTag != nil || !browseHistory.isEmpty {
                        ToolbarItem(placement: .navigation) {
                            Button(action: browseBack) {
                                Image(systemName: "chevron.backward")
                            }
                            .help("Back")
                        }
                    }
                    if section == .browse {
                        ToolbarItem {
                            Picker("Browse by", selection: Binding(
                                get: { kindRaw },
                                set: { kindRaw = $0; browseTag = nil; browseHistory = [] }
                            )) {
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
                FicDetailView(item: item)
                    // A tapped tag or series opens in the content column;
                    // the fic stays here.
                    .environment(\.openTag) { tag in
                        if section == .browse {
                            browseHistory.append((kind: kindRaw, tag: browseTag))
                        }
                        section = .browse
                        kindRaw = tag.kind.rawValue
                        browseTag = tag.name
                        searchText = ""
                    }
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
            action: "Rename",
            isValid: { model.collections.isAvailable($0, renaming: renamingCollection) }
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
        .onChange(of: section) { _, new in
            // Leaving Browse closes the open tag; coming back starts at the list.
            if new != .browse {
                browseTag = nil
                browseHistory = []
            }
            // Don't keep showing a fic the new list doesn't contain.
            if let id = selectedID, !visibleIDs(in: new).contains(id) {
                selectedID = nil
            }
        }
    }

    private func browseBack() {
        if let previous = browseHistory.popLast() {
            kindRaw = previous.kind
            browseTag = previous.tag
        } else {
            browseTag = nil
        }
    }

    /// Fic ids the content column lists for a section.
    private func visibleIDs(in section: SidebarSection?) -> Set<String> {
        let items: [LibraryItem]
        switch section {
        case .favorites: items = model.favoriteItems
        case .collection(let name): items = model.items(inCollection: name)
        case .browse:
            items = browseTag.map { model.items(for: .tag(TagSelection(kind: kind, name: $0), query: "")) } ?? []
        case .settings: items = []
        default: return Set(model.flatItems(.title).map(\.id))
        }
        return Set(items.map(\.id))
    }

    private var sidebar: some View {
        List(selection: $section) {
            ForEach(SidebarSection.main, id: \.self) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            Section("Collections") {
                ForEach(model.collections.names, id: \.self) { name in
                    Label(name, systemImage: "rectangle.stack")
                        .badge(model.items(inCollection: name).count)
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
            .navigationTitle("Favorites")
        } else {
            let items = model.favoriteItems.filter { model.item($0, matches: searchText) }
            List(selection: $selectedID) {
                ForEach(items) { item in
                    FicRow(item: item, showsAuthor: true).tag(item.id)
                }
            }
            .noSearchResults(for: searchText, when: items.isEmpty)
            .searchable(text: $searchText, prompt: "Filter favorites…")
            .navigationTitle("Favorites")
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
            .noSearchResults(for: searchText, when: !items.contains { model.item($0, matches: searchText) })
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
            BrowseEmptyView(kind: kind)
                .navigationTitle(kind.label)
        } else {
            Group {
                if let name = browseTag {
                    List(selection: $selectedID) {
                        ForEach(model.items(for: .tag(TagSelection(kind: kind, name: name), query: searchText))) { item in
                            FicRow(item: item, showsAuthor: true).tag(item.id)
                        }
                    }
                    .navigationTitle(name)
                    .noSearchResults(for: searchText, when: model.items(for: .tag(TagSelection(kind: kind, name: name), query: searchText)).isEmpty)
                } else {
                    // Selecting a row opens that tag.
                    List(selection: Binding<String?>(get: { nil }, set: { browseTag = $0 })) {
                        ForEach(filteredGroups, id: \.name) { group in
                            HStack {
                                Text(group.name).lineLimit(1)
                                Spacer()
                                Text("\(group.items.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .tag(group.name)
                        }
                    }
                    .navigationTitle(kind.label)
                    .noSearchResults(for: searchText, when: filteredGroups.isEmpty)
                }
            }
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
                        FicRow(item: item, showsAuthor: true, date: RowDate(sort)).tag(item.id)
                    }
                }
            }
            .noSearchResults(
                for: searchText,
                when: sort.isGrouped ? filteredSections.isEmpty : libraryFlat.isEmpty)
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
            .navigationTitle("Library")
        }
    }

    private var libraryFlat: [LibraryItem] {
        // Ordering comes pre-sorted from the model's cache; only the search
        // filter runs per render.
        model.flatItems(sort).filter { model.item($0, matches: searchText) }
    }

}
#endif

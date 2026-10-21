#if os(macOS)
import SwiftUI

private extension View {
    /// Double-clicking a fic in a list opens it to read — the list's primary
    /// action, so a single click still just selects.
    func readOnDoubleClick(_ model: AppModel) -> some View {
        modifier(ReadOnDoubleClick(model: model))
    }
}

private struct ReadOnDoubleClick: ViewModifier {
    let model: AppModel
    @Environment(\.readFic) private var readFic

    func body(content: Content) -> some View {
        content.contextMenu(forSelectionType: String.self) { _ in
            // Rows keep their own context menus.
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let item = model.item(withID: id), item.isDownloaded else { return }
            readFic?(item)
        }
    }
}

/// A part name in the sidebar: gold italic, like "Body and health".
private struct SidebarPart: View {
    let title: String

    var body: some View {
        Text(title)
            .textRole(.kicker)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 4)
    }
}

/// One sidebar link with a faint oldstyle count; the open one is raised.
private struct SidebarRow: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.reading(15, relativeTo: .body))
                    .foregroundStyle(selected || hovering ? palette.ink : palette.ink.opacity(0.86))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let count { Numeral(value: count, size: 14) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selected { Color.clear.embossed(cornerRadius: 8) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Standard macOS three-column layout: sidebar (sections) / list / detail,
/// with the system sidebar toggle, collapsing, and resizable columns.
struct MacRootView: View {
    enum SidebarSection: Hashable {
        case library, browse, ao3, favorites, settings
        case collection(String)

        static let main: [SidebarSection] = [.library, .browse, .ao3, .favorites, .settings]

        var title: String {
            switch self {
            case .library: "Library"
            case .browse: "Browse"
            case .ao3: "Find on AO3"
            case .favorites: "Favorites"
            case .settings: "Settings"
            case .collection(let name): name
            }
        }
        var icon: String {
            switch self {
            case .library: "books.vertical"
            case .browse: "tag"
            case .ao3: "globe"
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
    /// The fic open to read, filling the window.
    @State private var reading: LibraryItem?
    /// Where the window's leather backdrop sits, so the sidebar can show the
    /// matching slice of it.
    @State private var backdropFrame: CGRect = .zero
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
    /// AO3 search: kept while you move around the app, so coming back
    /// doesn't fetch again.
    @StateObject private var ao3 = AO3Browser()
    @State private var ao3Selection: Int?

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .author }
    private var kind: TagKind { TagKind(rawValue: kindRaw) ?? .fandoms }

    var body: some View {
        if let reading {
            // Reading takes the whole window; Back (or Esc) returns to the
            // library as it was.
            ReaderView(item: reading)
                .navigationTitle(reading.title)
                .pageTitleInContent()
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            self.reading = nil
                        } label: {
                            Label("Library", systemImage: "chevron.backward")
                        }
                        .help("Back to the library")
                        .keyboardShortcut(.cancelAction)
                    }
                }
        } else {
            library
                .environment(\.readFic) { reading = $0 }
        }
    }

    private var library: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 210)
        } content: {
            contentColumn
                .environment(\.leatherBackdrop, true)
                // Every state of the column, empty and loading included,
                // titles itself in the page, not the toolbar.
                .pageTitleInContent()
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
            detailColumn
                // Favorites is Noir end to end, the open fic included.
                .palette(windowPalette)
                .environment(\.leatherBackdrop, true)
        }
        // One sheet of leather behind the list and the fic, so the light and
        // vignette run across the window instead of restarting per column.
        .background {
            GeometryReader { geo in
                LeatherBackground()
                    .environment(\.palette, windowPalette)
                    .onAppear { backdropFrame = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, frame in backdropFrame = frame }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAddSheet) {
            AddFicSheet()
        }
        .newCollectionAlert(isPresented: $showNewCollection, model: model)
        .collectionNameAlert(
            "Rename collection",
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

    @ViewBuilder
    private var detailColumn: some View {
        if section == .settings {
            Color.clear.leatherBackground()
        } else if section == .ao3 {
            if let id = ao3Selection, let work = ao3.works.first(where: { $0.id == id }) {
                BlurbDetailView(work: work, browser: ao3)
                    .frame(minWidth: 260)
            } else {
                EmptyPage(
                    drawing: "OpenBook",
                    title: "Choose a work",
                    message: "Its summary and tags open here, with Download.")
                .leatherBackground()
            }
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
            EmptyPage(
                drawing: "OpenBook",
                title: "Choose a fic",
                message: "Its summary, tags and series open here.")
            .leatherBackground()
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
        case .settings, .ao3: items = []
        default: return Set(model.flatItems(.title).map(\.id))
        }
        return Set(items.map(\.id))
    }

    /// The book's contents rather than a source list: the app's name in
    /// italic, parts in gold italic, and the open section as an embossed
    /// pill.
    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Parade")
                    .font(.display(28, relativeTo: .largeTitle, italic: true))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                sidebarRow(.library, count: model.library.reduce(0) { $0 + $1.items.count })
                sidebarRow(.browse)
                sidebarRow(.ao3)
                sidebarRow(.favorites, count: model.favoriteItems.count)
                SidebarPart(title: "Collections")
                ForEach(model.collections.names, id: \.self) { name in
                    sidebarRow(.collection(name), count: model.items(inCollection: name).count)
                        .contextMenu {
                            Button("Rename…") { renamingCollection = name }
                            Button("Delete Collection", role: .destructive) { deletingCollection = name }
                        }
                }
                Button {
                    showNewCollection = true
                } label: {
                    Text("New collection…")
                        .textRole(.meta)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 24)
                sidebarRow(.settings)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
        // The same sheet of leather, seen through the floating sidebar with a
        // little shade — one gradient across the window, not a second one.
        .background {
            BackdropSlice(backdrop: backdropFrame)
                .environment(\.palette, windowPalette)
                .overlay(Color.black.opacity(0.2))
                .ignoresSafeArea()
        }
        // Favorites turns the whole window Noir, contents included.
        .palette(windowPalette)
    }

    /// The sidebar sits a shade deeper than the page.
    /// Noir in Favorites, Leather everywhere else.
    private var windowPalette: Palette {
        section == .favorites ? .noir : .leather
    }


    private func sidebarRow(_ s: SidebarSection, count: Int? = nil) -> some View {
        SidebarRow(title: s.title, count: count, selected: section == s) { section = s }
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
        case .ao3:
            AO3SearchPage(browser: ao3, selection: $ao3Selection)
                .navigationTitle("Find on AO3")
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
            EmptyPage(
                drawing: "EmptyFavorites",
                title: "No favorites yet",
                message: "Right-click a fic and choose Add to Favorites. The ones you keep coming back to gather here.")
            .leatherBackground()
            .palette(.noir)
            .navigationTitle("Favorites")
        } else {
            let items = model.favoriteItems.filter { model.item($0, matches: searchText) }
            List(selection: $selectedID) {
                PageHeader(title: "Favorites", subtitle: ficCount(model.favoriteItems.count))
                ForEach(items) { item in
                    FicRow(item: item, showsAuthor: true).tag(item.id)
                }
                .leatherRows()
            }
            .leatherList()
            .readOnDoubleClick(model)
            .palette(.noir)
            .noSearchResults(for: searchText, when: items.isEmpty)
            .searchable(text: $searchText, prompt: "Filter favorites…")
            .navigationTitle("Favorites")
            .pageTitleInContent()
        }
    }

    // MARK: - collections

    @ViewBuilder
    private func collectionList(_ name: String) -> some View {
        let items = model.items(inCollection: name)
        if items.isEmpty {
            EmptyPage(
                title: "Nothing in this collection yet",
                message: "Right-click any fic and choose Collections › \(name).")
            .leatherBackground()
            .navigationTitle(name)
        } else {
            List(selection: $selectedID) {
                PageHeader(title: name, subtitle: ficCount(items.count))
                ForEach(items.filter { model.item($0, matches: searchText) }) { item in
                    FicRow(item: item, showsAuthor: true, collection: name).tag(item.id)
                }
                .leatherRows()
            }
            .leatherList()
            .readOnDoubleClick(model)
            .noSearchResults(for: searchText, when: !items.contains { model.item($0, matches: searchText) })
            .searchable(text: $searchText, prompt: "Filter collection…")
            .navigationTitle(name)
            .pageTitleInContent()
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
            VStack(alignment: .leading, spacing: 0) {
                PageHeader { browseKindMenu }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                BrowseEmptyView(kind: kind)
            }
            .leatherBackground()
            .navigationTitle(kind.label)
            .pageTitleInContent()
        } else {
            Group {
                if let name = browseTag {
                    List(selection: $selectedID) {
                        PageHeader(title: name, subtitle: kind.label)
                        ForEach(model.items(for: .tag(TagSelection(kind: kind, name: name), query: searchText))) { item in
                            FicRow(item: item, showsAuthor: true).tag(item.id)
                        }
                        .leatherRows()
                    }
                    .leatherList()
                    .readOnDoubleClick(model)
                    .navigationTitle(name)
                    .noSearchResults(for: searchText, when: model.items(for: .tag(TagSelection(kind: kind, name: name), query: searchText)).isEmpty)
                } else {
                    // Selecting a row opens that tag.
                    List(selection: Binding<String?>(get: { nil }, set: { browseTag = $0 })) {
                        PageHeader(subtitle: filteredGroups.count == 1
                                   ? "1 \(kind.singular)"
                                   : "\(filteredGroups.count) \(kind.label.lowercased())") {
                            browseKindMenu
                        }
                        ForEach(filteredGroups, id: \.name) { group in
                            HStack(alignment: .firstTextBaseline) {
                                Text(group.name).textRole(.rowTitle).lineLimit(1)
                                Spacer()
                                Numeral(value: group.items.count)
                            }
                            .padding(.vertical, 4)
                            .tag(group.name)
                        }
                        .leatherRows()
                    }
                    .leatherList()
                    .navigationTitle(kind.label)
                    .noSearchResults(for: searchText, when: filteredGroups.isEmpty)
                }
            }
            .searchable(text: $searchText, prompt: "Filter \(kind.label.lowercased())…")
            .pageTitleInContent()
        }
    }

    /// "Fandoms ⌄": what Browse lists, chosen from the page title.
    private var browseKindMenu: some View {
        TitleMenu(title: kind.label) {
            Picker("Browse by", selection: Binding(
                get: { kindRaw },
                set: { kindRaw = $0; browseTag = nil; browseHistory = [] }
            )) {
                ForEach(TagKind.allCases) { k in
                    Text(k.label).tag(k.rawValue)
                }
            }
            .pickerStyle(.inline)
        }
        .help("Browse by fandom, series, relationship, character, or tag")
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
            List(selection: $selectedID) {
                PageHeader(title: "Library", subtitle: librarySubtitle)
                if sort.isGrouped {
                    ForEach(filteredSections, id: \.name) { section in
                        Section {
                            ForEach(section.items) { item in
                                FicRow(item: item, showsAuthor: sort.mixesAuthors).tag(item.id)
                            }
                            .leatherRows()
                        } header: {
                            SectionHeading(name: section.name)
                        }
                    }
                } else {
                    ForEach(libraryFlat) { item in
                        FicRow(item: item, showsAuthor: true, date: RowDate(sort)).tag(item.id)
                    }
                    .leatherRows()
                }
            }
            .leatherList()
            .readOnDoubleClick(model)
            .noSearchResults(
                for: searchText,
                when: sort.isGrouped ? filteredSections.isEmpty : libraryFlat.isEmpty)
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
            .navigationTitle("Library")
            .pageTitleInContent()
        }
    }

    /// "11 fics, by author".
    private var librarySubtitle: String {
        let count = model.library.reduce(0) { $0 + $1.items.count }
        let order = sort.label.lowercased()
        return "\(ficCount(count)), \(order.hasPrefix("by ") ? order : "by " + order)"
    }

    private var libraryFlat: [LibraryItem] {
        // Ordering comes pre-sorted from the model's cache; only the search
        // filter runs per render.
        model.flatItems(sort).filter { model.item($0, matches: searchText) }
    }

}
#endif

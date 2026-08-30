#if os(macOS)
import SwiftUI

/// Standard macOS three-column layout: sidebar (sections) / list / detail,
/// with the system sidebar toggle, collapsing, and resizable columns.
struct MacRootView: View {
    enum SidebarSection: String, CaseIterable, Identifiable {
        case library, fandoms, series, settings
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var icon: String {
            switch self {
            case .library: "books.vertical"
            case .fandoms: "theatermasks"
            case .series: "square.stack"
            case .settings: "gearshape"
            }
        }
    }

    @EnvironmentObject private var model: AppModel
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
        case .series:
            seriesList
        default:
            libraryList
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
            ContentUnavailableView(
                "Nothing to browse yet",
                systemImage: "theatermasks",
                description: Text("Fandom info loads in the background after fics download.")
            )
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
            ContentUnavailableView(
                "No fics yet",
                systemImage: "books.vertical",
                description: Text("Click + and paste an AO3 link.")
            )
        } else {
            List(selection: $selectedID) {
                ForEach(filteredLibrary, id: \.author) { group in
                    Section(group.author) {
                        ForEach(group.items) { item in
                            FicRow(item: item).tag(item.id)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter fics, tags, fandoms…")
        }
    }

    // MARK: - series

    private var filteredSeries: [(name: String, items: [(item: LibraryItem, part: Int?)])] {
        model.seriesGroups
            .map { group in
                (name: group.name,
                 items: group.items.filter { model.item($0.item, matches: searchText) })
            }
            .filter { !$0.items.isEmpty }
    }

    @ViewBuilder
    private var seriesList: some View {
        if model.seriesGroups.isEmpty {
            ContentUnavailableView(
                "No series yet",
                systemImage: "square.stack",
                description: Text("Fics that are part of a series show up here. Series info loads in the background.")
            )
        } else {
            List(selection: $selectedID) {
                ForEach(filteredSeries, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items, id: \.item.id) { entry in
                            FicRow(item: entry.item, part: entry.part).tag(entry.item.id)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter series, tags, fandoms…")
        }
    }
}
#endif

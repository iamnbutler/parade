#if os(iOS)
import SwiftUI

/// One fandom, as a navigation value.
struct FandomSelection: Hashable {
    let name: String
}

/// Browse the library grouped by fandom (AO3's word for the franchise/canon)
/// or by AO3 series (an author's multi-part sequence, in reading order).
/// Fandoms are items you drill into; series show inline in reading order.
struct BrowseView: View {
    enum Grouping: String, CaseIterable, Identifiable {
        case fandom = "Fandom"
        case series = "Series"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: AppModel
    @State private var grouping: Grouping = .fandom
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            Group {
                switch grouping {
                case .fandom: fandomList
                case .series: seriesList
                }
            }
            .navigationTitle("Fandoms")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Group by", selection: $grouping) {
                        ForEach(Grouping.allCases) { g in
                            Text(g.rawValue).tag(g)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                }
            }
            .navigationDestination(for: LibraryItem.self) { item in
                FicDetailView(item: item)
            }
            .navigationDestination(for: FandomSelection.self) { fandom in
                FandomFicsView(fandom: fandom.name)
            }
        }
        .onAppear {
            model.refreshLibrary()
            model.buildDetailsIndex()
        }
    }

    // MARK: - fandom list (drill into a fandom)

    private var fandoms: [(name: String, items: [LibraryItem])] {
        model.fandomGroups.filter { group in
            searchText.isEmpty
                || group.name.localizedCaseInsensitiveContains(searchText)
                || group.items.contains { model.item($0, matches: searchText) }
        }
    }

    @ViewBuilder
    private var fandomList: some View {
        if model.fandomGroups.isEmpty {
            ContentUnavailableView(
                "Nothing to browse yet",
                systemImage: "theatermasks",
                description: Text("Fandom info loads in the background after fics download.")
            )
        } else {
            List {
                ForEach(fandoms, id: \.name) { group in
                    NavigationLink(value: FandomSelection(name: group.name)) {
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
            .searchable(text: $searchText, prompt: "Filter fandoms…")
        }
    }

    // MARK: - series grouping (inline, reading order)

    private var seriesGroups: [(name: String, items: [(item: LibraryItem, part: Int?)])] {
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
                description: Text("Fics that are part of an author's series show up here, in reading order.")
            )
        } else {
            List {
                ForEach(seriesGroups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items, id: \.item.id) { entry in
                            NavigationLink(value: entry.item) {
                                FicRow(item: entry.item, part: entry.part)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Filter series, tags, fandoms…")
        }
    }
}

/// The fics inside one fandom.
struct FandomFicsView: View {
    let fandom: String
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var items: [LibraryItem] {
        (model.fandomGroups.first { $0.name == fandom }?.items ?? [])
            .filter { model.item($0, matches: searchText) }
    }

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    FicRow(item: item)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Filter fics…")
        .navigationTitle(fandom)
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

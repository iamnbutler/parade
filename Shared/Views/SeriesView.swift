#if os(iOS)
import SwiftUI

/// Fics grouped by series (from the metadata inside each EPUB), sorted by
/// part number. iOS tab; the Mac equivalent lives in MacRootView.
struct SeriesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var groups: [(name: String, items: [(item: LibraryItem, part: Int?)])] {
        model.seriesGroups
            .map { group in
                (name: group.name,
                 items: group.items.filter { model.item($0.item, matches: searchText) })
            }
            .filter { !$0.items.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.seriesGroups.isEmpty {
                    ContentUnavailableView(
                        "No series yet",
                        systemImage: "books.vertical",
                        description: Text("Fics that are part of a series show up here. Series info loads in the background after fics download.")
                    )
                } else {
                    List {
                        ForEach(groups, id: \.name) { group in
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
            .navigationTitle("Series")
            .navigationDestination(for: LibraryItem.self) { item in
                FicDetailView(item: item)
            }
        }
        .onAppear {
            model.refreshLibrary()
            model.buildDetailsIndex()
        }
    }
}
#endif

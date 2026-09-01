#if os(iOS)
import SwiftUI

/// One fandom, as a navigation value.
struct FandomSelection: Hashable {
    let name: String
}

/// Browse the library by fandom: a list of fandoms to drill into.
/// (A fic's place in an author's series shows in its detail view.)
struct BrowseView: View {
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var fandoms: [(name: String, items: [LibraryItem])] {
        model.fandomGroups.filter { group in
            searchText.isEmpty
                || group.name.localizedCaseInsensitiveContains(searchText)
                || group.items.contains { model.item($0, matches: searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
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
            .navigationTitle("Fandoms")
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

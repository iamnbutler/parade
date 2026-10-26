#if os(iOS)
import SwiftUI

/// Browse the library by fandom, series, relationship, character, or tag:
/// a list of values to drill into. The kind is picked from the toolbar menu.
struct BrowseView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("browseKind.v1") private var kindRaw = TagKind.fandoms.rawValue
    @State private var searchText = ""

    private var kind: TagKind { TagKind(rawValue: kindRaw) ?? .fandoms }

    private var groups: [(name: String, items: [LibraryItem])] {
        model.tagGroups(kind).filter { group in
            searchText.isEmpty
                || group.name.localizedCaseInsensitiveContains(searchText)
                || group.items.contains { model.item($0, matches: searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.tagGroups(kind).isEmpty {
                    BrowseEmptyView(kind: kind)
                } else {
                    List {
                        ForEach(groups, id: \.name) { group in
                            NavigationLink(value: TagSelection(kind: kind, name: group.name)) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(group.name).textRole(.rowTitle).lineLimit(1)
                                    Spacer()
                                    Numeral(value: group.items.count)
                                }
                            }
                        }
                        .leatherRows()
                    }
                    .leatherList()
                    .noSearchResults(for: searchText, when: groups.isEmpty)
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                                prompt: "Filter \(kind.label.lowercased())…")
                    .barHidesOnScrollDown(unless: !searchText.isEmpty)
                    .refreshable { await model.refreshLibraryNow() }
                }
            }
            .navigationTitle(kind.label)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Browse by", selection: $kindRaw) {
                            ForEach(TagKind.allCases) { k in
                                Text(k.label).tag(k.rawValue)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    .accessibilityLabel("Browse by")
                }
            }
            .ficDestinations()
        }
        .onAppear {
            model.refreshLibrary()
            model.buildDetailsIndex()
        }
    }
}
#endif

import SwiftUI
import AO3Kit

/// An author, rating, warning or category, as a navigation value. Browse
/// doesn't group fics by these, so their lists are worked out here from the
/// library and the details index rather than from `tagGroups`.
struct FacetSelection: Hashable {
    enum Kind: String, Hashable {
        case author, rating, warning, category

        var label: String {
            switch self {
            case .author: "Author"
            case .rating: "Rating"
            case .warning: "Warning"
            case .category: "Category"
            }
        }

        func values(in d: WorkDetails) -> [String] {
            switch self {
            case .author: d.authors
            case .rating: d.rating
            case .warning: d.warnings
            case .category: d.categories
            }
        }
    }

    let kind: Kind
    let name: String
}

/// Navigation value for opening one fic from an author, rating… list.
struct FacetFicRoute: Hashable {
    let item: LibraryItem
    let facet: FacetSelection
    let query: String
}

extension AppModel {
    /// Every library fic with one author, rating, warning or category: an
    /// author's by title, the rest by author, then title. Authors also
    /// match on the folder's name, so a fic not yet indexed still shows.
    func items(for facet: FacetSelection, query: String = "") -> [LibraryItem] {
        let matching = library.flatMap(\.items).filter { item in
            if let d = detailsIndex[item.id],
               facet.kind.values(in: d).contains(where: { $0.caseInsensitiveCompare(facet.name) == .orderedSame }) {
                return true
            }
            return facet.kind == .author
                && item.author.components(separatedBy: " & ")
                    .contains { $0.caseInsensitiveCompare(facet.name) == .orderedSame }
        }
        let keyed: [(author: String, title: String, item: LibraryItem)] = matching
            .filter { self.item($0, matches: query) }
            .map { (facet.kind == .author ? "" : $0.author.lowercased(), $0.title.lowercased(), $0) }
        return keyed.sorted { ($0.author, $0.title) < ($1.author, $1.title) }.map(\.item)
    }
}

/// How a tapped author, rating… opens. Unset, it pushes onto the current
/// NavigationStack (iOS); the Mac sets it to show the list in the content
/// column, like `openTag`.
private struct OpenFacetKey: EnvironmentKey {
    static let defaultValue: ((FacetSelection) -> Void)? = nil
}

extension EnvironmentValues {
    var openFacet: ((FacetSelection) -> Void)? {
        get { self[OpenFacetKey.self] }
        set { self[OpenFacetKey.self] = newValue }
    }
}

/// A tappable author, rating…: opens every fic sharing it.
struct FacetLink<Label: View>: View {
    let facet: FacetSelection
    @ViewBuilder let label: Label
    @Environment(\.openFacet) private var openFacet

    var body: some View {
        if let openFacet {
            Button { openFacet(facet) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: facet) { label }
                .buttonStyle(.plain)
        }
    }
}

/// Authors, ratings… as tappable chips, like `TagChips`.
struct FacetChips: View {
    let kind: FacetSelection.Kind
    let values: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(values, id: \.self) { value in
                FacetLink(facet: FacetSelection(kind: kind, name: value)) {
                    Chip(text: value)
                }
            }
        }
    }
}

#if os(iOS)
/// Every fic by one author, or with one rating, warning or category.
struct FacetFicsView: View {
    let facet: FacetSelection
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var items: [LibraryItem] {
        model.items(for: facet, query: searchText)
    }

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: FacetFicRoute(item: item, facet: facet, query: searchText)) {
                    // An author's own list needn't repeat them on every row.
                    FicRow(item: item, showsAuthor: facet.kind != .author)
                }
            }
            .leatherRows()
        }
        .leatherList()
        .backToTop { items.first?.id }
        .noSearchResults(for: searchText, when: items.isEmpty)
        .ficSearch(text: $searchText, prompt: "Filter fics…")
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(facet.name)
    }
}
#endif

import SwiftUI

extension View {
    /// Registers the fic / tag / collection screens on a NavigationStack. Apply
    /// once, at the stack's root.
    func ficDestinations() -> some View {
        modifier(FicDestinations())
    }
}

private struct FicDestinations: ViewModifier {
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: FicRoute.self) { route in
                #if os(iOS)
                FicPager(route: route, items: model.items(for: route.list))
                #else
                FicDetailView(item: route.item)
                #endif
            }
            .navigationDestination(for: TagSelection.self) { tag in
                TagFicsView(tag: tag)
            }
            #if os(iOS)
            .navigationDestination(for: CollectionSelection.self) { collection in
                CollectionFicsView(collection: collection.name)
            }
            #endif
    }
}

#if os(iOS)
/// A fic's detail page that swipes sideways to its neighbors in the list
/// it was opened from.
struct FicPager: View {
    /// Pages either side of the opened fic. A window, not the whole list —
    /// a 100k-fic library shouldn't be laid out to open one page.
    private static let reach = 100

    private let pages: [LibraryItem]
    @State private var currentID: String

    init(route: FicRoute, items: [LibraryItem]) {
        if let i = items.firstIndex(where: { $0.id == route.item.id }) {
            pages = Array(items[max(0, i - Self.reach)..<min(items.count, i + Self.reach + 1)])
        } else {
            pages = [route.item]
        }
        _currentID = State(initialValue: route.item.id)
    }

    private var currentIndex: Int? {
        pages.firstIndex { $0.id == currentID }
    }

    var body: some View {
        // A page-style TabView rather than a paging ScrollView: its
        // selection reliably opens on the tapped fic, where a scroll
        // position set before first layout can be dropped.
        TabView(selection: $currentID) {
            ForEach(pages) { item in
                FicDetailView(item: item)
                    .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle(currentIndex.map { pages[$0].title } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pages.count > 1, let i = currentIndex {
                ToolbarItem(placement: .primaryAction) {
                    Text("\(i + 1) of \(pages.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
#endif

/// Every fic with one tag, fandom, series…
struct TagFicsView: View {
    let tag: TagSelection
    @EnvironmentObject private var model: AppModel
    @State private var searchText = ""

    private var items: [LibraryItem] {
        model.items(for: .tag(tag)).filter { model.item($0, matches: searchText) }
    }

    var body: some View {
        List {
            ForEach(items) { item in
                NavigationLink(value: FicRoute(item: item, list: .tag(tag))) {
                    FicRow(item: item, showsAuthor: true)
                }
            }
        }
        #if os(iOS)
        .searchable(text: $searchText, prompt: "Filter fics…")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .navigationTitle(tag.name)
    }
}

/// How a tapped tag (or series) opens. Unset, it pushes onto the current
/// NavigationStack (iOS); the Mac sets it to show the tag in the content
/// column instead, leaving the fic in the detail pane.
private struct OpenTagKey: EnvironmentKey {
    static let defaultValue: ((TagSelection) -> Void)? = nil
}

extension EnvironmentValues {
    var openTag: ((TagSelection) -> Void)? {
        get { self[OpenTagKey.self] }
        set { self[OpenTagKey.self] = newValue }
    }
}

/// A tappable tag: opens every fic sharing it.
struct TagLink<Label: View>: View {
    let tag: TagSelection
    @ViewBuilder let label: Label
    @Environment(\.openTag) private var openTag

    var body: some View {
        if let openTag {
            Button { openTag(tag) } label: { label }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: tag) { label }
                .buttonStyle(.plain)
        }
    }
}

/// Tags as tappable chips that open every fic sharing that tag.
struct TagChips: View {
    let kind: TagKind
    let values: [String]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(values, id: \.self) { value in
                TagLink(tag: TagSelection(kind: kind, name: value)) {
                    Text(value)
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                // Centered in the row, so mixed-height buttons line up.
                subviews[index].place(
                    at: CGPoint(x: x, y: bounds.minY + row.y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            // Proposing the full width lets an over-long tag wrap instead
            // of overflowing.
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            let w = size.width
            if !row.indices.isEmpty, row.width + spacing + w > width {
                rows.append(row)
                row = Row(y: row.y + row.height + spacing)
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + w
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

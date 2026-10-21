import SwiftUI

// App-level pieces built from the theme: lists on leather, section
// headings, empty and loading states in the book's voice.

extension View {
    /// A List on leather: plain rows on the page, hairline rules, no
    /// system grays.
    func leatherList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .leatherBackground()
    }

    /// Row treatment inside `leatherList()`. Apply to the ForEach.
    func leatherRows() -> some View {
        modifier(LeatherRows())
    }
}

private struct LeatherRows: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparatorTint(palette.rule)
    }
}

/// A list section's heading: a gold italic name, as in the book's contents.
struct SectionHeading: View {
    let name: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).textRole(.kicker).lineLimit(1)
            Spacer()
            if let count { Numeral(value: count, size: 14) }
        }
        .textCase(nil)
        .padding(.top, 6)
    }
}

/// Swipe-action colors: muted to sit on leather, dark enough for white labels.
enum SwipeTint {
    static let favorite = Color(hex: 0x94753F)
    static let update = Color(hex: 0x5E6E78)
    static let remove = Color(hex: 0x8A5A5C)
    static let delete = Color(hex: 0xA2454A)
}

/// An empty screen, spoken in the interface's voice: an optional drawing,
/// a display line, a soft explanation, and what to do.
struct EmptyPage<Actions: View>: View {
    var drawing: String?
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            if let drawing {
                Drawing(name: drawing)
                    .frame(maxWidth: 240, maxHeight: 200)
                    .padding(.bottom, 8)
            }
            Text(title)
                .textRole(.heading)
                .multilineTextAlignment(.center)
            Text(message)
                .textRole(.dek)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            actions
                .buttonStyle(.leather)
                .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyPage where Actions == EmptyView {
    init(drawing: String? = nil, title: String, message: String) {
        self.init(drawing: drawing, title: title, message: message) { EmptyView() }
    }
}

/// A soft-ink drawing from the asset catalog (Shared/Assets.xcassets/Drawings),
/// tinted with the palette's ink so it follows Noir and Paper.
struct Drawing: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}

/// Search came up empty, in the book's voice.
struct NoResultsPage: View {
    let query: String

    var body: some View {
        EmptyPage(
            title: "Nothing matches “\(query)”",
            message: "Try fewer words, or a fandom, tag or author.")
    }
}

/// A list page's own title, set in the book's display type, with a count
/// line beneath ("11 fics, 1 favorite"). On the Mac it replaces the
/// toolbar's system-font title; put it as the first row of the list.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .textRole(.pageTitle)
                .lineLimit(2)
            if let subtitle {
                Text(subtitle).textRole(.meta)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Mac: takes the system-font title out of the toolbar (the page shows
    /// a `PageHeader` instead). The window keeps its title.
    @ViewBuilder
    func pageTitleInContent() -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// A Form on leather: raised rows, gold italic section headings.
    func leatherForm() -> some View {
        scrollContentBackground(.hidden)
            .leatherBackground()
    }
}

/// "11 fics", "1 fic".
func ficCount(_ n: Int) -> String {
    n == 1 ? "1 fic" : "\(n.formatted()) fics"
}

/// A form section on leather: raised rows, a gold italic heading, a soft
/// italic footer.
struct LeatherSection<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @Environment(\.palette) private var palette

    var body: some View {
        Section {
            content
                .listRowBackground(palette.raised)
        } header: {
            Text(title).textRole(.kicker).textCase(nil)
        } footer: {
            footer.textRole(.meta)
        }
    }
}

extension LeatherSection where Footer == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, content: content, footer: { EmptyView() })
    }
}

/// One line of the activity log, in the interface's voice and colors.
struct ActivityLine: View {
    let line: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(line)
            .font(TextRole.meta.font)
            .foregroundStyle(line.hasPrefix("⚠️") ? palette.alert : palette.inkSoft)
    }
}

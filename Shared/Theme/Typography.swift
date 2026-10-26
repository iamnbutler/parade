import SwiftUI
import CoreText

/// Cormorant Garamond for display, Newsreader for reading — §4. Both are
/// bundled (Shared/Fonts, OFL) and scale with Dynamic Type. No sans-serif,
/// no uppercase tracking labels: italic carries the labels.
enum Typeface {
    /// Registers the bundled fonts for this process. Call once at launch,
    /// before any view or appearance proxy asks for them.
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func displayName(italic: Bool, heavy: Bool) -> String {
        switch (italic, heavy) {
        case (false, false): "CormorantGaramond-Medium"
        case (false, true): "CormorantGaramond-SemiBold"
        case (true, false): "CormorantGaramond-Italic"
        case (true, true): "CormorantGaramond-MediumItalic"
        }
    }

    static func readingName(italic: Bool, heavy: Bool) -> String {
        switch (italic, heavy) {
        case (false, false): "Newsreader-Regular"
        case (false, true): "Newsreader-SemiBold"
        case (true, false): "Newsreader-Italic"
        case (true, true): "Newsreader-MediumItalic"
        }
    }
}

extension Font {
    /// Cormorant Garamond: titles, headings, list titles, kickers.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .body,
                        italic: Bool = false, heavy: Bool = false) -> Font {
        .custom(Typeface.displayName(italic: italic, heavy: heavy), size: size, relativeTo: style)
    }

    /// Newsreader: reading text, summaries, captions, UI labels.
    static func reading(_ size: CGFloat, relativeTo style: TextStyle = .body,
                        italic: Bool = false, heavy: Bool = false) -> Font {
        .custom(Typeface.readingName(italic: italic, heavy: heavy), size: size, relativeTo: style)
    }
}

/// The type roles, so screens (and later the reader) share one scale.
enum TextRole {
    /// A screen's own title: "Before you start".
    case pageTitle
    /// A fic's title on its detail page.
    case title
    /// A heading inside a page.
    case heading
    /// A title in a list row.
    case rowTitle
    /// Italic gold label: "The summary", "Begin with", group names.
    case kicker
    /// Faint italic running head: "Library, 3 of 26".
    case runningHead
    /// Reading text.
    case body
    /// Italic soft subtitle under a title.
    case dek
    /// The line under a page or empty-state title: "12 fics, by date added".
    case subtitle
    /// Soft secondary text under a row title.
    case summary
    /// Small italic secondary line: dates, stats, hints.
    case meta
    /// Plain small text: chips, buttons.
    case small

    /// Mac text sits closer to the eye than a phone's; list type runs smaller.
    static var mac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    var font: Font {
        switch self {
        case .pageTitle: .display(34, relativeTo: .largeTitle)
        case .title: .display(30, relativeTo: .title)
        case .heading: .display(23, relativeTo: .title3)
        case .rowTitle: .display(Self.mac ? 17 : 20, relativeTo: .body)
        case .kicker: .display(18, relativeTo: .subheadline, italic: true)
        case .runningHead: .reading(14, relativeTo: .footnote, italic: true)
        case .body: .reading(17, relativeTo: .body)
        case .dek: .reading(17, relativeTo: .body, italic: true)
        case .subtitle: .reading(Self.mac ? 15 : 16, relativeTo: .subheadline, italic: true)
        case .summary: .reading(15, relativeTo: .subheadline)
        case .meta: .reading(Self.mac ? 13 : 14, relativeTo: .footnote, italic: true)
        case .small: .reading(14, relativeTo: .footnote)
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .pageTitle, .title, .heading, .rowTitle, .body: p.ink
        case .kicker: p.gold
        case .dek, .summary, .subtitle, .meta: p.inkSoft
        case .runningHead: p.inkFaint
        case .small: p.inkSoft
        }
    }

    /// Extra space between lines, in points at the default size. Reading
    /// text gets the book's generous 1.7 leading; display type sits tight.
    var lineSpacing: CGFloat {
        switch self {
        case .pageTitle, .title, .heading, .rowTitle: -2
        case .body, .dek: 7
        case .subtitle: 3
        case .summary: 4
        case .meta: 3
        case .kicker, .runningHead, .small: 1
        }
    }
}

private struct RoleStyle: ViewModifier {
    let role: TextRole
    @Environment(\.palette) private var palette
    @ScaledMetric private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .font(role.font)
            .foregroundStyle(role.color(palette))
            .lineSpacing(max(0, role.lineSpacing * scale))
    }
}

extension View {
    func textRole(_ role: TextRole) -> some View {
        modifier(RoleStyle(role: role))
    }
}

/// A count beside a row or sidebar link, in soft ink. Lining figures in the
/// reading face: Cormorant's oldstyle figures are too small to read at this size.
struct Numeral: View {
    let value: Int
    var size: CGFloat = 14
    @Environment(\.palette) private var palette

    var body: some View {
        Text(value, format: .number)
            .font(.reading(size, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(palette.inkSoft)
    }
}

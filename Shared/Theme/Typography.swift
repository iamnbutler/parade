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

    /// The heading face's font name (or a system-face token, see `Face`).
    static func displayName(italic: Bool, heavy: Bool) -> String {
        TypeTheme.current.display.name(italic: italic, heavy: heavy)
    }

    static func readingName(italic: Bool, heavy: Bool) -> String {
        TypeTheme.current.reading.name(italic: italic, heavy: heavy)
    }

    #if os(macOS)
    typealias PlatformFont = NSFont
    #else
    typealias PlatformFont = UIFont
    #endif

    /// A UIKit/AppKit font for a name from `displayName`/`readingName`,
    /// system faces included (they have no PostScript names to ask for).
    static func platformFont(_ name: String, size: CGFloat) -> PlatformFont {
        guard let face = Face.system(token: name) else {
            return PlatformFont(name: name, size: size) ?? .systemFont(ofSize: size)
        }
        let base = PlatformFont.systemFont(ofSize: size, weight: face.heavy ? .semibold : .regular)
        var descriptor = base.fontDescriptor
        #if os(macOS)
        if let design = face.design.flatMap({ descriptor.withDesign($0) }) { descriptor = design }
        if face.italic { descriptor = descriptor.withSymbolicTraits(.italic) }
        return PlatformFont(descriptor: descriptor, size: size) ?? base
        #else
        if let design = face.design.flatMap({ descriptor.withDesign($0) }) { descriptor = design }
        if face.italic, let italic = descriptor.withSymbolicTraits(.traitItalic) { descriptor = italic }
        return PlatformFont(descriptor: descriptor, size: size)
        #endif
    }
}

/// A typeface the reader can choose: the two bundled ones, and the good
/// faces every Mac and iPhone already has.
enum Face: String, CaseIterable, Codable, Identifiable {
    case cormorant, newsreader, newYork, charter, iowan, georgia, palatino
    case sfPro, sfRounded, avenirNext, helvetica

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cormorant: "Cormorant Garamond"
        case .newsreader: "Newsreader"
        case .newYork: "New York"
        case .charter: "Charter"
        case .iowan: "Iowan Old Style"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .sfPro: "SF Pro"
        case .sfRounded: "SF Rounded"
        case .avenirNext: "Avenir Next"
        case .helvetica: "Helvetica Neue"
        }
    }

    var isSerif: Bool {
        switch self {
        case .sfPro, .sfRounded, .avenirNext, .helvetica: false
        default: true
        }
    }

    /// Sizes were set for Cormorant (headings) and Newsreader (text); other
    /// faces read larger or smaller at the same point size.
    func sizeFactor(display: Bool) -> CGFloat {
        switch (self, display) {
        case (.cormorant, true), (.newsreader, false): 1
        case (.cormorant, false): 1.12
        case (.sfPro, true), (.sfRounded, true), (.avenirNext, true), (.helvetica, true): 0.84
        case (_, true): 0.88
        case (.sfPro, false), (.sfRounded, false), (.avenirNext, false), (.helvetica, false): 0.95
        case (_, false): 0.97
        }
    }

    /// PostScript name, or "system|design|italic|heavy" for the system faces.
    func name(italic: Bool, heavy: Bool) -> String {
        func pick(_ r: String, _ b: String, _ i: String, _ bi: String) -> String {
            switch (italic, heavy) {
            case (false, false): r
            case (false, true): b
            case (true, false): i
            case (true, true): bi
            }
        }
        switch self {
        case .cormorant: return pick("CormorantGaramond-Medium", "CormorantGaramond-SemiBold",
                                     "CormorantGaramond-Italic", "CormorantGaramond-MediumItalic")
        case .newsreader: return pick("Newsreader-Regular", "Newsreader-SemiBold",
                                      "Newsreader-Italic", "Newsreader-MediumItalic")
        case .charter: return pick("Charter-Roman", "Charter-Bold", "Charter-Italic", "Charter-BoldItalic")
        case .iowan: return pick("IowanOldStyle-Roman", "IowanOldStyle-Bold",
                                 "IowanOldStyle-Italic", "IowanOldStyle-BoldItalic")
        case .georgia: return pick("Georgia", "Georgia-Bold", "Georgia-Italic", "Georgia-BoldItalic")
        case .palatino: return pick("Palatino-Roman", "Palatino-Bold", "Palatino-Italic", "Palatino-BoldItalic")
        case .avenirNext: return pick("AvenirNext-Regular", "AvenirNext-DemiBold",
                                      "AvenirNext-Italic", "AvenirNext-DemiBoldItalic")
        case .helvetica: return pick("HelveticaNeue", "HelveticaNeue-Medium",
                                     "HelveticaNeue-Italic", "HelveticaNeue-MediumItalic")
        case .newYork, .sfPro, .sfRounded:
            return ["system", rawValue, italic ? "i" : "", heavy ? "b" : ""].joined(separator: "|")
        }
    }

    struct SystemFace {
        var face: Face
        var italic: Bool
        var heavy: Bool
        #if os(macOS)
        var design: NSFontDescriptor.SystemDesign? {
            switch face { case .newYork: .serif; case .sfRounded: .rounded; default: nil }
        }
        #else
        var design: UIFontDescriptor.SystemDesign? {
            switch face { case .newYork: .serif; case .sfRounded: .rounded; default: nil }
        }
        #endif
        var swiftUIDesign: Font.Design {
            switch face { case .newYork: .serif; case .sfRounded: .rounded; default: .default }
        }
    }

    static func system(token: String) -> SystemFace? {
        let parts = token.components(separatedBy: "|")
        guard parts.count == 4, parts[0] == "system", let face = Face(rawValue: parts[1]) else { return nil }
        return SystemFace(face: face, italic: parts[2] == "i", heavy: parts[3] == "b")
    }

    /// A SwiftUI font in this face, scaling with Dynamic Type.
    func font(_ size: CGFloat, relativeTo style: Font.TextStyle, italic: Bool, heavy: Bool,
              display: Bool) -> Font {
        let size = size * sizeFactor(display: display)
        let token = name(italic: italic, heavy: heavy)
        if let system = Face.system(token: token) {
            var font = Font.system(size: UIFontMetricsCompat.scaled(size, style),
                                   weight: heavy ? .semibold : .regular, design: system.swiftUIDesign)
            if italic { font = font.italic() }
            return font
        }
        return .custom(token, size: size, relativeTo: style)
    }
}

/// Dynamic Type scaling for system faces (`.custom(relativeTo:)` does it
/// for named ones).
enum UIFontMetricsCompat {
    static func scaled(_ size: CGFloat, _ style: Font.TextStyle) -> CGFloat {
        #if os(iOS)
        let uiStyle: UIFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return UIFontMetrics(forTextStyle: uiStyle).scaledValue(for: size)
        #else
        return size
        #endif
    }
}

/// The reader's own choice of type and spacing (Settings › Type). Stored
/// per device; `current` is what the font helpers read.
struct TypeTheme: Codable, Equatable {
    var display: Face = .cormorant
    var reading: Face = .newsreader
    /// Interface text, as a multiple of the designed sizes.
    var textScale: CGFloat = 1
    /// Titles and headings, on top of `textScale`.
    var headingScale: CGFloat = 1
    /// Leading, as a multiple of each role's.
    var lineSpacing: CGFloat = 1
    /// Extra room above and below each list row, in points.
    var rowPadding: CGFloat = 0

    static let standard = TypeTheme()
    nonisolated(unsafe) static var current = TypeTheme.load()

    private static let key = "typeTheme.v1"

    static func load() -> TypeTheme {
        guard let data = UserDefaults.standard.data(forKey: key),
              let theme = try? JSONDecoder().decode(TypeTheme.self, from: data) else { return .standard }
        return theme
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

/// Holds the theme and republishes it, so changing it redraws every
/// `textRole` (and the reader) at once.
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()
    @Published var theme = TypeTheme.current {
        didSet {
            TypeTheme.current = theme
            theme.save()
            Chrome.install()
        }
    }
}

private struct TypeThemeKey: EnvironmentKey {
    static let defaultValue = TypeTheme.standard
}

extension EnvironmentValues {
    var typeTheme: TypeTheme {
        get { self[TypeThemeKey.self] }
        set { self[TypeThemeKey.self] = newValue }
    }
}

extension Font {
    /// The heading face (Cormorant Garamond unless changed): titles,
    /// headings, list titles, kickers.
    static func display(_ size: CGFloat, relativeTo style: TextStyle = .body,
                        italic: Bool = false, heavy: Bool = false) -> Font {
        TypeTheme.current.display.font(size, relativeTo: style, italic: italic, heavy: heavy, display: true)
    }

    /// The text face (Newsreader unless changed): reading text, summaries,
    /// captions, UI labels.
    static func reading(_ size: CGFloat, relativeTo style: TextStyle = .body,
                        italic: Bool = false, heavy: Bool = false) -> Font {
        TypeTheme.current.reading.font(size, relativeTo: style, italic: italic, heavy: heavy, display: false)
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

    var font: Font { font(TypeTheme.current) }

    /// The role's font with a theme's sizes applied.
    func font(_ t: TypeTheme) -> Font {
        let k = t.textScale, h = t.textScale * t.headingScale
        return switch self {
        case .pageTitle: .display(34 * h, relativeTo: .largeTitle)
        case .title: .display(30 * h, relativeTo: .title)
        case .heading: .display(23 * h, relativeTo: .title3)
        case .rowTitle: .display((Self.mac ? 17 : 20) * k, relativeTo: .body)
        case .kicker: .display(18 * k, relativeTo: .subheadline, italic: true)
        case .runningHead: .reading(14 * k, relativeTo: .footnote, italic: true)
        case .body: .reading(17 * k, relativeTo: .body)
        case .dek: .reading(17 * k, relativeTo: .body, italic: true)
        case .subtitle: .reading((Self.mac ? 15 : 16) * k, relativeTo: .subheadline, italic: true)
        case .summary: .reading(15 * k, relativeTo: .subheadline)
        case .meta: .reading((Self.mac ? 13 : 14) * k, relativeTo: .footnote, italic: true)
        case .small: .reading(14 * k, relativeTo: .footnote)
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
    /// Read so a theme change redraws every role.
    @Environment(\.typeTheme) private var theme
    @ScaledMetric private var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .font(role.font(theme))
            .foregroundStyle(role.color(palette))
            .lineSpacing(max(0, role.lineSpacing * scale * theme.lineSpacing * theme.textScale))
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
    @Environment(\.typeTheme) private var theme

    var body: some View {
        Text(value, format: .number)
            .font(.reading(size * theme.textScale, relativeTo: .footnote))
            .monospacedDigit()
            .foregroundStyle(palette.inkSoft)
    }
}

import Foundation
import ZIPFoundation

/// The readable text of an EPUB: its documents in reading order, each turned
/// into a flat run of simple blocks — paragraphs, headings, scene breaks,
/// images, tables — that a native view can lay out. Inline style keeps what
/// fics lean on (italic, bold, underline, strikethrough, super/subscript,
/// links) and paragraphs keep their alignment; fonts, sizes and colors are
/// dropped — the reader supplies its own type.
public struct EPUBBook: Sendable, Equatable {
    public var title: String?
    public var sections: [Section] = []
    /// Image bytes by archive path, for the images the text uses.
    public var images: [String: Data] = [:]

    public init(title: String? = nil, sections: [Section] = [], images: [String: Data] = [:]) {
        self.title = title
        self.sections = sections
        self.images = images
    }

    /// One spine document: a chapter, or AO3's preface or afterword.
    public struct Section: Sendable, Equatable, Identifiable {
        public var id: Int
        /// The table of contents' name for it ("Chapter 1: Tea"), if any.
        public var title: String?
        public var blocks: [Block]
    }

    public struct Block: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case paragraph
            case heading(level: Int)
            /// A scene break (`<hr>`).
            case rule
            /// An archive path (a key of `EPUBBook.images`) or a web URL, and
            /// its alt text.
            case image(source: String, alt: String)
            /// Rows of cells, each cell's runs (a chat log, a letter's header).
            case table(rows: [[[Run]]])
            /// A text-message thread — AO3 work skins mark one up as a `<dl>`:
            /// the contact as a heading, timestamps, then `<dt>` sender and
            /// `<dd>` messages.
            case chat(Chat)
        }

        public enum Alignment: Sendable, Equatable {
            case natural, center, right
        }

        /// What a list item's first paragraph is marked with.
        public enum Marker: Sendable, Equatable {
            case bullet
            case number(Int)
        }

        public var kind: Kind
        public var runs: [Run]
        /// How many blockquotes deep (author's notes, summaries, letters).
        public var quoteDepth: Int
        public var alignment: Alignment = .natural
        /// Set on the first paragraph of a list item.
        public var marker: Marker?
        /// How many lists deep; a list item's later paragraphs keep its indent.
        public var listDepth = 0

        public var text: String { runs.map(\.text).joined() }

        public init(kind: Kind, runs: [Run], quoteDepth: Int, alignment: Alignment = .natural,
                    marker: Marker? = nil, listDepth: Int = 0) {
            self.kind = kind
            self.runs = runs
            self.quoteDepth = quoteDepth
            self.alignment = alignment
            self.marker = marker
            self.listDepth = listDepth
        }
    }

    public struct Chat: Sendable, Equatable {
        /// Who the thread is with ("Unknown Number"), if it names them.
        public var title: String?
        public var items: [Item] = []

        public enum Item: Sendable, Equatable {
            /// A timestamp or other note between messages.
            case note(String)
            case message(sender: String, runs: [Run])
            case image(sender: String, source: String, alt: String)
        }

        public init(title: String? = nil, items: [Item] = []) {
            self.title = title
            self.items = items
        }

        /// Everyone who sends a message, most active first.
        public var senders: [String] {
            var counts: [String: Int] = [:]
            var order: [String] = []
            for case .message(let sender, _) in items {
                if counts[sender] == nil { order.append(sender) }
                counts[sender, default: 0] += 1
            }
            return order.enumerated().sorted {
                (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset)
            }.map(\.element)
        }

        /// The phone's owner — the busiest sender who isn't the contact.
        /// Their messages sit on the right.
        public var me: String? {
            senders.first { !isContact($0) } ?? senders.first
        }

        /// Whether a sender is who the thread is with. Loose: the header
        /// often decorates the name ("Shane ☀️" for "Shane").
        public func isContact(_ sender: String) -> Bool {
            guard let title else { return false }
            let a = Self.letters(title), b = Self.letters(sender)
            return !a.isEmpty && !b.isEmpty && (a.hasPrefix(b) || b.hasPrefix(a))
        }

        private static func letters(_ s: String) -> String {
            // Not CharacterSet.alphanumerics: it counts an emoji's variation
            // selector (U+FE0F) as a "letter".
            String(s.lowercased().unicodeScalars
                .filter { $0.properties.isAlphabetic || $0.properties.numericType != nil }
                .map(Character.init))
        }
    }

    /// A stretch of text with one style.
    public struct Run: Sendable, Equatable {
        public enum Baseline: Sendable, Equatable {
            case normal, superscript, `subscript`
        }

        public var text: String
        public var italic = false
        public var bold = false
        public var underline = false
        public var strikethrough = false
        public var baseline: Baseline = .normal
        public var link: URL?

        /// Everything but the text matches.
        func sameStyle(as other: Run) -> Bool {
            var a = self, b = other
            a.text = ""
            b.text = ""
            return a == b
        }
    }
}

public enum EPUBBookParser {

    /// Reads every spine document of the EPUB at `url`, in order.
    public static func parse(epubAt url: URL) throws -> EPUBBook {
        let archive = try Archive(url: url, accessMode: .read)
        func read(_ path: String) -> String? {
            guard let entry = archive[path] else { return nil }
            var data = Data()
            guard (try? archive.extract(entry, skipCRC32: true) { data.append($0) }) != nil else { return nil }
            return String(data: data, encoding: .utf8)
        }

        let container = read("META-INF/container.xml") ?? ""
        let opfPath = firstMatch(in: container, pattern: #"full-path="([^"]+)""#)
            ?? archive.first { $0.path.lowercased().hasSuffix(".opf") }?.path
        guard let opfPath, let opf = read(opfPath) else {
            throw AO3Error.parseFailed("epub has no package document")
        }
        let base = (opfPath as NSString).deletingLastPathComponent

        let documents = spine(opf: opf)
        let tocTitles = read(resolve(tocPath(opf: opf) ?? "toc.ncx", base: base)).map(ncxTitles) ?? [:]
        // Calibre turns presentational markup (align="center", <s>…) into
        // classes, so class styles come from every stylesheet in the book.
        var classes: [String: CSSStyle] = [:]
        for entry in archive where entry.path.lowercased().hasSuffix(".css") {
            if let css = read(entry.path) { classes.merge(stylesheet(css)) { _, new in new } }
        }

        var book = EPUBBook(title: firstMatch(in: opf, pattern: #"<dc:title>([\s\S]*?)</dc:title>"#)
            .map(HTMLExtract.decodeEntities))
        for (i, href) in documents.enumerated() {
            let path = resolve(href, base: base)
            guard let xhtml = read(path) else { continue }
            let blocks = blocks(fromXHTML: xhtml, classes: classes, base: (path as NSString).deletingLastPathComponent)
            guard !blocks.isEmpty else { continue }
            var sources: [String] = []
            for block in blocks {
                switch block.kind {
                case .image(let source, _): sources.append(source)
                case .chat(let chat):
                    for case .image(_, let source, _) in chat.items { sources.append(source) }
                default: break
                }
            }
            for source in sources where book.images[source] == nil {
                guard let entry = archive[source] else { continue }
                var data = Data()
                if (try? archive.extract(entry, skipCRC32: true) { data.append($0) }) != nil {
                    book.images[source] = data
                }
            }
            book.sections.append(.init(id: i, title: tocTitles[href], blocks: blocks))
        }
        return book
    }

    // MARK: - stylesheets

    /// The parts of CSS a fic's formatting lives in.
    struct CSSStyle: Equatable {
        var italic: Bool?
        var bold: Bool?
        var underline: Bool?
        var strikethrough: Bool?
        var baseline: EPUBBook.Run.Baseline?
        var alignment: EPUBBook.Block.Alignment?
        var hidden = false

        /// Later declarations win, as in CSS.
        mutating func merge(_ other: CSSStyle) {
            italic = other.italic ?? italic
            bold = other.bold ?? bold
            underline = other.underline ?? underline
            strikethrough = other.strikethrough ?? strikethrough
            baseline = other.baseline ?? baseline
            alignment = other.alignment ?? alignment
            hidden = hidden || other.hidden
        }
    }

    /// Class name → style, from simple class selectors (".calibre7",
    /// "p.calibre7"). Anything fancier is ignored.
    static func stylesheet(_ css: String) -> [String: CSSStyle] {
        let stripped = css.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        guard let rule = try? NSRegularExpression(pattern: #"([^{}]+)\{([^}]*)\}"#),
              let selector = try? NSRegularExpression(pattern: #"^[a-zA-Z0-9]*\.([\w-]+)$"#)
        else { return [:] }
        var out: [String: CSSStyle] = [:]
        for m in rule.matches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) {
            guard let sel = Range(m.range(at: 1), in: stripped), let body = Range(m.range(at: 2), in: stripped) else { continue }
            let style = declarations(String(stripped[body]))
            for part in stripped[sel].split(separator: ",") {
                let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let s = selector.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                      let cls = Range(s.range(at: 1), in: name) else { continue }
                out[String(name[cls]), default: CSSStyle()].merge(style)
            }
        }
        return out
    }

    /// One declaration block, or a `style` attribute.
    static func declarations(_ body: String) -> CSSStyle {
        var style = CSSStyle()
        for decl in body.split(separator: ";") {
            let parts = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard parts.count == 2 else { continue }
            let (prop, value) = (parts[0], parts[1])
            switch prop {
            case "font-style":
                style.italic = value.hasPrefix("italic") || value.hasPrefix("oblique")
            case "font-weight":
                style.bold = value.hasPrefix("bold") || (Int(value).map { $0 >= 600 } ?? false)
            case "text-decoration", "text-decoration-line":
                if value.contains("line-through") { style.strikethrough = true }
                if value.contains("underline") { style.underline = true }
                if value.hasPrefix("none") { style.underline = false; style.strikethrough = false }
            case "vertical-align":
                if value.hasPrefix("super") { style.baseline = .superscript }
                else if value.hasPrefix("sub") { style.baseline = .subscript }
            case "text-align":
                style.alignment = alignment(value)
            case "display":
                if value.hasPrefix("none") { style.hidden = true }
            default:
                break
            }
        }
        return style
    }

    static func alignment(_ value: String) -> EPUBBook.Block.Alignment {
        switch value.trimmingCharacters(in: .whitespaces).lowercased() {
        case "center", "middle": .center
        case "right", "end": .right
        default: .natural
        }
    }

    // MARK: - package document

    /// Spine hrefs in reading order (manifest ids resolved).
    static func spine(opf: String) -> [String] {
        var hrefs: [String: String] = [:]
        for item in allMatches(in: opf, pattern: #"<item\b[^>]*/?>"#) {
            if let id = firstMatch(in: item, pattern: #"\bid="([^"]+)""#),
               let href = firstMatch(in: item, pattern: #"\bhref="([^"]+)""#) {
                hrefs[id] = HTMLExtract.decodeEntities(href)
            }
        }
        return allMatches(in: opf, pattern: #"<itemref\b[^>]*\bidref="([^"]+)""#, group: 1)
            .compactMap { hrefs[$0] }
    }

    static func tocPath(opf: String) -> String? {
        for item in allMatches(in: opf, pattern: #"<item\b[^>]*/?>"#)
        where item.contains("application/x-dtbncx+xml") {
            return firstMatch(in: item, pattern: #"\bhref="([^"]+)""#)
        }
        return nil
    }

    /// toc.ncx labels keyed by the document they point at (fragment dropped);
    /// the first label for a document wins.
    static func ncxTitles(_ ncx: String) -> [String: String] {
        var titles: [String: String] = [:]
        let pattern = ##"<navLabel>\s*<text>([\s\S]*?)</text>\s*</navLabel>\s*<content\s+src="([^"#]+)"##
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [:] }
        for m in regex.matches(in: ncx, range: NSRange(ncx.startIndex..., in: ncx)) {
            guard let label = Range(m.range(at: 1), in: ncx), let src = Range(m.range(at: 2), in: ncx) else { continue }
            let key = HTMLExtract.decodeEntities(String(ncx[src]))
            if titles[key] == nil {
                titles[key] = HTMLExtract.decodeEntities(String(ncx[label]))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return titles
    }

    static func resolve(_ href: String, base: String) -> String {
        let path = base.isEmpty ? href : base + "/" + href
        // Collapse "a/../b" the way zip paths need it.
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            if part == ".." { _ = parts.popLast() } else if part != "." { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }

    // MARK: - XHTML → blocks

    /// Pure: one XHTML document to blocks. Falls back to a tag-stripping
    /// pass if the document isn't well-formed XML.
    public static func blocks(fromXHTML xhtml: String) -> [EPUBBook.Block] {
        blocks(fromXHTML: xhtml, classes: [:], base: "")
    }

    /// `classes` are the book's class styles; `base` is the document's folder
    /// in the archive, for resolving image paths.
    static func blocks(fromXHTML xhtml: String, classes: [String: CSSStyle], base: String) -> [EPUBBook.Block] {
        let builder = BlockBuilder(classes: classes, base: base)
        let parser = XMLParser(data: Data(xmlSafe(xhtml).utf8))
        parser.delegate = builder
        parser.shouldResolveExternalEntities = false
        if parser.parse() {
            return builder.blocks
        }
        return fallbackBlocks(xhtml)
    }

    /// XHTML from the web often carries HTML's named entities, which XML
    /// doesn't know without a DTD. Turn the common ones into characters.
    static func xmlSafe(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = s
        for (name, char) in htmlEntities {
            out = out.replacingOccurrences(of: "&\(name);", with: char)
        }
        return out
    }

    private static let htmlEntities: [(String, String)] = [
        ("nbsp", "\u{00A0}"), ("mdash", "—"), ("ndash", "–"), ("hellip", "…"),
        ("lsquo", "‘"), ("rsquo", "’"), ("ldquo", "“"), ("rdquo", "”"),
        ("copy", "©"), ("reg", "®"), ("trade", "™"), ("middot", "·"), ("bull", "•"),
        ("laquo", "«"), ("raquo", "»"), ("eacute", "é"), ("egrave", "è"),
        ("aacute", "á"), ("iacute", "í"), ("oacute", "ó"), ("uacute", "ú"),
        ("ntilde", "ñ"), ("uuml", "ü"), ("ouml", "ö"), ("auml", "ä"), ("szlig", "ß"),
        ("times", "×"), ("deg", "°"), ("sect", "§"), ("para", "¶"), ("dagger", "†"),
        ("hearts", "♥"), ("shy", "\u{00AD}"), ("zwj", "\u{200D}"), ("zwnj", "\u{200C}"),
    ]

    static func fallbackBlocks(_ html: String) -> [EPUBBook.Block] {
        let body = firstMatch(in: html, pattern: #"<body[^>]*>([\s\S]*?)(?:</body>|$)"#) ?? html
        // Every block tag, open or close, ends a paragraph — so unclosed
        // tags still split where a browser would.
        return body
            .replacingOccurrences(of: #"</?(?:p|h[1-6]|div|blockquote|li|dd|dt)\b[^>]*>"#, with: "\u{1}", options: .regularExpression)
            .components(separatedBy: "\u{1}")
            .map { chunk in
                let text = HTMLExtract.decodeEntities(
                    chunk.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
                return EPUBBook.Block(kind: .paragraph, runs: [.init(text: collapse(text))], quoteDepth: 0)
            }
            .filter { !$0.text.isEmpty }
    }

    /// Source whitespace (newlines, indentation) reads as single spaces.
    static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"[ \t\r\n]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - regex helpers (the package's existing style)

    static func firstMatch(in s: String, pattern: String) -> String? {
        allMatches(in: s, pattern: pattern, group: 1).first
    }

    static func allMatches(in s: String, pattern: String, group: Int = 0) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range(at: group), in: s).map { String(s[$0]) }
        }
    }
}

/// Walks XHTML and emits blocks. Block elements end a paragraph; inline
/// elements set the style of the text inside them.
final class BlockBuilder: NSObject, XMLParserDelegate {
    private(set) var blocks: [EPUBBook.Block] = []

    private let classes: [String: EPUBBookParser.CSSStyle]
    private let base: String

    private var runs: [EPUBBook.Run] = []
    private var style = EPUBBook.Run(text: "")
    private var styleStack: [EPUBBook.Run] = []
    private var alignment: EPUBBook.Block.Alignment = .natural
    private var alignmentStack: [EPUBBook.Block.Alignment] = []
    private var quoteDepth = 0
    private var headingLevel: Int?
    /// Depth inside an element we skip entirely (head, AO3's tag list…).
    private var skipDepth = 0
    private var elementStack: [(name: String, skipped: Bool)] = []

    /// Inside a `<dl>` thread: the chat so far, the current sender, and
    /// whether the text being read is a `<dt>` (a sender's name).
    private var chat: EPUBBook.Chat?
    private var chatDepth = 0
    private var sender = ""
    private var inSenderName = false

    /// Inside a table: its rows so far, and the cell being filled. Nested
    /// tables flatten into the outer one.
    private var tableRows: [[[EPUBBook.Run]]]?
    private var tableDepth = 0
    private var cell: [EPUBBook.Run]?

    /// Open lists, innermost last: whether each is numbered, and its next
    /// number. A list item's marker waits for its first paragraph.
    private var lists: [(ordered: Bool, next: Int)] = []
    private var pendingMarker: EPUBBook.Block.Marker?

    init(classes: [String: EPUBBookParser.CSSStyle] = [:], base: String = "") {
        self.classes = classes
        self.base = base
    }

    private static let blockElements: Set<String> = [
        "p", "div", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "li", "ul", "ol",
        "dl", "dt", "dd", "table", "tr", "td", "th", "pre", "center", "section", "article",
        "header", "footer", "figure", "figcaption", "body",
    ]
    private static let skippedElements: Set<String> = ["head", "script", "style", "title"]
    /// AO3 furniture the detail page already shows, or that only makes sense online.
    private static let skippedClasses: Set<String> = ["tags", "message", "endnote-link"]

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        let tag = name.lowercased()
        let classNames = (attributes["class"] ?? "").split(separator: " ").map(String.init)
        var css = EPUBBookParser.CSSStyle()
        for name in classNames { if let c = classes[name] { css.merge(c) } }
        if let inline = attributes["style"] { css.merge(EPUBBookParser.declarations(inline)) }
        let skip = skipDepth > 0 || Self.skippedElements.contains(tag)
            || !Set(classNames).isDisjoint(with: Self.skippedClasses) || css.hidden
            || (tag == "kbd" && classNames.contains("typebar"))  // a texting skin's empty input bar
        elementStack.append((tag, skip))
        if skip {
            skipDepth += 1
            return
        }

        if Self.blockElements.contains(tag) { flush() }
        alignmentStack.append(alignment)
        if tag == "center" { alignment = .center }
        if let align = attributes["align"] { alignment = EPUBBookParser.alignment(align) }
        if let align = css.alignment { alignment = align }

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            headingLevel = Int(tag.dropFirst())
        case "blockquote":
            quoteDepth += 1
        case "hr":
            flush()
            blocks.append(.init(kind: .rule, runs: [], quoteDepth: quoteDepth))
        case "br":
            append(Self.lineBreak)
        case "ul", "ol":
            lists.append((tag == "ol", attributes["start"].flatMap { Int($0) } ?? 1))
        case "li":
            if let value = attributes["value"].flatMap({ Int($0) }), !lists.isEmpty {
                lists[lists.count - 1].next = value
            }
            if let list = lists.last, list.ordered {
                pendingMarker = .number(list.next)
                lists[lists.count - 1].next += 1
            } else {
                pendingMarker = .bullet
            }
        case "table":
            tableDepth += 1
            if tableRows == nil { tableRows = [] }
        case "tr":
            if tableRows != nil { tableRows?.append([]) }
        case "td", "th":
            if tableRows != nil {
                if tableRows?.isEmpty == true { tableRows?.append([]) }
                cell = []
            }
        case "img":
            image(attributes)
        case "dl":
            chatDepth += 1
            if chat == nil {
                chat = EPUBBook.Chat()
                sender = ""
            }
        case "dt":
            if chat != nil { inSenderName = true }
        default:
            break
        }

        styleStack.append(style)
        switch tag {
        case "em", "i", "cite", "var", "dfn": style.italic = true
        case "strong", "b", "th": style.bold = true
        case "u", "ins": style.underline = true
        case "s", "strike", "del": style.strikethrough = true
        case "sup": style.baseline = .superscript
        case "sub": style.baseline = .subscript
        case "a":
            if let href = attributes["href"], let url = URL(string: href), url.scheme?.hasPrefix("http") == true {
                style.link = url
            }
        default: break
        }
        // Headings are set in the reader's own heading style.
        if headingLevel == nil {
            if let v = css.italic { style.italic = v }
            if let v = css.bold { style.bold = v }
        }
        if let v = css.underline { style.underline = v }
        if let v = css.strikethrough { style.strikethrough = v }
        if let v = css.baseline { style.baseline = v }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let (tag, skipped) = elementStack.popLast() else { return }
        if skipped {
            skipDepth -= 1
            return
        }
        style = styleStack.popLast() ?? EPUBBook.Run(text: "")
        // The paragraph ends with the alignment it was written in.
        if Self.blockElements.contains(tag) { flush() }
        alignment = alignmentStack.popLast() ?? .natural
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6": headingLevel = nil
        case "blockquote": quoteDepth = max(0, quoteDepth - 1)
        case "ul", "ol": _ = lists.popLast()
        case "li": pendingMarker = nil
        case "td", "th":
            if let finished = cell, tableRows != nil {
                if tableRows!.isEmpty { tableRows!.append([]) }
                tableRows![tableRows!.count - 1].append(finished)
            }
            cell = nil
        case "dt":
            inSenderName = false
        case "dl":
            chatDepth -= 1
            if chatDepth == 0, let finished = chat {
                chat = nil
                if !finished.items.isEmpty {
                    blocks.append(.init(kind: .chat(finished), runs: [], quoteDepth: quoteDepth))
                }
            }
        case "table":
            tableDepth -= 1
            if tableDepth == 0, let rows = tableRows {
                tableRows = nil
                let kept = rows.filter { !$0.isEmpty }
                if !kept.isEmpty {
                    blocks.append(.init(kind: .table(rows: kept), runs: [], quoteDepth: quoteDepth))
                }
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0 else { return }
        // Source line breaks and indentation are just spaces; only <br>
        // breaks a line.
        append(string.replacingOccurrences(of: #"[\t\r\n]"#, with: " ", options: .regularExpression))
    }

    /// An image is a block of its own; one only on the web keeps its URL.
    private func image(_ attributes: [String: String]) {
        let alt = (attributes["alt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let src = attributes["src"].map(HTMLExtract.decodeEntities), !src.isEmpty else {
            if !alt.isEmpty { append(alt) }
            return
        }
        let source: String
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            source = src
        } else if src.hasPrefix("data:") {
            if !alt.isEmpty { append(alt) }
            return
        } else {
            source = EPUBBookParser.resolve(src.removingPercentEncoding ?? src, base: base)
        }
        flush()
        if chat != nil {
            chat?.items.append(.image(sender: sender, source: source, alt: alt))
            return
        }
        let block = EPUBBook.Block(kind: .image(source: source, alt: alt), runs: [], quoteDepth: quoteDepth,
                                   alignment: alignment)
        if tableRows != nil {
            // An image in a table cell keeps its alt text there.
            if !alt.isEmpty { append(alt) }
        } else {
            blocks.append(block)
        }
    }

    /// Symbols only: a lone "…" is a beat of silence and "ooo" is a word.
    static func isTypedBreak(_ text: String) -> Bool {
        let marks = text.filter { !$0.isWhitespace }
        return marks.count >= 3 && marks.allSatisfy { "~*-=_•·°#+❦❧✦✧♦◆○●◇†‡§|/\\—–×".contains($0) }
            && Set(marks).count <= 3
    }

    /// Stands in for <br> until the paragraph is cleaned up.
    private static let lineBreak = "\u{2028}"

    func parserDidEndDocument(_ parser: XMLParser) {
        flush()
    }

    private func append(_ text: String) {
        var run = style
        run.text = text
        if var last = runs.last, last.sameStyle(as: run) {
            last.text += text
            runs[runs.count - 1] = last
        } else {
            runs.append(run)
        }
    }

    /// Ends the current paragraph: collapse source whitespace (keeping <br>
    /// line breaks), trim the ends, drop it if nothing's left. Inside a table
    /// cell the text joins the cell instead.
    private func flush() {
        defer { runs = [] }
        var cleaned: [EPUBBook.Run] = []
        for var run in runs {
            run.text = run.text
                .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
                .replacingOccurrences(of: Self.lineBreak, with: "\n")
            cleaned.append(run)
        }
        // Trim leading/trailing spaces across the whole paragraph, and the
        // spaces that hug a line break.
        while let first = cleaned.first, first.text.trimmingCharacters(in: .whitespaces).isEmpty, !first.text.contains("\n") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return }
        cleaned[0].text = String(cleaned[0].text.drop { $0 == " " })
        cleaned[cleaned.count - 1].text = String(cleaned[cleaned.count - 1].text.reversed().drop { $0 == " " || $0 == "\n" }.reversed())
        for i in cleaned.indices {
            cleaned[i].text = cleaned[i].text
                .replacingOccurrences(of: " \n", with: "\n")
                .replacingOccurrences(of: "\n ", with: "\n")
        }
        cleaned.removeAll { $0.text.isEmpty }
        let text = cleaned.map(\.text).joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let marker = pendingMarker
        pendingMarker = nil
        if chat == nil, cell != nil || tableRows != nil, let marker {
            // No room for a list's gutter in a table: the marker goes in the text.
            cleaned.insert(.init(text: Self.label(marker) + " "), at: 0)
        }
        if chat != nil {
            if inSenderName {
                sender = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if headingLevel != nil, chat?.title == nil, chat?.items.isEmpty == true {
                chat?.title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if headingLevel != nil || sender.isEmpty || Self.isTypedBreak(text) {
                chat?.items.append(.note(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            } else {
                chat?.items.append(.message(sender: sender, runs: cleaned))
            }
            return
        }
        if cell != nil {
            if var existing = cell, !existing.isEmpty {
                existing.append(.init(text: "\n"))
                cell = existing + cleaned
            } else {
                cell = cleaned
            }
            return
        }
        if tableRows != nil {
            // Text loose in a table, outside any cell: its own row.
            tableRows?.append([cleaned])
            return
        }
        // A line of nothing but dashes, tildes, asterisks… is a scene break
        // typed by hand ("~~~~~", "* * *", "-----"), whatever its markup.
        if headingLevel == nil, Self.isTypedBreak(text) {
            blocks.append(.init(kind: .rule, runs: [], quoteDepth: quoteDepth))
            return
        }
        let kind: EPUBBook.Block.Kind = headingLevel.map { .heading(level: $0) } ?? .paragraph
        blocks.append(.init(kind: kind, runs: cleaned, quoteDepth: quoteDepth, alignment: alignment,
                            marker: marker, listDepth: lists.count))
    }

    static func label(_ marker: EPUBBook.Block.Marker) -> String {
        switch marker {
        case .bullet: return "•"
        case .number(let n): return "\(n)."
        }
    }
}

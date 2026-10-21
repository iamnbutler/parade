import Foundation
import ZIPFoundation

/// The readable text of an EPUB: its documents in reading order, each turned
/// into a flat run of simple blocks — paragraphs, headings, scene breaks —
/// that a native view can lay out. Styling beyond italic, bold, underline and
/// links is dropped; the reader supplies its own type.
public struct EPUBBook: Sendable, Equatable {
    public var title: String?
    public var sections: [Section] = []

    public init(title: String? = nil, sections: [Section] = []) {
        self.title = title
        self.sections = sections
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
        }

        public var kind: Kind
        public var runs: [Run]
        /// How many blockquotes deep (author's notes, summaries, letters).
        public var quoteDepth: Int

        public var text: String { runs.map(\.text).joined() }
    }

    /// A stretch of text with one style.
    public struct Run: Sendable, Equatable {
        public var text: String
        public var italic = false
        public var bold = false
        public var underline = false
        public var link: URL?
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

        var book = EPUBBook(title: firstMatch(in: opf, pattern: #"<dc:title>([\s\S]*?)</dc:title>"#)
            .map(HTMLExtract.decodeEntities))
        for (i, href) in documents.enumerated() {
            let path = resolve(href, base: base)
            guard let xhtml = read(path) else { continue }
            let blocks = blocks(fromXHTML: xhtml)
            guard !blocks.isEmpty else { continue }
            book.sections.append(.init(id: i, title: tocTitles[href], blocks: blocks))
        }
        return book
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
        let builder = BlockBuilder()
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
private final class BlockBuilder: NSObject, XMLParserDelegate {
    private(set) var blocks: [EPUBBook.Block] = []

    private var runs: [EPUBBook.Run] = []
    private var style = EPUBBook.Run(text: "")
    private var styleStack: [EPUBBook.Run] = []
    private var quoteDepth = 0
    private var headingLevel: Int?
    /// Depth inside an element we skip entirely (head, AO3's tag list…).
    private var skipDepth = 0
    private var elementStack: [(name: String, skipped: Bool)] = []

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
        let classes = Set((attributes["class"] ?? "").split(separator: " ").map(String.init))
        let skip = skipDepth > 0 || Self.skippedElements.contains(tag) || !classes.isDisjoint(with: Self.skippedClasses)
        elementStack.append((tag, skip))
        if skip {
            skipDepth += 1
            return
        }

        if Self.blockElements.contains(tag) { flush() }
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
        case "li":
            append("• ")
        case "img":
            if let alt = attributes["alt"], !alt.isEmpty { append(alt) }
        default:
            break
        }

        styleStack.append(style)
        switch tag {
        case "em", "i", "cite", "var", "dfn": style.italic = true
        case "strong", "b": style.bold = true
        case "u", "ins": style.underline = true
        case "a":
            if let href = attributes["href"], let url = URL(string: href), url.scheme?.hasPrefix("http") == true {
                style.link = url
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let (tag, skipped) = elementStack.popLast() else { return }
        if skipped {
            skipDepth -= 1
            return
        }
        style = styleStack.popLast() ?? EPUBBook.Run(text: "")
        if Self.blockElements.contains(tag) { flush() }
        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6": headingLevel = nil
        case "blockquote": quoteDepth = max(0, quoteDepth - 1)
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard skipDepth == 0 else { return }
        // Source line breaks and indentation are just spaces; only <br>
        // breaks a line.
        append(string.replacingOccurrences(of: #"[\t\r\n]"#, with: " ", options: .regularExpression))
    }

    /// Stands in for <br> until the paragraph is cleaned up.
    private static let lineBreak = "\u{2028}"

    func parserDidEndDocument(_ parser: XMLParser) {
        flush()
    }

    private func append(_ text: String) {
        var run = style
        run.text = text
        if var last = runs.last, last.italic == run.italic, last.bold == run.bold,
           last.underline == run.underline, last.link == run.link {
            last.text += text
            runs[runs.count - 1] = last
        } else {
            runs.append(run)
        }
    }

    /// Ends the current paragraph: collapse source whitespace (keeping <br>
    /// line breaks), trim the ends, drop it if nothing's left.
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
        let kind: EPUBBook.Block.Kind = headingLevel.map { .heading(level: $0) } ?? .paragraph
        blocks.append(.init(kind: kind, runs: cleaned, quoteDepth: quoteDepth))
    }
}

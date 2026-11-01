import Foundation

/// A work as its AO3 web page shows it: preface, tags, stats and the text of
/// each chapter on the page. For building an EPUB when AO3's own export
/// can't be had — an archived copy of the page, with AO3 down.
public struct WorkPage: Equatable, Sendable {
    public struct TagGroup: Equatable, Sendable {
        /// As AO3's EPUB preface labels it: "Rating", "Additional Tags"…
        public var label: String
        public var names: [String]
    }

    public struct Chapter: Equatable, Sendable {
        /// "Chapter 2" or "Chapter 2: Title"; nil for a one-chapter work.
        public var title: String?
        /// XHTML fragments, ready to sit in a document body.
        public var summary: String?
        public var notes: String?
        public var text: String
        public var endNotes: String?
    }

    public var id: Int
    public var title: String
    public var authors: [String]
    /// The byline's profile links ("/users/name/pseuds/name"), one per author.
    public var authorPaths: [String] = []
    public var tags: [TagGroup] = []
    /// BCP 47 code from the page, e.g. "en".
    public var language: String?
    /// "Part 2 of Some Series", one per series.
    public var series: [String] = []
    public var published: String?
    /// "Completed" or "Updated", and its date.
    public var statusLabel: String?
    public var statusDate: String?
    public var words: String?
    /// "6/6", "3/?".
    public var chapterCount: String?
    public var summary: String?
    public var notes: String?
    public var endNotes: String?
    public var chapters: [Chapter] = []
    /// AO3's EPUB download path from the page ("/downloads/…epub?updated_at=…").
    public var epubPath: String?

    /// Chapters posted, from the stats ("6" of "6/6").
    public var postedChapters: Int? {
        chapterCount?.split(separator: "/").first.flatMap { Int($0.filter(\.isNumber)) }
    }

    /// Whether the page carries every posted chapter — a chapter link or
    /// a work page without view_full_work shows only one.
    public var hasAllChapters: Bool {
        guard let posted = postedChapters else { return !chapters.isEmpty }
        return chapters.count >= posted
    }
}

public enum WorkPageParser {

    /// Reads a work page. Throws if it isn't one with text on it — a login
    /// page, the adult-content check, an error page.
    public static func parse(_ html: String, id: Int) throws -> WorkPage {
        if HTMLExtract.isLoginPage(html, finalURL: nil) { throw AO3Error.restricted }
        guard let title = HTMLExtract.title(in: html) else { throw AO3Error.parseFailed("title") }
        var authors = HTMLExtract.authors(in: html)
        if authors.isEmpty { authors = ["Anonymous"] }
        var page = WorkPage(id: id, title: title, authors: authors)
        page.epubPath = HTMLExtract.epubPath(in: html)
        if let byline = HTMLExtract.firstMatch(in: html, pattern: #"<h3 class="byline heading">([\s\S]*?)</h3>"#) {
            page.authorPaths = HTMLExtract.allMatches(in: byline, pattern: #"<a rel="author" href="([^"]+)""#)
        }

        if let meta = element("dl", #"<dl class="work meta group"[^>]*>"#, in: html)?.inner {
            readMeta(meta, into: &page)
        }

        let workskin = element("div", #"<div id="workskin"[^>]*>"#, in: html)?.inner ?? html
        if let preface = element("div", #"<div class="preface group"[^>]*>"#, in: workskin)?.inner {
            page.summary = quoted(in: preface, module: "summary")
            page.notes = quoted(in: preface, module: "notes")
        }
        if let end = element("div", #"<div[^>]*id="work_endnotes"[^>]*>"#, in: html)?.inner {
            page.endNotes = quote(in: end)
        }

        guard let body = element("div", #"<div id="chapters"[^>]*>"#, in: workskin)?.inner else {
            throw AO3Error.parseFailed("work text")
        }
        var cursor = body.startIndex
        while let chapter = element("div", #"<div class="chapter" id="chapter-\d+"[^>]*>"#, in: body, from: cursor) {
            cursor = chapter.end
            if let parsed = readChapter(chapter.inner) { page.chapters.append(parsed) }
        }
        if page.chapters.isEmpty,
           let text = element("div", #"<div class="userstuff"[^>]*>"#, in: body)?.inner {
            // A one-chapter work: its text sits straight in #chapters.
            page.chapters = [.init(title: nil, text: XHTMLFragment.make(text))]
        }
        guard !page.chapters.isEmpty else { throw AO3Error.parseFailed("work text") }
        return page
    }

    private static func readChapter(_ html: String) -> WorkPage.Chapter? {
        guard var text = element("div", #"<div class="userstuff module"[^>]*>"#, in: html)?.inner else { return nil }
        text = text.replacingOccurrences(
            of: #"<h3 class="landmark heading"[^>]*>[\s\S]*?</h3>"#, with: "", options: .regularExpression)
        let title = HTMLExtract.firstMatch(in: html, pattern: #"<h3 class="title">([\s\S]*?)</h3>"#)
            .map(plainText).flatMap { $0.isEmpty ? nil : $0 }
        let preface = element("div", #"<div class="chapter preface group"[^>]*>"#, in: html)?.inner ?? ""
        let end = element("div", #"<div[^>]*class="end notes module"[^>]*>"#, in: html)?.inner
        return .init(title: title,
                     summary: quoted(in: preface, module: "summary"),
                     notes: quoted(in: preface, module: "notes"),
                     text: XHTMLFragment.make(text),
                     endNotes: end.flatMap(quote))
    }

    /// The quoted text of a "summary module" or "notes module" div.
    private static func quoted(in html: String, module: String) -> String? {
        element("div", #"<div[^>]*class="\#(module) module"[^>]*>"#, in: html).flatMap { quote(in: $0.inner) }
    }

    private static func quote(in html: String) -> String? {
        guard let inner = element("blockquote", #"<blockquote[^>]*class="userstuff"[^>]*>"#, in: html)?.inner,
              !plainText(inner).isEmpty else { return nil }
        return XHTMLFragment.make(inner)
    }

    private static let tagLabels: [(String, String)] = [
        ("rating", "Rating"), ("warning", "Archive Warning"), ("category", "Category"),
        ("fandom", "Fandom"), ("relationship", "Relationship"), ("character", "Characters"),
        ("freeform", "Additional Tags"),
    ]

    private static func readMeta(_ meta: String, into page: inout WorkPage) {
        for (cls, label) in tagLabels {
            guard let dd = HTMLExtract.firstMatch(in: meta, pattern: #"<dd class="\#(cls) tags">([\s\S]*?)</dd>"#) else { continue }
            let names = HTMLExtract.allMatches(in: dd, pattern: #"<a class="tag"[^>]*>([\s\S]*?)</a>"#).map(plainText)
            if !names.isEmpty { page.tags.append(.init(label: label, names: names)) }
        }
        page.language = HTMLExtract.firstMatch(in: meta, pattern: #"<dd class="language" lang="([^"]+)""#)
        if let dd = HTMLExtract.firstMatch(in: meta, pattern: #"<dd class="series">([\s\S]*?)</dd>"#) {
            page.series = HTMLExtract.allMatches(in: dd, pattern: #"<span class="position">([\s\S]*?)</span>"#)
                .map(plainText).filter { !$0.isEmpty }
        }
        func stat(_ cls: String) -> String? {
            HTMLExtract.firstMatch(in: meta, pattern: #"<dd class="\#(cls)">([\s\S]*?)</dd>"#)
                .map(plainText).flatMap { $0.isEmpty ? nil : $0 }
        }
        page.published = stat("published")
        page.words = stat("words")
        page.chapterCount = stat("chapters")
        if let label = HTMLExtract.firstMatch(in: meta, pattern: #"<dt class="status">([\s\S]*?)</dt>"#)
            .map({ plainText($0).trimmingCharacters(in: CharacterSet(charactersIn: ":")) }),
           let date = stat("status") {
            page.statusLabel = label
            page.statusDate = date
        }
    }

    static func plainText(_ html: String) -> String {
        HTMLExtract.decodeEntities(
            html.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression))
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first element whose start tag matches `opening`, at or after
    /// `start`: its inner HTML, and where it ends. Nested elements of the
    /// same name are balanced, so a div's inner divs stay inside it.
    static func element(_ tag: String, _ opening: String, in html: String,
                        from start: String.Index? = nil) -> (inner: String, end: String.Index)? {
        guard let open = html.range(of: opening, options: .regularExpression,
                                    range: (start ?? html.startIndex)..<html.endIndex) else { return nil }
        var depth = 1
        var cursor = open.upperBound
        while let next = html.range(of: #"</?\#(tag)\b[^>]*>"#, options: [.regularExpression, .caseInsensitive],
                                    range: cursor..<html.endIndex) {
            if html[next].hasPrefix("</") {
                depth -= 1
                if depth == 0 { return (String(html[open.upperBound..<next.lowerBound]), next.upperBound) }
            } else if !html[next].hasSuffix("/>") {
                depth += 1
            }
            cursor = next.upperBound
        }
        return nil
    }
}

/// HTML from AO3's pages made into XHTML an EPUB can carry: void tags
/// closed, HTML's named entities resolved, stray ampersands escaped. If
/// that still isn't well-formed XML, the text survives as plain paragraphs.
enum XHTMLFragment {
    static func make(_ html: String) -> String {
        var s = html.replacingOccurrences(
            of: #"<(br|hr|img|wbr|col|area|source)\b([^>]*?)\s*/?>"#, with: "<$1$2/>",
            options: [.regularExpression, .caseInsensitive])
        s = EPUBBookParser.xmlSafe(s)
        s = s.replacingOccurrences(of: #"&(?!(?:amp|lt|gt|quot|apos|#\d+|#x[0-9a-fA-F]+);)"#,
                                   with: "&amp;", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if isWellFormed(s) { return s }
        return EPUBBookParser.fallbackBlocks("<body>" + html + "</body>")
            .map { "<p>" + escape($0.text) + "</p>" }
            .joined(separator: "\n")
    }

    static func isWellFormed(_ fragment: String) -> Bool {
        XMLParser(data: Data(("<div>" + fragment + "</div>").utf8)).parse()
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

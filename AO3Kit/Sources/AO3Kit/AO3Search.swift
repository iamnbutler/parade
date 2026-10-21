import Foundation

/// A page of AO3 works to fetch: a search, or everything under one tag.
/// AO3 has no API; these are the site's own HTML listings.
public struct AO3WorkQuery: Sendable, Hashable {
    public enum Source: Sendable, Hashable {
        /// AO3's work search ("any field").
        case search(String)
        /// Every work under a tag: a fandom, ship, character or freeform.
        case tag(String)
    }

    public enum Sort: String, Sendable, CaseIterable, Identifiable {
        case relevance = "_score"
        case kudos = "kudos_count"
        case updated = "revised_at"
        case hits = "hits"
        case bookmarks = "bookmarks_count"
        case words = "word_count"

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .relevance: "Best match"
            case .kudos: "Kudos"
            case .updated: "Updated"
            case .hits: "Hits"
            case .bookmarks: "Bookmarks"
            case .words: "Length"
            }
        }
    }

    public var source: Source
    public var sort: Sort
    public var completeOnly: Bool
    /// 1-based, as on the site.
    public var page: Int

    public init(source: Source, sort: Sort = .relevance, completeOnly: Bool = false, page: Int = 1) {
        self.source = source
        self.sort = sort
        self.completeOnly = completeOnly
        self.page = page
    }

    public var url: URL {
        var c: URLComponents
        var items: [URLQueryItem] = []
        switch source {
        case .search(let text):
            c = URLComponents(string: "https://archiveofourown.org/works/search")!
            items.append(.init(name: "work_search[query]", value: text))
        case .tag(let name):
            c = URLComponents(string: "https://archiveofourown.org")!
            // AO3 spells a few characters out in tag URLs.
            c.percentEncodedPath = "/tags/" + Self.tagPath(name) + "/works"
        }
        // Tag listings sort by update date unless told otherwise, and know
        // nothing of relevance.
        if case .tag = source, sort == .relevance {
        } else {
            items.append(.init(name: "work_search[sort_column]", value: sort.rawValue))
        }
        if completeOnly { items.append(.init(name: "work_search[complete]", value: "T")) }
        if page > 1 { items.append(.init(name: "page", value: String(page))) }
        items.append(.init(name: "view_adult", value: "true"))
        c.queryItems = items
        return c.url!
    }

    static func tagPath(_ name: String) -> String {
        let spelled = name
            .replacingOccurrences(of: "*", with: "*x*")  // before the others add asterisks
            .replacingOccurrences(of: "/", with: "*s*")
            .replacingOccurrences(of: "&", with: "*a*")
            .replacingOccurrences(of: ".", with: "*d*")
            .replacingOccurrences(of: "?", with: "*q*")
            .replacingOccurrences(of: "#", with: "*h*")
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return spelled.addingPercentEncoding(withAllowedCharacters: allowed) ?? spelled
    }
}

/// One work as a listing shows it.
public struct WorkBlurb: Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String
    public var authors: [String]
    public var fandoms: [String] = []
    public var rating: String?
    public var warnings: [String] = []
    public var categories: [String] = []
    public var isComplete: Bool?
    /// "19 Dec 2025", as AO3 prints it.
    public var date: String?
    public var relationships: [String] = []
    public var characters: [String] = []
    public var freeforms: [String] = []
    /// Plain text, paragraphs separated by blank lines.
    public var summary: String?
    /// "Part 1 of You Have (81) Unread Messages"
    public var series: [String] = []
    public var language: String?
    public var words: Int?
    /// "3/10", "1/1", "4/?"
    public var chapters: String?
    public var kudos: Int?
    public var hits: Int?

    public init(id: Int, title: String, authors: [String]) {
        self.id = id
        self.title = title
        self.authors = authors
    }

    public var url: URL { AO3Link.work(id: id).pageURL }
}

public struct WorkResults: Sendable, Hashable {
    public var works: [WorkBlurb]
    /// "56,975 Found" / "1 - 20 of 5,431 Works in …"
    public var total: Int?
    public var page: Int
    public var hasNextPage: Bool
}

enum BlurbExtract {
    static func results(in html: String, page: Int) -> WorkResults {
        let starts = ranges(of: #"<li id="work_\d+" class="[^"]*\bwork blurb\b"#, in: html)
        var works: [WorkBlurb] = []
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1].lowerBound : html.endIndex
            if let blurb = blurb(String(html[start.lowerBound..<end])) { works.append(blurb) }
        }
        let total = HTMLExtract.firstMatch(in: html, pattern: #"<h2 class="heading">[^<]*?of ([\d,]+) Works"#)
            ?? HTMLExtract.firstMatch(in: html, pattern: #"<h3 class="heading">\s*([\d,]+) Found"#)
        let hasNext = html.range(of: #"<li class="next"[^>]*><a "#, options: .regularExpression) != nil
        return WorkResults(works: works, total: total.flatMap(number), page: page, hasNextPage: hasNext)
    }

    static func blurb(_ s: String) -> WorkBlurb? {
        guard let id = HTMLExtract.firstMatch(in: s, pattern: #"<li id="work_(\d+)""#).flatMap({ Int($0) }),
              let title = HTMLExtract.firstMatch(in: s, pattern: #"<h4 class="heading">\s*<a href="/works/\d+">([^<]*)</a>"#)
        else { return nil }
        var authors = HTMLExtract.allMatches(in: s, pattern: #"<a rel="author" href="[^"]*">([^<]*)</a>"#, group: 1)
            .map(text)
        if authors.isEmpty { authors = ["Anonymous"] }
        var b = WorkBlurb(id: id, title: text(title), authors: authors)

        if let fandoms = section(s, #"<h5 class="fandoms heading">"#, "</h5>") {
            b.fandoms = tags(in: fandoms)
        }
        b.rating = HTMLExtract.firstMatch(in: s, pattern: #"<span class="rating-[^"]*" title="([^"]*)""#).map(text)
        b.warnings = HTMLExtract.firstMatch(in: s, pattern: #"<span class="warning-[^"]*" title="([^"]*)""#)
            .map { text($0).components(separatedBy: ", ") } ?? []
        b.categories = HTMLExtract.firstMatch(in: s, pattern: #"<span class="category-[^"]*" title="([^"]*)""#)
            .map { text($0).components(separatedBy: ", ") } ?? []
        if let wip = HTMLExtract.firstMatch(in: s, pattern: #"<span class="complete-(yes|no) iswip""#) {
            b.isComplete = wip == "yes"
        }
        b.date = HTMLExtract.firstMatch(in: s, pattern: #"<p class="datetime">([^<]*)</p>"#)
        b.relationships = classTags(s, "relationships")
        b.characters = classTags(s, "characters")
        b.freeforms = classTags(s, "freeforms")
        if let summary = section(s, #"<blockquote class="userstuff summary">"#, "</blockquote>\n") {
            let plain = paragraphs(summary)
            b.summary = plain.isEmpty ? nil : plain
        }
        if let series = section(s, #"<ul class="series">"#, "</ul>") {
            b.series = HTMLExtract.allMatches(in: series, pattern: #"<li>([\s\S]*?)</li>"#, group: 1)
                .map { text(stripTags($0)) }
                .filter { !$0.isEmpty }
        }
        b.language = stat(s, "language").map(text)
        b.words = stat(s, "words").flatMap(number)
        b.chapters = stat(s, "chapters").map { text(stripTags($0)) }
        b.kudos = stat(s, "kudos").flatMap { number(stripTags($0)) }
        b.hits = stat(s, "hits").flatMap(number)
        return b
    }

    // MARK: - helpers

    private static func ranges(of pattern: String, in s: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s) }
    }

    /// The text between an opening marker and the first `end` after it.
    private static func section(_ s: String, _ open: String, _ end: String) -> String? {
        guard let a = s.range(of: open) else { return nil }
        let rest = s[a.upperBound...]
        let b = rest.range(of: end)?.lowerBound ?? rest.endIndex
        return String(rest[..<b])
    }

    private static func tags(in s: String) -> [String] {
        HTMLExtract.allMatches(in: s, pattern: #"<a class="tag" href="[^"]*">([^<]*)</a>"#, group: 1).map(text)
    }

    private static func classTags(_ s: String, _ kind: String) -> [String] {
        HTMLExtract.allMatches(in: s, pattern: "<li class='\(kind)'>(?:<strong>)?<a class=\"tag\" href=\"[^\"]*\">([^<]*)</a>", group: 1)
            .map(text)
    }

    private static func stat(_ s: String, _ name: String) -> String? {
        HTMLExtract.firstMatch(in: s, pattern: "<dd class=\"\(name)\"[^>]*>([\\s\\S]*?)</dd>")
    }

    private static func number(_ s: String) -> Int? {
        Int(s.filter(\.isNumber))
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Entities decoded, runs of whitespace as one space.
    private static func text(_ s: String) -> String {
        HTMLExtract.decodeEntities(s)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// A summary's HTML as plain paragraphs: <br> a line break, block ends
    /// a blank line.
    static func paragraphs(_ html: String) -> String {
        let marked = html
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\u{2028}", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</(p|div|blockquote|li|h\d)>"#, with: "\u{2029}", options: [.regularExpression, .caseInsensitive])
        return stripTags(marked)
            .components(separatedBy: "\u{2029}")
            .map { para in
                para.components(separatedBy: "\u{2028}")
                    .map { HTMLExtract.decodeEntities($0).trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

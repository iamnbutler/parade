import Foundation

/// Saves works from ao3saver.com, which keeps versions of AO3 works and
/// serves each as AO3's own HTML export (preface, tags, chapters, afterword).
/// That page is read into a `WorkPage` and built into an EPUB the way a
/// Wayback copy is, so the library treats it like any AO3 download.
public struct AO3SaverClient: Sendable {
    /// A queue of its own, so an AO3 outage's breaker doesn't hold it back.
    public static let scheduler = AO3Scheduler()

    private let session: URLSession
    private let scheduler: AO3Scheduler

    public init(session: URLSession? = nil, scheduler: AO3Scheduler = AO3SaverClient.scheduler) {
        self.scheduler = scheduler
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.httpAdditionalHeaders = ["User-Agent": AO3Client.userAgent]
            config.timeoutIntervalForRequest = 60
            self.session = URLSession(configuration: config)
        }
    }

    public struct SavedWork: Sendable {
        public let work: WorkInfo
        public let page: WorkPage
        /// A temporary EPUB file, for `Organizer.place`.
        public let epub: URL
    }

    public static func url(id: Int, version: Int?) -> URL {
        URL(string: "https://ao3saver.com/works/\(id)" + (version.map { "?version=\($0)" } ?? ""))!
    }

    public func fetchWork(id: Int, version: Int?,
                          priority: AO3Scheduler.Priority = .user) async throws -> SavedWork {
        let url = Self.url(id: id, version: version)
        let session = session
        let data: Data
        do {
            data = try await scheduler.run(priority) { () -> Data in
                let (data, response) = try await session.data(for: URLRequest(url: url))
                guard let http = response as? HTTPURLResponse else { throw AO3Error.httpError(0) }
                try AO3Client.check(http)
                return data
            }
        } catch AO3Error.notFound {
            throw AO3Error.archive("ao3saver.com has no copy of work \(id)\(version.map { " version \($0)" } ?? "").")
        } catch AO3Error.rateLimited {
            throw AO3Error.archive("ao3saver.com is rate-limiting requests. Try again in a minute.")
        } catch AO3Error.httpError(let code) {
            throw AO3Error.archive("ao3saver.com returned HTTP \(code).")
        }
        guard let html = String(data: data, encoding: .utf8) else { throw AO3Error.parseFailed("page encoding") }
        let page = try AO3ExportParser.parse(html, id: id)
        let work = WorkInfo(id: id, title: page.title, authors: page.authors,
                            epubURL: AO3Link.work(id: id).pageURL, updatedAt: nil)
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        try WorkPageEPUB.write(page, source: "Saved from ao3saver.com.", to: dest)
        return SavedWork(work: work, page: page, epub: dest)
    }
}

/// Reads AO3's HTML export of a work (the format ao3saver.com serves).
public enum AO3ExportParser {

    public static func parse(_ html: String, id: Int) throws -> WorkPage {
        guard let meta = WorkPageParser.element("div", #"<div class="meta"[^>]*>"#, in: html)?.inner,
              let title = HTMLExtract.firstMatch(in: meta, pattern: #"<h1[^>]*>([\s\S]*?)</h1>"#)
                .map(WorkPageParser.plainText), !title.isEmpty
        else { throw AO3Error.parseFailed("title") }

        let byline = HTMLExtract.firstMatch(in: meta, pattern: #"<div class="byline">([\s\S]*?)</div>"#) ?? ""
        var authors = HTMLExtract.allMatches(in: byline, pattern: #"<a rel="author"[^>]*>([\s\S]*?)</a>"#)
            .map(WorkPageParser.plainText).filter { !$0.isEmpty }
        if authors.isEmpty { authors = ["Anonymous"] }
        var page = WorkPage(id: id, title: title, authors: authors)
        page.authorPaths = HTMLExtract.allMatches(in: byline, pattern: #"<a rel="author" href="https?://[^/]+(/[^"]+)""#)

        if let tags = WorkPageParser.element("dl", #"<dl class="tags"[^>]*>"#, in: meta)?.inner {
            readTags(tags, into: &page)
        }
        // Summary and notes sit after the byline, each under a label.
        let afterByline = meta.range(of: "</h1>").map { String(meta[$0.upperBound...]) } ?? meta
        page.summary = labelled("Summary", in: afterByline)
        page.notes = labelled("Notes", in: afterByline)

        if let after = WorkPageParser.element("div", #"<div id="afterword"[^>]*>"#, in: html)?.inner {
            page.endNotes = labelled("End Notes", in: after)
        }

        guard let body = WorkPageParser.element("div", #"<div id="chapters"[^>]*>"#, in: html)?.inner else {
            throw AO3Error.parseFailed("work text")
        }
        page.chapters = chapters(in: body, workTitle: title)
        guard !page.chapters.isEmpty else { throw AO3Error.parseFailed("work text") }
        return page
    }

    /// One chapter per heading in #chapters; a one-chapter work has the one
    /// heading, its own title, and no chapter title of its own.
    private static func chapters(in body: String, workTitle: String) -> [WorkPage.Chapter] {
        let heading = #"<h2 class="toc-heading">([\s\S]*?)</h2>"#
        guard let regex = try? NSRegularExpression(pattern: heading) else { return [] }
        let ns = body as NSString
        let matches = regex.matches(in: body, range: NSRange(location: 0, length: ns.length))
        var sections: [(title: String, html: String)] = []
        for (i, m) in matches.enumerated() {
            let start = m.range.location + m.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            sections.append((WorkPageParser.plainText(ns.substring(with: m.range(at: 1))),
                             ns.substring(with: NSRange(location: start, length: end - start))))
        }
        if sections.isEmpty { sections = [(workTitle, body)] }

        return sections.compactMap { title, html in
            guard let text = WorkPageParser.element("div", #"<div class="userstuff"[^>]*>"#, in: html)?.inner
            else { return nil }
            var chapter = WorkPage.Chapter(title: sections.count == 1 ? nil : title, text: XHTMLFragment.make(text))
            // Chapter notes sit in a meta block before the text, end notes after it.
            if let range = html.range(of: #"<div class="userstuff"[^>]*>"#, options: .regularExpression) {
                let before = String(html[..<range.lowerBound])
                chapter.summary = labelled("Summary", in: before) ?? labelled("Chapter Summary", in: before)
                chapter.notes = labelled("Notes", in: before) ?? labelled("Chapter Notes", in: before)
            }
            chapter.endNotes = labelled("End Notes", in: html) ?? labelled("Chapter End Notes", in: html)
            return chapter
        }
    }

    /// The blockquote following a `<p>Label</p>`.
    private static func labelled(_ label: String, in html: String) -> String? {
        guard let marker = html.range(of: "<p>\(label)</p>") else { return nil }
        let rest = String(html[marker.upperBound...])
        guard let quote = WorkPageParser.element("blockquote", #"<blockquote[^>]*>"#, in: rest),
              !WorkPageParser.plainText(quote.inner).isEmpty else { return nil }
        return XHTMLFragment.make(quote.inner)
    }

    private static func readTags(_ dl: String, into page: inout WorkPage) {
        let pattern = #"<dt>([\s\S]*?)</dt>\s*<dd>([\s\S]*?)</dd>"#
        let pairs = Array(zip(HTMLExtract.allMatches(in: dl, pattern: pattern),
                              HTMLExtract.allMatches(in: dl, pattern: pattern, group: 2)))
        for (dt, dd) in pairs {
            let label = WorkPageParser.plainText(dt).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            switch label {
            case "Stats":
                let text = WorkPageParser.plainText(dd)
                func stat(_ name: String) -> String? {
                    HTMLExtract.firstMatch(in: text, pattern: "\(name):\\s*(\\S+)")
                }
                page.published = stat("Published")
                page.words = stat("Words")
                page.chapterCount = stat("Chapters")
                for status in ["Completed", "Updated"] {
                    if let date = stat(status) { page.statusLabel = status; page.statusDate = date }
                }
            case "Language":
                let name = WorkPageParser.plainText(dd)
                page.language = Locale.LanguageCode.isoLanguageCodes.first {
                    Locale(identifier: "en").localizedString(forLanguageCode: $0.identifier) == name
                }?.identifier
            case "Series":
                page.series = HTMLExtract.allMatches(in: dd, pattern: #"<span class="series">([\s\S]*?)</span>"#)
                    .map(WorkPageParser.plainText)
                if page.series.isEmpty { page.series = [WorkPageParser.plainText(dd)] }
            default:
                let names = HTMLExtract.allMatches(in: dd, pattern: #"<a[^>]*>([\s\S]*?)</a>"#).map(WorkPageParser.plainText)
                if !names.isEmpty {
                    // The export says "Fandoms:"; AO3's preface in the library says "Fandom".
                    page.tags.append(.init(label: label == "Fandoms" ? "Fandom" : label, names: names))
                }
            }
        }
    }
}

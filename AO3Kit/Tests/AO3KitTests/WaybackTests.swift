import XCTest
@testable import AO3Kit

final class WaybackTests: XCTestCase {

    // MARK: - links

    func testArchivedWorkLink() {
        let text = "https://web.archive.org/web/20260828044405/https://archiveofourown.org/works/89442356?view_adult=true&view_full_work=true#main"
        XCTAssertEqual(AO3Link(text: text), .archivedWork(
            id: 89442356, timestamp: "20260828044405",
            original: "https://archiveofourown.org/works/89442356?view_adult=true&view_full_work=true"))
        XCTAssertEqual(AO3Link(text: text)?.workID, 89442356)
    }

    func testArchivedLinkVariants() {
        // A capture modifier, a chapter link, no scheme, a short timestamp.
        XCTAssertEqual(AO3Link(text: "web.archive.org/web/20260101000000id_/http://archiveofourown.org/works/5/chapters/9"),
                       .archivedWork(id: 5, timestamp: "20260101000000", original: "http://archiveofourown.org/works/5/chapters/9"))
        XCTAssertEqual(AO3Link(text: "https://web.archive.org/web/2026/archiveofourown.org/works/7"),
                       .archivedWork(id: 7, timestamp: "2026", original: "https://archiveofourown.org/works/7"))
        // Not a snapshot of a work: falls through to the plain AO3 link.
        XCTAssertEqual(AO3Link(text: "https://web.archive.org/web/20260101000000/https://archiveofourown.org/series/3"),
                       .series(id: 3))
        XCTAssertEqual(AO3Link(text: "https://archiveofourown.org/works/12"), .work(id: 12))
    }

    func testBatchMixesArchivedAndLiveLinks() {
        let text = """
        https://web.archive.org/web/20260828044405/https://archiveofourown.org/works/1
        https://archiveofourown.org/works/2
        """
        XCTAssertEqual(AO3Link.all(in: text), [
            .archivedWork(id: 1, timestamp: "20260828044405", original: "https://archiveofourown.org/works/1"),
            .work(id: 2),
        ])
    }

    // MARK: - authors

    func testAuthorsComeFromTheBylineNotInspiredWorks() {
        let html = Self.fullWork
        XCTAssertEqual(HTMLExtract.authors(in: html), ["Writer"])
    }

    // MARK: - work page

    func testParsesFullWork() throws {
        let page = try WorkPageParser.parse(Self.fullWork, id: 42)
        XCTAssertEqual(page.title, "A & B")
        XCTAssertEqual(page.authors, ["Writer"])
        XCTAssertEqual(page.authorPaths, ["/users/Writer/pseuds/Writer"])
        XCTAssertEqual(page.tags, [
            .init(label: "Rating", names: ["Teen And Up Audiences"]),
            .init(label: "Fandom", names: ["Some Show"]),
            .init(label: "Relationship", names: ["A/B"]),
            .init(label: "Additional Tags", names: ["Fluff & Angst"]),
        ])
        XCTAssertEqual(page.language, "en")
        XCTAssertEqual(page.series, ["Part 2 of The Series"])
        XCTAssertEqual(page.published, "2026-01-01")
        XCTAssertEqual(page.statusLabel, "Updated")
        XCTAssertEqual(page.statusDate, "2026-02-01")
        XCTAssertEqual(page.words, "1,234")
        XCTAssertEqual(page.chapterCount, "2/3")
        XCTAssertEqual(page.epubPath, "/downloads/42/A_B.epub?updated_at=1700000000")
        XCTAssertEqual(page.summary, "<p>The summary.</p>")
        XCTAssertEqual(page.notes, "<p>Begin notes.</p>")
        XCTAssertEqual(page.endNotes, "<p>Work end notes.</p>")
        XCTAssertTrue(page.hasAllChapters)

        XCTAssertEqual(page.chapters.count, 2)
        let one = page.chapters[0]
        XCTAssertEqual(one.title, "Chapter 1: Beginnings")
        XCTAssertNil(one.summary)
        XCTAssertEqual(one.text, "<p>First line.<br/>Same paragraph.</p><hr/><p>Tom\u{00A0}&amp; Jerry — &lt;3</p>")
        XCTAssertEqual(one.endNotes, "<p>Chapter one end notes.</p>")
        let two = page.chapters[1]
        XCTAssertEqual(two.title, "Chapter 2")
        XCTAssertEqual(two.summary, "<p>Chapter two summary.</p>")
        XCTAssertEqual(two.notes, "<p>Chapter two notes.</p>")
        XCTAssertEqual(two.text, "<div><p>Nested <em>div</em>.</p></div><p>After it.</p>")
    }

    func testParsesOneChapterWork() throws {
        let html = """
        <div id="workskin"><div class="preface group">
          <h2 class="title heading">Short</h2>
          <h3 class="byline heading"><a rel="author" href="/users/x/pseuds/x">x</a></h3>
        </div>
        <div id="chapters" role="article">
          <h3 class="landmark heading" id="work">Work Text:</h3>
          <div class="userstuff"><p>All of it.</p></div>
        </div></div>
        """
        let page = try WorkPageParser.parse(html, id: 1)
        XCTAssertEqual(page.chapters, [.init(title: nil, text: "<p>All of it.</p>")])
        XCTAssertTrue(page.hasAllChapters)
    }

    func testOneChapterOfManyIsIncomplete() throws {
        let page = try WorkPageParser.parse(Self.fullWork.replacingOccurrences(of: "2/3", with: "3/3"), id: 42)
        XCTAssertEqual(page.postedChapters, 3)
        XCTAssertFalse(page.hasAllChapters)
    }

    func testPageWithoutTextThrows() {
        // The adult-content check, or an error page: a title but no chapters.
        let html = #"<h2 class="title heading">Gated</h2><p>This work could have adult content.</p>"#
        XCTAssertThrowsError(try WorkPageParser.parse(html, id: 1))
        XCTAssertThrowsError(try WorkPageParser.parse(#"<form id="new_user_session"></form>"#, id: 1)) {
            XCTAssertEqual($0 as? AO3Error, .restricted)
        }
    }

    func testMalformedTextFallsBackToParagraphs() {
        let out = XHTMLFragment.make("<p>One <b>two</p><p>three & four")
        XCTAssertTrue(XHTMLFragment.isWellFormed(out))
        XCTAssertEqual(out, "<p>One two</p>\n<p>three &amp; four</p>")
    }

    // MARK: - EPUB

    func testBuiltEPUBReadsLikeAO3Export() throws {
        let page = try WorkPageParser.parse(Self.fullWork, id: 42)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: url) }
        try WorkPageEPUB.write(page, source: "Saved from the Wayback Machine.", to: url)

        let details = try EPUBDetailsParser.parse(epubAt: url)
        XCTAssertEqual(details.title, "A & B")
        XCTAssertEqual(details.authors, ["Writer"])
        XCTAssertEqual(details.workID, 42)
        XCTAssertEqual(details.summary, "The summary.")
        XCTAssertEqual(details.rating, ["Teen And Up Audiences"])
        XCTAssertEqual(details.fandoms, ["Some Show"])
        XCTAssertEqual(details.relationships, ["A/B"])
        XCTAssertEqual(details.additionalTags, ["Fluff & Angst"])
        XCTAssertEqual(details.series, "Part 2 of The Series")
        XCTAssertEqual(details.seriesPart, 2)
        XCTAssertEqual(details.published, "2026-01-01")
        XCTAssertEqual(details.updated, "2026-02-01")
        XCTAssertEqual(details.words, "1,234")
        XCTAssertEqual(details.chapters, "2/3")

        let book = try EPUBBookParser.parse(epubAt: url)
        XCTAssertEqual(book.title, "A & B")
        XCTAssertEqual(book.sections.map(\.title), ["Preface", "Chapter 1: Beginnings", "Chapter 2", "Afterword"])
        let text = book.sections[1].blocks.map(\.text)
        XCTAssertTrue(text.contains("Tom\u{00A0}& Jerry — <3"), "\(text)")
        XCTAssertTrue(book.sections[3].blocks.map(\.text).contains("Work end notes."))
    }

    // MARK: - client

    func testFetchesFullWorkWhenTheLinkIsOneChapter() async throws {
        StubWayback.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubWayback.self]
        var schedule = AO3Scheduler.Configuration()
        schedule.spacing = 0
        schedule.spacingJitter = 0
        let client = WaybackClient(session: URLSession(configuration: config),
                                   scheduler: AO3Scheduler(configuration: schedule))

        let archived = try await client.fetchWork(id: 42, timestamp: "20260828044405",
                                                  original: "https://archiveofourown.org/works/42/chapters/7")
        defer { try? FileManager.default.removeItem(at: archived.epub) }
        XCTAssertEqual(archived.page.chapters.count, 2)
        XCTAssertFalse(archived.isAO3Export)
        XCTAssertEqual(archived.work.title, "A & B")
        XCTAssertEqual(archived.work.updatedAt, 1700000000)
        XCTAssertEqual(archived.captured, WaybackClient.date("20260828044405"))
        XCTAssertEqual(StubWayback.requests, [
            "https://web.archive.org/web/20260828044405id_/https://archiveofourown.org/works/42/chapters/7",
            "https://web.archive.org/web/20260828044405id_/https://archiveofourown.org/works/42?view_adult=true&view_full_work=true",
            "https://web.archive.org/web/20260828044405id_/https://archiveofourown.org/downloads/42/A_B.epub?updated_at=1700000000",
        ])
        XCTAssertEqual(try EPUBDetailsParser.parse(epubAt: archived.epub).workID, 42)
    }

    func testNothingArchived() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubWayback.self]
        var schedule = AO3Scheduler.Configuration()
        schedule.spacing = 0
        schedule.spacingJitter = 0
        let client = WaybackClient(session: URLSession(configuration: config),
                                   scheduler: AO3Scheduler(configuration: schedule))
        do {
            _ = try await client.fetchWork(id: 9, timestamp: "2026", original: "https://archiveofourown.org/works/9")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AO3Error, .notArchived)
        }
    }

    func testTimestampOfCapture() {
        XCTAssertEqual(WaybackClient.timestamp(in: URL(string: "https://web.archive.org/web/20260828044405id_/https://x")!),
                       "20260828044405")
    }

    // MARK: - fixtures

    /// A two-chapter view_full_work page, trimmed to the parts that matter.
    static let fullWork = #"""
    <ul class="expandable secondary"><li><a href="/downloads/42/A_B.epub?updated_at=1700000000">EPUB</a></li></ul>
    <dl class="work meta group">
      <dt class="rating tags">Rating:</dt>
      <dd class="rating tags"><ul class="commas"><li><a class="tag" href="/tags/Teen%20And%20Up%20Audiences/works">Teen And Up Audiences</a></li></ul></dd>
      <dt class="fandom tags">Fandom:</dt>
      <dd class="fandom tags"><ul class="commas"><li><a class="tag" href="/tags/Some%20Show/works">Some Show</a></li></ul></dd>
      <dt class="relationship tags">Relationship:</dt>
      <dd class="relationship tags"><ul class="commas"><li><a class="tag" href="/tags/A*s*B/works">A/B</a></li></ul></dd>
      <dt class="freeform tags">Additional Tags:</dt>
      <dd class="freeform tags"><ul class="commas"><li><a class="tag" href="/tags/x/works">Fluff &amp; Angst</a></li></ul></dd>
      <dt class="language">Language:</dt>
      <dd class="language" lang="en">English</dd>
      <dt class="series">Series:</dt>
      <dd class="series"><span class="series"><span class="position">Part 2 of <a href="/series/5">The Series</a></span></span></dd>
      <dt class="stats">Stats:</dt>
      <dd class="stats"><dl class="stats"><dt class="published">Published:</dt><dd class="published">2026-01-01</dd><dt class="status">Updated:</dt><dd class="status">2026-02-01</dd><dt class="words">Words:</dt><dd class="words">1,234</dd><dt class="chapters">Chapters:</dt><dd class="chapters">2/3</dd></dl></dd>
    </dl>
    <div id="workskin">
      <div class="preface group">
        <h2 class="title heading">
          A &amp; B
        </h2>
        <h3 class="byline heading">
          <a rel="author" href="/users/Writer/pseuds/Writer">Writer</a>
        </h3>
        <div class="summary module"><h3 class="heading">Summary:</h3>
          <blockquote class="userstuff"><p>The summary.</p></blockquote>
        </div>
        <div class="notes module"><h3 class="heading">Notes:</h3>
          <blockquote class="userstuff"><p>Begin notes.</p></blockquote>
          <p class="jump">(See the end of the work for <a href="#work_endnotes">more notes</a>.)</p>
        </div>
      </div>
      <div id="chapters" role="article">
        <div class="chapter" id="chapter-1">
          <div class="chapter preface group">
            <h3 class="title"><a href="/works/42/chapters/7">Chapter 1</a>: Beginnings</h3>
          </div>
          <div class="userstuff module" role="article">
            <h3 class="landmark heading" id="work">Chapter Text</h3>
            <p>First line.<br>Same paragraph.</p><hr><p>Tom&nbsp;&amp; Jerry &mdash; &lt;3</p>
          </div>
          <div class="chapter preface group">
            <div id="chapter_1_endnotes" class="end notes module"><h3 class="heading">Notes:</h3>
              <blockquote class="userstuff"><p>Chapter one end notes.</p></blockquote>
            </div>
          </div>
        </div>
        <div class="chapter" id="chapter-2">
          <div class="chapter preface group">
            <h3 class="title"><a href="/works/42/chapters/8">Chapter 2</a></h3>
            <div id="summary" class="summary module"><h3 class="heading">Summary:</h3>
              <blockquote class="userstuff"><p>Chapter two summary.</p></blockquote>
            </div>
            <div id="notes" class="notes module"><h3 class="heading">Notes:</h3>
              <blockquote class="userstuff"><p>Chapter two notes.</p></blockquote>
            </div>
          </div>
          <div class="userstuff module" role="article">
            <h3 class="landmark heading" id="work">Chapter Text</h3>
            <div><p>Nested <em>div</em>.</p></div><p>After it.</p>
          </div>
        </div>
      </div>
      <div class="afterword preface group">
        <div id="work_endnotes" class="end notes module"><h3 class="heading">Notes:</h3>
          <blockquote class="userstuff"><p>Work end notes.</p></blockquote>
        </div>
        <div id="children" class="children module"><h3 class="heading">Works inspired by this one:</h3>
          <ul><li><a href="https://archiveofourown.org/works/99">Fan art</a> by <a rel="author" href="/users/Fan/pseuds/Fan">Fan</a></li></ul>
        </div>
      </div>
    </div>
    """#
}

/// The Wayback Machine, for work 42: a one-chapter capture of chapter 7,
/// the full work, and no EPUB. Anything else is not archived.
final class StubWayback: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var requests: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.append(url.absoluteString)
        var body: String?
        if url.absoluteString.hasSuffix("/works/42/chapters/7") {
            // A chapter view: only chapter one.
            let page = WaybackTests.fullWork
            let cut = page.range(of: #"<div class="chapter" id="chapter-2">"#)!.lowerBound
            let resume = page.range(of: #"<div class="afterword"#)!.lowerBound
            body = page[..<cut] + "</div>\n" + page[resume...]
        } else if url.absoluteString.contains("/works/42?") {
            body = WaybackTests.fullWork
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

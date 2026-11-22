import XCTest
import ZIPFoundation
@testable import AO3Kit

/// Downloads that came back with only some chapters: AO3's HTML export
/// heads chapters `<h2 class="heading">`, which was read as one chapter,
/// and an update could replace a whole saved copy with that.
final class PartialDownloadTests: XCTestCase {

    // MARK: - AO3's HTML export

    func testExportKeepsEveryChapter() throws {
        let page = try AO3ExportParser.parse(Self.export(chapters: 3), id: 95718386)
        XCTAssertEqual(page.chapters.map(\.title), ["Chapter 1: One", "Chapter 2: Two", "Chapter 3: Three"])
        XCTAssertEqual(page.chapters.map(\.text), ["<p>Text one.</p>", "<p>Text two.</p>", "<p>Text three.</p>"])
        XCTAssertEqual(page.postedChapters, 3)
        XCTAssertTrue(page.hasAllChapters)
        // Chapter summaries and end notes stay with their own chapter.
        XCTAssertEqual(page.chapters[1].summary, "<p>Summary two.</p>")
        XCTAssertNil(page.chapters[0].summary)
        XCTAssertEqual(page.chapters[1].endNotes, "<p>End notes two.</p>")
        XCTAssertNil(page.chapters[2].endNotes)
        XCTAssertEqual(page.endNotes, "<p>Thanks for reading.</p>")
    }

    func testOneChapterExport() throws {
        let page = try AO3ExportParser.parse(Self.export(chapters: 1), id: 5)
        XCTAssertEqual(page.chapters.count, 1)
        XCTAssertNil(page.chapters[0].title)
        XCTAssertEqual(page.chapters[0].text, "<p>Text one.</p>")
    }

    func testNineteenChapterExport() throws {
        let page = try AO3ExportParser.parse(Self.export(chapters: 19), id: 89037231)
        XCTAssertEqual(page.chapters.count, 19)
        XCTAssertEqual(page.chapters.last?.text, "<p>Text 19.</p>")
    }

    /// A real export, if one has been saved there (ao3saver.com serves them).
    func testRealExportIfPresent() throws {
        guard let html = try? String(contentsOfFile: "/tmp/ao3dl/export-95718386.html", encoding: .utf8) else { return }
        let page = try AO3ExportParser.parse(html, id: 95718386)
        XCTAssertEqual(page.chapters.count, 3)
        XCTAssertTrue(page.hasAllChapters)
    }

    // MARK: - the download, from a chapter link

    /// Saori's link: a /works/<id>/chapters/<id> link saves every chapter,
    /// from the HTML download while AO3's EPUBs are off.
    func testChapterLinkSavesEveryChapter() async throws {
        let client = Self.client()
        let link = try XCTUnwrap(AO3Link(text: "https://archiveofourown.org/works/95718386/chapters/255693601"))
        let ids = try await client.workIDs(for: link)
        XCTAssertEqual(ids, [95718386])
        let work = try await client.fetchWork(id: ids[0])
        XCTAssertEqual(work.postedChapters, 3)
        let epub = try await client.downloadEPUB(work)
        defer { try? FileManager.default.removeItem(at: epub) }
        XCTAssertEqual(ChapterGuard.chapterCount(epubAt: epub), 3)
        let book = try EPUBBookParser.parse(epubAt: epub)
        let text = book.sections.flatMap(\.blocks).map(\.text)
        XCTAssertTrue(text.contains("Text three."), "\(text)")
    }

    /// A chapter-only link (/chapters/<id>) finds its work, then the same.
    func testChapterOnlyLinkSavesEveryChapter() async throws {
        let client = Self.client()
        let ids = try await client.workIDs(for: .chapter(id: 255693601))
        XCTAssertEqual(ids, [95718386])
        let epub = try await client.downloadEPUB(try await client.fetchWork(id: ids[0]))
        defer { try? FileManager.default.removeItem(at: epub) }
        XCTAssertEqual(ChapterGuard.chapterCount(epubAt: epub), 3)
    }

    /// An HTML download that falls short of the stated chapters isn't built.
    func testShortHTMLDownloadIsRefused() async throws {
        let client = Self.client()
        let work = WorkInfo(id: 95718386, title: "Three", authors: ["a"],
                            epubURL: URL(string: "https://archiveofourown.org/downloads/95718386/Three.html")!,
                            updatedAt: nil, postedChapters: 19)
        do {
            _ = try await client.downloadEPUB(work)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? AO3Error, .missingChapters(got: 3, expected: 19, keptSaved: false))
        }
    }

    // MARK: - the guard

    func testShortfall() {
        XCTAssertNil(ChapterGuard.shortfall(got: 19, saved: 19, stated: 19))
        XCTAssertNil(ChapterGuard.shortfall(got: 20, saved: 19, stated: nil))
        XCTAssertNil(ChapterGuard.shortfall(got: 1, saved: nil, stated: nil))
        XCTAssertEqual(ChapterGuard.shortfall(got: 1, saved: 19, stated: nil),
                       .missingChapters(got: 1, expected: 19, keptSaved: true))
        XCTAssertEqual(ChapterGuard.shortfall(got: 2, saved: 1, stated: 19),
                       .missingChapters(got: 2, expected: 19, keptSaved: true))
        XCTAssertEqual(ChapterGuard.shortfall(got: 2, saved: nil, stated: 19),
                       .missingChapters(got: 2, expected: 19, keptSaved: false))
    }

    /// AO3's own EPUB's table of contents: the title, Preface, each chapter, Afterword.
    func testCountsChaptersInAO3TableOfContents() {
        func ncx(_ labels: [String]) -> String {
            "<ncx><docTitle><text>Work</text></docTitle><navMap>"
                + labels.enumerated().map { i, l in
                    "<navPoint id=\"n\(i)\" playOrder=\"\(i)\"><navLabel><text>\(l)</text></navLabel><content src=\"x\"/></navPoint>"
                }.joined() + "</navMap></ncx>"
        }
        XCTAssertEqual(ChapterGuard.chapterCount(ncx: ncx(["Preface", "Chapter 1: A", "Chapter 2: B", "Afterword"])), 2)
        XCTAssertEqual(ChapterGuard.chapterCount(ncx: ncx(["Preface", "Reassurance", "Afterword"])), 1)
        XCTAssertNil(ChapterGuard.chapterCount(ncx: "<ncx></ncx>"))
    }

    /// Nate's update: a 2-chapter download never replaces a 19-chapter copy.
    func testUpdateKeepsTheFullerCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let organizer = Organizer(root: root)
        let work = WorkInfo(id: 89037231, title: "Phoenix", authors: ["P"],
                            epubURL: URL(string: "https://archiveofourown.org/downloads/89037231/P.epub")!, updatedAt: nil)

        let saved = try organizer.place(try Self.epub(chapters: 19), for: work)
        let savedBytes = try Data(contentsOf: saved)

        let short = try Self.epub(chapters: 2)
        XCTAssertThrowsError(try organizer.place(short, for: work)) { error in
            XCTAssertEqual(error as? AO3Error, .missingChapters(got: 2, expected: 19, keptSaved: true))
        }
        // The saved copy is untouched, nothing went to Backups, the short one is gone.
        XCTAssertEqual(try Data(contentsOf: saved), savedBytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(Organizer.backupsFolder).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: short.path))

        // Fewer than the work page says are posted, even with no saved copy to compare.
        var stated = work
        stated.postedChapters = 20
        XCTAssertThrowsError(try organizer.place(try Self.epub(chapters: 19), for: stated))

        // A full download still replaces it, backing the old one up.
        XCTAssertNoThrow(try organizer.place(try Self.epub(chapters: 20), for: stated))
        XCTAssertEqual(ChapterGuard.chapterCount(epubAt: saved), 20)
    }

    /// Checked against a copy saved under another name (an update whose title changed).
    func testGuardChecksTheCopyBeingReplaced() throws {
        let old = try Self.epub(chapters: 5)
        let new = try Self.epub(chapters: 4)
        defer { [old, new].forEach { try? FileManager.default.removeItem(at: $0) } }
        XCTAssertThrowsError(try ChapterGuard.check(new, replacing: old, stated: nil))
        XCTAssertNoThrow(try ChapterGuard.check(old, replacing: new, stated: 5))
        // A saved copy that isn't there (an iCloud placeholder) isn't held against it.
        XCTAssertNoThrow(try ChapterGuard.check(new, replacing: URL(fileURLWithPath: "/nonexistent.epub"), stated: nil))
    }

    // MARK: - fixtures

    static func epub(chapters n: Int) throws -> URL {
        var page = WorkPage(id: 1, title: "Work", authors: ["a"])
        page.chapters = (1...n).map { .init(title: n == 1 ? nil : "Chapter \($0)", text: "<p>\($0)</p>") }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
        try WorkPageEPUB.write(page, to: url)
        return url
    }

    static func client() -> AO3Client {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAO3.self]
        var schedule = AO3Scheduler.Configuration()
        schedule.spacing = 0
        schedule.spacingJitter = 0
        return AO3Client(session: URLSession(configuration: config), scheduler: AO3Scheduler(configuration: schedule))
    }

    /// AO3's HTML download, laid out as AO3 writes it (text made up).
    static func export(chapters n: Int) -> String {
        var s = """
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en"><head><meta charset="utf-8" /><title>Three</title></head>
        <body>
        <div id="preface">
          <h2 class="toc-heading">Preface</h2>
          <p class="message"><b>Three</b><br/>Posted originally on the Archive of Our Own at https://archiveofourown.org/works/95718386.</p>
          <div class="meta">
            <dl class="tags">
              <dt>Rating:</dt><dd><a href="https://archiveofourown.org/tags/Explicit">Explicit</a></dd>
              <dt>Language:</dt><dd>English</dd>
              <dt>Stats:</dt><dd>Published: 2026-11-01 Completed: 2026-11-15 Words: 1,000 Chapters: \(n)/\(n)</dd>
            </dl>
            <h1>Three</h1>
            <div class="byline">by <a rel="author" href="https://archiveofourown.org/users/a/pseuds/a">a</a></div>
            <p>Summary</p>
            <blockquote class="userstuff"><p>A work.</p></blockquote>
          </div>
        </div>
        <div id="chapters" class="userstuff">

        """
        let names = ["One", "Two", "Three"]
        for i in 1...n {
            let label = i <= names.count ? names[i - 1] : "\(i)"
            if n > 1 {
                s += """
                <div class="meta group">
                  <h2 class="heading">
                      Chapter \(i): \(label)
                  </h2>

                """
                if i == 2 {
                    s += """
                        <p>Chapter Summary</p>
                        <blockquote class="userstuff"><p>Summary two.</p></blockquote>
                        <p>Chapter Notes</p>
                          <div class="endnote-link">
                            See the end of the chapter for <a href="#endnotes2">notes</a>
                          </div>

                    """
                }
                s += "</div>\n"
            }
            s += """
            <!--chapter content-->
            <div class="userstuff">
              <p>Text \(i <= names.count ? names[i - 1].lowercased() : "\(i)").</p>
            </div>
            <!--/chapter content-->

            """
            if i == 2 {
                s += """
                  <div class="meta" id="endnotes2">
                    <p>Chapter End Notes</p>
                    <blockquote class="userstuff"><p>End notes two.</p></blockquote>
                  </div>

                """
            }
        }
        s += """
        </div>
        <div id="afterword">
          <h2 class="toc-heading">Afterword</h2>
          <div class="meta"><div id="endnotes"><p>End Notes</p>
            <blockquote class="userstuff"><p>Thanks for reading.</p></blockquote></div></div>
          <p class="message">Please <a href="https://archiveofourown.org/works/95718386/comments/new">drop by the Archive and comment</a></p>
        </div>
        </body></html>
        """
        return s
    }

    /// The first chapter's page, which AO3 serves for /works/<id> of a
    /// multi-chapter work, and for its chapter links.
    static let chapterPage = """
    <html><body>
    <ul class="work navigation actions">
      <li class="download"><ul class="expandable secondary">
        <li><a href="/downloads/95718386/Three.epub?updated_at=1763000000">EPUB</a></li>
        <li><a href="/downloads/95718386/Three.html?updated_at=1763000000">HTML</a></li>
      </ul></li>
    </ul>
    <dl class="work meta group"><dt class="stats">Stats:</dt><dd class="stats"><dl class="stats">
      <dt class="chapters">Chapters:</dt><dd class="chapters"><a href="/works/95718386/chapters/255693603">3</a>/3</dd>
    </dl></dd></dl>
    <div id="workskin"><div class="preface group"><h2 class="title heading">
      Three
    </h2><h3 class="byline heading"><a rel="author" href="/users/a/pseuds/a">a</a></h3></div>
    <div id="chapters" role="article"><div class="chapter" id="chapter-1">
      <div class="userstuff module" role="article"><p>Text one.</p></div>
    </div></div></div>
    <a href="/works/95718386/kudos">Kudos</a>
    </body></html>
    """
}

/// AO3 with EPUB downloads off, for work 95718386 (three chapters): its
/// pages show chapter one; the EPUB is gone; the HTML download is whole.
final class StubAO3: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var body: String?
        var type = "text/html; charset=utf-8"
        if url.path.hasPrefix("/works/95718386") || url.path == "/chapters/255693601" {
            body = PartialDownloadTests.chapterPage
        } else if url.path == "/downloads/95718386/Three.html" {
            body = PartialDownloadTests.export(chapters: 3)
            type = "text/html"
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil,
                                       headerFields: ["Content-Type": type])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

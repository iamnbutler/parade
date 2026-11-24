import XCTest
import ZIPFoundation
@testable import AO3Kit

/// Timings for the parse/build/read paths, on made-up works of a few sizes.
/// Off by default (they take a while); run with
/// `PARADE_BENCH=1 swift test --filter PerfBenchmarks`.
final class PerfBenchmarks: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PARADE_BENCH"] != nil, "set PARADE_BENCH=1")
    }

    /// One chapter's text: `paragraphs` paragraphs of fic-like prose, with
    /// curly quotes, em dashes, italics and an entity or two, as AO3 emits.
    static func chapterText(_ paragraphs: Int) -> String {
        let p = "<p>“I don’t know,” she said &amp; looked away — <em>again</em>. The rain hadn’t stopped "
            + "since Tuesday, and the kettle was still on the hob, whistling at nobody… "
            + "He’d said he’d be back by six.</p>\n"
        return String(repeating: p, count: paragraphs)
    }

    /// AO3's HTML export with `n` chapters of `paragraphs` each.
    static func bigExport(chapters n: Int, paragraphs: Int) -> String {
        let small = PartialDownloadTests.export(chapters: n)
        // Swap each chapter's one-line text for a long one.
        var out = ""
        var rest = Substring(small)
        while let r = rest.range(of: #"<p>Text [^<]*</p>"#, options: .regularExpression) {
            out += rest[..<r.lowerBound]
            out += chapterText(paragraphs)
            rest = rest[r.upperBound...]
        }
        return out + rest
    }

    static func time(_ label: String, runs: Int = 3, _ body: () throws -> Void) rethrows -> Double {
        var best = Double.infinity
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        print(String(format: "BENCH %@: %.1f ms", label, best))
        return best
    }

    func testExportParseBuildRead() throws {
        for (chapters, paragraphs) in [(10, 60), (40, 60), (120, 60)] {
            let html = Self.bigExport(chapters: chapters, paragraphs: paragraphs)
            let tag = "\(chapters)ch \(html.utf8.count / 1024)KB"
            var page: WorkPage!
            _ = try Self.time("export parse \(tag)") { page = try AO3ExportParser.parse(html, id: 1) }
            XCTAssertEqual(page.chapters.count, chapters)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try Self.time("epub write \(tag)") {
                try? FileManager.default.removeItem(at: url)
                try WorkPageEPUB.write(page, to: url)
            }
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("BENCH epub size \(tag): \(size / 1024) KB")
            _ = Self.time("chapterCount \(tag)") { XCTAssertEqual(ChapterGuard.chapterCount(epubAt: url), chapters) }
            var book: EPUBBook!
            _ = try Self.time("epub read \(tag)") { book = try EPUBBookParser.parse(epubAt: url) }
            XCTAssertEqual(book.sections.count, chapters + 2)
        }
    }

    /// A work page as AO3 serves it (first chapter only, ~40 KB of chrome
    /// around it), read the way `fetchWork` reads it.
    func testWorkPageExtract() throws {
        let page = String(repeating: "<li class=\"blurb\"><a href=\"/tags/x\">tag</a></li>\n", count: 800)
            + PartialDownloadTests.chapterPage.replacingOccurrences(of: "<p>Text one.</p>", with: Self.chapterText(80))
        _ = Self.time("fetchWork extract \(page.utf8.count / 1024)KB", runs: 5) {
            _ = HTMLExtract.isLoginPage(page, finalURL: nil)
            _ = HTMLExtract.title(in: page)
            _ = HTMLExtract.epubPath(in: page)
            _ = HTMLExtract.htmlDownloadPath(in: page)
            _ = HTMLExtract.authors(in: page)
            _ = HTMLExtract.postedChapters(in: page)
        }
    }

    /// A 20-work search page (the update check reads one per request).
    func testSearchPage() {
        let blurbs = AO3SearchTests.searchPage
        let start = blurbs.range(of: "<li id=\"work_")!.lowerBound
        let page = String(blurbs[..<start]) + String(repeating: String(blurbs[start...]), count: 10)
        var count = 0
        _ = Self.time("search page parse \(page.utf8.count / 1024)KB", runs: 5) {
            count = BlurbExtract.results(in: page, page: 1).works.count
        }
        XCTAssertGreaterThanOrEqual(count, 20)
    }

    /// The library index reads every EPUB's details once (and again when
    /// one changes): the fixture library, 50 times over.
    func testDetailsIndex() throws {
        guard let dir = ProcessInfo.processInfo.environment["PARADE_FIXTURES"] else { return }
        let files = FileManager.default.enumerator(atPath: dir)!.compactMap { $0 as? String }
            .filter { $0.hasSuffix(".epub") }.map { URL(fileURLWithPath: dir + "/" + $0) }
        _ = Self.time("details ×\(files.count * 50)", runs: 3) {
            for _ in 0..<50 { for f in files { _ = try? EPUBDetailsParser.parse(epubAt: f) } }
        }
    }

    // MARK: - requests per flow

    func testRequestsPerFlow() async throws {
        CountingAO3.reset()
        let client = Self.countingClient()
        // Save a work whose EPUB link 404s (AO3's EPUBs switched off).
        let work = try await client.fetchWork(id: 95718386)
        let epub = try await client.downloadEPUB(work)
        try? FileManager.default.removeItem(at: epub)
        print("BENCH requests, save with EPUBs off: \(CountingAO3.paths)")
        CountingAO3.reset()
        let again = try await client.downloadEPUB(try await client.fetchWork(id: 95718386))
        try? FileManager.default.removeItem(at: again)
        print("BENCH requests, second save with EPUBs off: \(CountingAO3.paths)")
    }

    static func countingClient() -> AO3Client {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingAO3.self]
        var schedule = AO3Scheduler.Configuration()
        schedule.spacing = 0
        schedule.spacingJitter = 0
        return AO3Client(session: URLSession(configuration: config), scheduler: AO3Scheduler(configuration: schedule))
    }
}

/// StubAO3, counting what it's asked for.
final class CountingAO3: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _paths: [String] = []
    static var paths: [String] { lock.withLock { _paths } }
    static func reset() { lock.withLock { _paths = [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock { Self._paths.append(url.path) }
        var body: String?
        if url.path.hasPrefix("/works/95718386") || url.path == "/chapters/255693601" {
            body = PartialDownloadTests.chapterPage
        } else if url.path == "/downloads/95718386/Three.html" {
            body = PartialDownloadTests.export(chapters: 3)
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/html; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "Not found").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}


final class PerfBreakdown: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PARADE_BENCH"] != nil, "set PARADE_BENCH=1")
    }

    final class Nop: NSObject, XMLParserDelegate {}

    func testReaderBreakdown() throws {
        let chapter = "<?xml version='1.0' encoding='utf-8'?><html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>t</title></head><body><div id=\"chapters\"><div class=\"userstuff\">"
            + PerfBenchmarks.chapterText(60).replacingOccurrences(of: "&amp;", with: "&amp;") + "</div></div></body></html>"
        let n = 120
        _ = PerfBenchmarks.time("xmlSafe ×\(n)") { for _ in 0..<n { _ = EPUBBookParser.xmlSafe(chapter) } }
        let safe = EPUBBookParser.xmlSafe(chapter)
        _ = PerfBenchmarks.time("XMLParser nop ×\(n)") {
            for _ in 0..<n { let nop = Nop(); let p = XMLParser(data: Data(safe.utf8)); p.delegate = nop; _ = p.parse(); withExtendedLifetime(nop) {} }
        }
        _ = PerfBenchmarks.time("blocks(fromXHTML) ×\(n)") { for _ in 0..<n { _ = EPUBBookParser.blocks(fromXHTML: chapter) } }
        _ = PerfBenchmarks.time("XHTMLFragment.make ×\(n)") {
            for _ in 0..<n { _ = XHTMLFragment.make(PerfBenchmarks.chapterText(60)) }
        }
        _ = PerfBenchmarks.time("regex newline replace ×\(n * 200)") {
            for _ in 0..<(n * 200) { _ = "a line of text\nwith one".replacingOccurrences(of: #"[\t\r\n]"#, with: " ", options: .regularExpression) }
        }
        var d = WorkDetails()
        d.updated = "2024-05-06"
        _ = PerfBenchmarks.time("latestDate ×1000") { for _ in 0..<1000 { _ = d.latestDate } }
    }

    func testExportBreakdown() throws {
        let html = PerfBenchmarks.bigExport(chapters: 40, paragraphs: 60)
        _ = PerfBenchmarks.time("element #chapters 504KB") {
            _ = WorkPageParser.element("div", #"<div id="chapters"[^>]*>"#, in: html)
        }
        _ = PerfBenchmarks.time("element #afterword 504KB") {
            _ = WorkPageParser.element("div", #"<div id="afterword"[^>]*>"#, in: html)
        }
        _ = PerfBenchmarks.time("plainText ×40 chapters") {
            for _ in 0..<40 { _ = WorkPageParser.plainText(PerfBenchmarks.chapterText(60)) }
        }
    }
}

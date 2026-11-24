import XCTest
@testable import AO3Kit

/// The faster paths give the same answers as the ones they replaced, and
/// the request-saving ones save requests.
final class PerfRegressionTests: XCTestCase {

    // MARK: - xmlSafe

    /// The entity pass as it was: one replace per name.
    static func oldXMLSafe(_ s: String) -> String {
        let names = ["nbsp", "mdash", "ndash", "hellip", "lsquo", "rsquo", "ldquo", "rdquo", "copy", "reg",
                     "trade", "middot", "bull", "laquo", "raquo", "eacute", "egrave", "aacute", "iacute",
                     "oacute", "uacute", "ntilde", "uuml", "ouml", "auml", "szlig", "times", "deg", "sect",
                     "para", "dagger", "hearts", "shy", "zwj", "zwnj"]
        var out = s
        for name in names {
            out = out.replacingOccurrences(of: "&\(name);", with: EPUBBookParser.xmlSafe("&\(name);"))
        }
        return out
    }

    func testXMLSafeResolvesEntities() {
        XCTAssertEqual(EPUBBookParser.xmlSafe("a&nbsp;b &mdash; c&hellip;"), "a\u{00A0}b — c…")
        XCTAssertEqual(EPUBBookParser.xmlSafe("&amp; &lt;b&gt; &#8217; &unknown; & ;"), "&amp; &lt;b&gt; &#8217; &unknown; & ;")
        XCTAssertEqual(EPUBBookParser.xmlSafe("&&nbsp;;"), "&\u{00A0};")
        XCTAssertEqual(EPUBBookParser.xmlSafe("tail &nbsp"), "tail &nbsp")
        XCTAssertEqual(EPUBBookParser.xmlSafe("“é” &eacute;&zwj;👩‍👧"), "“é” é\u{200D}👩‍👧")
        XCTAssertEqual(EPUBBookParser.xmlSafe("no entities"), "no entities")
    }

    /// The old pass compared characters, so an entity followed by a
    /// combining mark ("&zwj;" + U+0301) was left unresolved — and then
    /// failed the XML parse. Bytes don't care.
    func testXMLSafeResolvesAnEntityBeforeACombiningMark() {
        XCTAssertEqual(EPUBBookParser.xmlSafe("a&zwj;\u{0301}"), "a\u{200D}\u{0301}")
    }

    /// Same output as the old pass (combining marks after an entity aside).
    func testXMLSafeMatchesTheOldPass() {
        let pieces = ["&", ";", "nbsp", "&nbsp;", "&mdash;", "&amp;", "a", " ", "é", "👩‍👧", "&hearts",
                      "&#39;", "&zwnj;", "&zwj;", "<p>", "&shy;&shy;", "x;", "&&", "x\u{0301}"]
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<2000 {
            let s = (0..<Int.random(in: 0...12, using: &rng)).map { _ in pieces.randomElement(using: &rng)! }.joined()
            XCTAssertEqual(EPUBBookParser.xmlSafe(s), Self.oldXMLSafe(s), s.debugDescription)
        }
    }

    // MARK: - reader text

    func testSourceLineBreaksReadAsSpaces() {
        let blocks = EPUBBookParser.blocks(fromXHTML:
            "<html><body><p>one\r\ntwo\tthree\nfour  <em>five</em>\n six<br/>seven</p></body></html>")
        XCTAssertEqual(blocks.map(\.text), ["one two three four five six\nseven"])
        XCTAssertEqual(blocks[0].runs.map(\.text), ["one two three four ", "five", " six\nseven"])
    }

    // MARK: - dates

    func testLatestDate() {
        var d = WorkDetails()
        d.published = "2020-01-05"
        XCTAssertEqual(d.latestDate, Date(timeIntervalSince1970: 1_578_182_400))
        d.updated = " 2024-05-06 "
        XCTAssertEqual(d.latestDate, Date(timeIntervalSince1970: 1_714_953_600))
        d.updated = "May 6"
        XCTAssertNil(d.latestDate)
    }

    /// The hand-worked day matches the formatter for every day it accepts,
    /// and leaves the rest to it.
    func testUTCDayMatchesTheFormatter() {
        let f = WorkDetailsDates.day
        var day = f.date(from: "1999-12-25")!
        let end = f.date(from: "2031-03-02")!
        while day < end {
            let s = f.string(from: day)
            XCTAssertEqual(WorkDetailsDates.utcDay(s), day, s)
            day += 86_400
        }
        for s in ["2023-02-29", "2024-13-01", "2024-00-10", "2024-1-05", "2024/01/05", "1850-01-01", "２０２４-01-01", ""] {
            XCTAssertNil(WorkDetailsDates.utcDay(s), s)
        }
        XCTAssertNotNil(WorkDetailsDates.utcDay("2024-02-29"))
    }

    // MARK: - EPUB downloads off

    /// Once AO3's EPUB link has failed and its HTML download worked, the
    /// next save goes straight to the HTML download: two requests, not three.
    func testEPUBsOffIsRememberedBetweenSaves() async throws {
        CountingAO3.reset()
        let client = PerfBenchmarks.countingClient()
        let first = try await client.downloadEPUB(try await client.fetchWork(id: 95718386))
        try? FileManager.default.removeItem(at: first)
        XCTAssertEqual(CountingAO3.paths, ["/works/95718386", "/downloads/95718386/Three.epub", "/downloads/95718386/Three.html"])

        CountingAO3.reset()
        let second = try await client.downloadEPUB(try await client.fetchWork(id: 95718386))
        defer { try? FileManager.default.removeItem(at: second) }
        XCTAssertEqual(CountingAO3.paths, ["/works/95718386", "/downloads/95718386/Three.html"])
        XCTAssertEqual(ChapterGuard.chapterCount(epubAt: second), 3)
    }

    /// When the HTML download isn't there either, the EPUB is still tried.
    func testShortcutFallsBackToTheEPUB() async throws {
        CountingAO3.reset()
        let client = PerfBenchmarks.countingClient()
        client.epubsOff.mark()
        let work = WorkInfo(id: 7, title: "Gone", authors: ["a"],
                            epubURL: URL(string: "https://archiveofourown.org/downloads/7/Gone.epub")!, updatedAt: nil)
        do {
            _ = try await client.downloadEPUB(work)
            XCTFail("expected an error")
        } catch {}
        XCTAssertEqual(CountingAO3.paths, ["/downloads/7/Gone.html", "/downloads/7/Gone.epub"])
        XCTAssertFalse(client.epubsOff.recently())
    }

    func testEPUBsOffWearsOff() {
        final class Clock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 0) }
        let clock = Clock()
        let off = EPUBsOff(now: { clock.now })
        XCTAssertFalse(off.recently())
        off.mark()
        XCTAssertTrue(off.recently())
        clock.now = clock.now.addingTimeInterval(EPUBsOff.window - 1)
        XCTAssertTrue(off.recently())
        clock.now = clock.now.addingTimeInterval(2)
        XCTAssertFalse(off.recently())
    }
}

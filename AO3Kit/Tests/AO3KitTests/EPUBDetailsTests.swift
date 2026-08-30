import XCTest
@testable import AO3Kit

/// Fixtures mirror the exact structure of AO3's EPUB exports (verified
/// against a live download 2026-08) without embedding anyone's fic.
final class EPUBDetailsTests: XCTestCase {

    let opf = """
    <?xml version='1.0' encoding='utf-8'?>
    <package xmlns="http://www.idpf.org/2007/opf">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
        <dc:title>Some Work &amp; Its Title</dc:title>
        <dc:language>en</dc:language>
        <dc:creator opf:file-as="writer" opf:role="aut">Writer</dc:creator>
        <dc:description>&lt;p&gt;First line of the summary.&lt;/p&gt;&lt;p&gt;Second &amp;amp; final line.&lt;/p&gt;</dc:description>
        <dc:publisher>Archive of Our Own</dc:publisher>
        <dc:subject>Fanworks</dc:subject>
      </metadata>
    </package>
    """

    let preface = """
    <div id="preface">
      <p class="message">
        <b>Some Work</b><br/>
        Posted originally on the <a href="https://archiveofourown.org/">Archive of Our Own</a> at <a href="https://archiveofourown.org/works/74823621">https://archiveofourown.org/works/74823621</a>.
      </p>
      <dl class="tags">
        <dt>Rating:</dt>
        <dd><a href="https://archiveofourown.org/tags/Teen%20And%20Up%20Audiences">Teen And Up Audiences</a></dd>
        <dt>Archive Warning:</dt>
        <dd><a href="#">Creator Chose Not To Use Archive Warnings</a></dd>
        <dt>Category:</dt>
        <dd><a href="#">Gen</a></dd>
        <dt>Fandom:</dt>
        <dd><a href="#">Harry Potter - J. K. Rowling</a></dd>
        <dt>Relationships:</dt>
        <dd><a href="#">Draco Malfoy &amp; Harry Potter</a>, <a href="#">Harry Potter &amp; Ron Weasley</a></dd>
        <dt>Characters:</dt>
        <dd><a href="#">Harry Potter</a>, <a href="#">Draco Malfoy</a></dd>
        <dt>Additional Tags:</dt>
        <dd><a href="#">Fluff</a>, <a href="#">Alternate Universe</a></dd>
        <dt>Series:</dt>
        <dd>Part 2 of <a href="#">The Long Series</a></dd>
        <dt>Stats:</dt>
        <dd>
          Published: 2025-11-28
            Updated: 2026-08-30
          Words: 11,263
          Chapters: 5/?
        </dd>
      </dl>
    </div>
    """

    func testOPFFields() {
        let d = EPUBDetailsParser.parse(opf: opf, preface: nil)
        XCTAssertEqual(d.title, "Some Work & Its Title")
        XCTAssertEqual(d.authors, ["Writer"])
        XCTAssertEqual(d.summary, "First line of the summary.\n\nSecond & final line.")
    }

    func testPrefaceTags() {
        let d = EPUBDetailsParser.parse(opf: opf, preface: preface)
        XCTAssertEqual(d.workURL?.absoluteString, "https://archiveofourown.org/works/74823621")
        XCTAssertEqual(d.rating, ["Teen And Up Audiences"])
        XCTAssertEqual(d.warnings, ["Creator Chose Not To Use Archive Warnings"])
        XCTAssertEqual(d.categories, ["Gen"])
        XCTAssertEqual(d.fandoms, ["Harry Potter - J. K. Rowling"])
        XCTAssertEqual(d.relationships, ["Draco Malfoy & Harry Potter", "Harry Potter & Ron Weasley"])
        XCTAssertEqual(d.characters, ["Harry Potter", "Draco Malfoy"])
        XCTAssertEqual(d.additionalTags, ["Fluff", "Alternate Universe"])
        XCTAssertEqual(d.series, "Part 2 of The Long Series")
    }

    func testStats() {
        let d = EPUBDetailsParser.parse(opf: opf, preface: preface)
        XCTAssertEqual(d.published, "2025-11-28")
        XCTAssertEqual(d.updated, "2026-08-30")
        XCTAssertEqual(d.words, "11,263")
        XCTAssertEqual(d.chapters, "5/?")
    }

    func testSeriesNameAndPart() {
        let d = EPUBDetailsParser.parse(opf: opf, preface: preface)
        XCTAssertEqual(d.seriesName, "The Long Series")
        XCTAssertEqual(d.seriesPart, 2)
        var plain = WorkDetails()
        plain.series = "Some Series Without Part"
        XCTAssertEqual(plain.seriesName, "Some Series Without Part")
        XCTAssertNil(plain.seriesPart)
        XCTAssertNil(WorkDetails().seriesName)
    }

    func testMissingEverythingFailsSoft() {
        let d = EPUBDetailsParser.parse(opf: "", preface: nil)
        XCTAssertNil(d.title)
        XCTAssertNil(d.summary)
        XCTAssertEqual(d.additionalTags, [])
        XCTAssertNil(d.series)
    }

    /// Full zip round-trip against a real AO3 EPUB when one is provided via
    /// AO3KIT_SAMPLE_EPUB (kept out of the repo).
    func testRealEPUB() throws {
        guard let path = ProcessInfo.processInfo.environment["AO3KIT_SAMPLE_EPUB"] else {
            throw XCTSkip("set AO3KIT_SAMPLE_EPUB to run")
        }
        let d = try EPUBDetailsParser.parse(epubAt: URL(fileURLWithPath: path))
        XCTAssertNotNil(d.title)
        XCTAssertFalse(d.authors.isEmpty)
        XCTAssertNotNil(d.workURL)
        XCTAssertFalse(d.fandoms.isEmpty)
        XCTAssertNotNil(d.words)
    }
}

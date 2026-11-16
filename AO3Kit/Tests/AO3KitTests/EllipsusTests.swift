import XCTest
@testable import AO3Kit

final class EllipsusTests: XCTestCase {
    /// A small Yjs document (made with Yjs itself): a heading, marked runs,
    /// an empty paragraph, a centered paragraph with a hard break, a quote.
    static let update = "ASGSnO30BAAHAQ1kcmFmdC1jb250ZW50AwdoZWFkaW5nBwCSnO30BAAGBACSnO30BAELQ2hhcHRlciBPbmUoAJKc7fQEAAVsZXZlbAF9AoeSnO30BAADCXBhcmFncmFwaAcAkpzt9AQOBgQAkpzt9AQPClBsYWluIGFuZCCHkpzt9AQPBgYAkpzt9AQaBGJvbGQCe32Ekpzt9AQbBGJvbGSGkpzt9AQfBGJvbGQEbnVsbIeSnO30BBoGBACSnO30BCEFIGFuZCCHkpzt9AQhBgYAkpzt9AQnBGJvbGQCe32Gkpzt9AQoBml0YWxpYwJ7fYaSnO30BCkJdGV4dFN0eWxlEHsiY29sb3IiOiIjZmZmIn2Ekpzt9AQqCGJvdGggPCY+hpKc7fQEMgRib2xkBG51bGyGkpzt9AQzBml0YWxpYwRudWxshpKc7fQENAl0ZXh0U3R5bGUEbnVsbIeSnO30BA4DCXBhcmFncmFwaIeSnO30BDYDCXBhcmFncmFwaAcAkpzt9AQ3BgQAkpzt9AQ4A29uZYeSnO30BDgDCWhhcmRCcmVha4eSnO30BDwGBACSnO30BD0DdHdvKACSnO30BDcJdGV4dEFsaWduAXcGY2VudGVyh5Kc7fQENwMKYmxvY2txdW90ZQcAkpzt9ARCAwlwYXJhZ3JhcGgHAJKc7fQEQwYEAJKc7fQERAZxdW90ZWQA"

    func testLinks() {
        XCTAssertEqual(AO3Link(text: "https://ellipsus.com/read/68yjjhWW0GtnqxcQJDUd54/Late-Night-Read-Phanfic"),
                       .ellipsus(id: "68yjjhWW0GtnqxcQJDUd54"))
        XCTAssertEqual(AO3Link(text: "ellipsus.com/read/68yjjhWW0GtnqxcQJDUd54")?.workID, nil)
        XCTAssertEqual(AO3Link.all(in: "https://ellipsus.com/read/AAAAAAAAAAAA\nhttps://archiveofourown.org/works/9"),
                       [.ellipsus(id: "AAAAAAAAAAAA"), .work(id: 9)])
    }

    func testDocumentBecomesXHTML() throws {
        let (html, words) = try EllipsusDocument.xhtml(updates: [Self.update])
        XCTAssertEqual(html, """
        <h2>Chapter One</h2>
        <p>Plain and <strong>bold</strong> and <strong><em>both &lt;&amp;&gt;</em></strong></p>
        <p style="text-align: center">one<br/>two</p>
        <blockquote><p>quoted</p></blockquote>
        """)
        XCTAssertEqual(words, 11)
        XCTAssertTrue(XHTMLFragment.isWellFormed(html))
    }

    func testPageAndEPUB() throws {
        let resolved = EllipsusClient.Resolved(name: "A Story", description: "Short & sweet",
                                               nickname: "writer", createdAt: "2026-11-05T01:59:37.777Z")
        let page = try EllipsusClient.page(id: "abcdefgh12", resolved: resolved, updates: [Self.update])
        XCTAssertEqual(page.authors, ["writer"])
        XCTAssertEqual(page.published, "2026-11-05")
        let files = Dictionary(uniqueKeysWithValues: WorkPageEPUB.files(page, source: "Saved from Ellipsus."))
        let preface = try XCTUnwrap(files["preface.xhtml"])
        XCTAssertTrue(preface.contains("Posted originally on Ellipsus at"))
        XCTAssertFalse(preface.contains("archiveofourown"))
        XCTAssertFalse(try XCTUnwrap(files["afterword.xhtml"]).contains("archiveofourown"))
        // Read back, it's a story with a source link and no AO3 work.
        let details = EPUBDetailsParser.parse(opf: try XCTUnwrap(files["content.opf"]), preface: preface)
        XCTAssertNil(details.workID)
        XCTAssertEqual(details.sourceURL?.absoluteString, "https://ellipsus.com/read/abcdefgh12")
        XCTAssertEqual(details.title, "A Story")
    }
}

import XCTest
@testable import AO3Kit

/// Fixtures mirror AO3's EPUB exports (Calibre-converted XHTML: a preface,
/// one file per chapter, an afterword) without embedding anyone's fic.
final class EPUBBookTests: XCTestCase {

    func testChapterParagraphsKeepInlineStyle() {
        let xhtml = """
        <?xml version='1.0' encoding='utf-8'?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>T</title></head>
        <body class="calibre"><div id="chapters">
          <h2 class="toc-heading">Chapter 1: Tea</h2>
          <div class="userstuff">
            <p class="calibre7">She said,
              <em>never</em> again — and meant <strong>it</strong>.</p>
            <hr/>
            <p>Line one<br/>line two</p>
          </div>
        </div></body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml)
        XCTAssertEqual(blocks.map(\.kind), [.heading(level: 2), .paragraph, .rule, .paragraph])
        XCTAssertEqual(blocks[0].text, "Chapter 1: Tea")
        XCTAssertEqual(blocks[1].text, "She said, never again — and meant it.")
        XCTAssertEqual(blocks[1].runs.first { $0.text == "never" }?.italic, true)
        XCTAssertEqual(blocks[1].runs.first { $0.text == "it" }?.bold, true)
        XCTAssertEqual(blocks[3].text, "Line one\nline two")
    }

    func testPrefaceSkipsTagListAndBoilerplate() {
        let xhtml = """
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
          <p class="message"><b>Work</b><br/>Posted originally on the Archive of Our Own.</p>
          <dl class="tags"><dt>Rating:</dt><dd><a href="https://archiveofourown.org/tags/x">Explicit</a></dd></dl>
          <h1>Work</h1>
          <p>Summary</p>
          <blockquote class="userstuff"><p>A summary.</p></blockquote>
          <div class="endnote-link">See the end of the work for <a href="x.xhtml#endnotes">more notes</a></div>
        </body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml)
        XCTAssertEqual(blocks.map(\.text), ["Work", "Summary", "A summary."])
        XCTAssertEqual(blocks[2].quoteDepth, 1)
    }

    func testNamedHTMLEntitiesDoNotBreakParsing() {
        let xhtml = "<html><body><p>Wait&hellip; what&nbsp;now &amp; then</p></body></html>"
        XCTAssertEqual(EPUBBookParser.blocks(fromXHTML: xhtml).map(\.text), ["Wait… what\u{00A0}now & then"])
    }

    func testMalformedDocumentFallsBackToPlainParagraphs() {
        let html = "<html><body><p>One <i>two</p><p>Three</body></html>"
        XCTAssertEqual(EPUBBookParser.blocks(fromXHTML: html).map(\.text), ["One two", "Three"])
    }

    func testSpineOrderAndTOCTitles() {
        let opf = """
        <package><manifest>
          <item id="html2" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>
          <item id="html1" href="Text/preface.xhtml" media-type="application/xhtml+xml"/>
          <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
        </manifest><spine toc="ncx"><itemref idref="html1"/><itemref idref="html2"/></spine></package>
        """
        XCTAssertEqual(EPUBBookParser.spine(opf: opf), ["Text/preface.xhtml", "Text/ch1.xhtml"])
        XCTAssertEqual(EPUBBookParser.tocPath(opf: opf), "toc.ncx")

        let ncx = """
        <navMap>
          <navPoint id="n1"><navLabel><text>Preface</text></navLabel><content src="Text/preface.xhtml"/></navPoint>
          <navPoint id="n2"><navLabel><text>Chapter 1 &amp; More</text></navLabel><content src="Text/ch1.xhtml#calibre_toc_2"/></navPoint>
        </navMap>
        """
        XCTAssertEqual(EPUBBookParser.ncxTitles(ncx), ["Text/preface.xhtml": "Preface", "Text/ch1.xhtml": "Chapter 1 & More"])
    }

    func testResolveRelativeHrefs() {
        XCTAssertEqual(EPUBBookParser.resolve("ch1.xhtml", base: ""), "ch1.xhtml")
        XCTAssertEqual(EPUBBookParser.resolve("../Text/ch1.xhtml", base: "OEBPS/Styles"), "OEBPS/Text/ch1.xhtml")
    }
}

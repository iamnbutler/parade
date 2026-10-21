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

    func testTypedSceneBreaksBecomeRules() {
        let xhtml = "<html><body><p>Before.</p><p>~~~~~~~~~~</p><p>* * *</p><p>-----</p><p>Ooo, after.</p><p>...</p></body></html>"
        XCTAssertEqual(EPUBBookParser.blocks(fromXHTML: xhtml).map(\.kind),
                       [.paragraph, .rule, .rule, .rule, .paragraph, .paragraph])
        XCTAssertFalse(BlockBuilder.isTypedBreak("Oh."))
        XCTAssertFalse(BlockBuilder.isTypedBreak("xox"))
    }

    func testAlignmentFromAttributeClassAndCenterTag() {
        let css = ".calibre8 { text-align: center; margin: 0 } p.calibre9 { text-align: right }"
        let xhtml = """
        <html><body>
          <p align="center">Dear diary,</p>
          <p class="calibre8">centred by class</p>
          <p class="calibre9">signed, me</p>
          <center><p>old-school</p></center>
          <p style="text-align: center">inline</p>
          <p>plain</p>
        </body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml, classes: EPUBBookParser.stylesheet(css), base: "")
        XCTAssertEqual(blocks.map(\.alignment), [.center, .center, .right, .center, .center, .natural])
    }

    func testListItemsCarryMarkersNotText() {
        let xhtml = """
        <html><body>
          <ol start="3"><li>Three</li><li><p>Four</p><p>more of four</p></li>
            <li value="9">Nine<ul><li>nested</li></ul></li></ol>
          <ul><li>dot</li></ul>
          <p>after</p>
          <table><tr><td><ol><li>in a cell</li></ol></td></tr></table>
        </body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml)
        XCTAssertEqual(blocks.map(\.text).prefix(7), ["Three", "Four", "more of four", "Nine", "nested", "dot", "after"])
        XCTAssertEqual(blocks.map(\.marker).prefix(7), [.number(3), .number(4), nil, .number(9), .bullet, .bullet, nil])
        XCTAssertEqual(blocks.map(\.listDepth).prefix(7), [1, 1, 1, 1, 2, 1, 0])
        guard case .table(let rows) = blocks.last?.kind else { return XCTFail("no table") }
        XCTAssertEqual(rows[0][0].map(\.text).joined(), "1. in a cell")
    }

    func testStrikethroughAndScriptsFromTagsAndClasses() {
        let css = ".calibre12 { text-decoration: line-through } .calibre13 { vertical-align: super; font-size: 0.75em }"
        let xhtml = """
        <html><body><p>I <s>hate</s> <del>loathe</del> <span class="calibre12">adore</span> you,
        x<sup>2</sup> H<sub>2</sub>O and 1<span class="calibre13">st</span></p></body></html>
        """
        let runs = EPUBBookParser.blocks(fromXHTML: xhtml, classes: EPUBBookParser.stylesheet(css), base: "")[0].runs
        XCTAssertEqual(runs.filter(\.strikethrough).map(\.text), ["hate", "loathe", "adore"])
        XCTAssertEqual(runs.filter { $0.baseline == .superscript }.map(\.text), ["2", "st"])
        XCTAssertEqual(runs.filter { $0.baseline == .subscript }.map(\.text), ["2"])
    }

    func testClassStylesItalicBoldAndHidden() {
        let css = ".calibre4 { font-style: italic } .calibre5 { font-weight: 700 } .calibre6 { display: none }"
        let xhtml = """
        <html><body><p><span class="calibre4">thought</span> and <span class="calibre5">shout</span></p>
        <p class="calibre6">hidden</p></body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml, classes: EPUBBookParser.stylesheet(css), base: "")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].runs.first { $0.text == "thought" }?.italic, true)
        XCTAssertEqual(blocks[0].runs.first { $0.text == "shout" }?.bold, true)
    }

    func testTablesBecomeRowsOfCells() {
        let xhtml = """
        <html><body><p>Before.</p>
        <table><tr><td><b>Rumi</b></td><td>where are you</td></tr>
        <tr><td>Jinu</td><td><p>on my way</p><p>5 min</p></td></tr></table>
        <p>After.</p></body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml)
        XCTAssertEqual(blocks.count, 3)
        guard case .table(let rows) = blocks[1].kind else { return XCTFail("no table") }
        XCTAssertEqual(rows.map { $0.map { $0.map(\.text).joined() } },
                       [["Rumi", "where are you"], ["Jinu", "on my way\n5 min"]])
        XCTAssertEqual(rows[0][0].first?.bold, true)
    }

    func testImagesAreBlocksWithResolvedPaths() {
        let xhtml = """
        <html><body><p>Art by a friend:</p>
        <p><img src="../images/00001.jpg" alt="Rumi, sketched"/></p>
        <img src="https://example.com/a.png" alt=""/>
        </body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml, classes: [:], base: "OEBPS/Text")
        XCTAssertEqual(blocks.map(\.kind), [
            .paragraph,
            .image(source: "OEBPS/images/00001.jpg", alt: "Rumi, sketched"),
            .image(source: "https://example.com/a.png", alt: ""),
        ])
    }

    func testTextingSkinBecomesChat() {
        // AO3 texting work skins (Calibre keeps the markup): a <dl> thread.
        let xhtml = """
        <html><body><p>Before.</p>
        <dl class="calibre14">
          <h1 class="contact">Unknown Number</h1>
          <h4 class="time"><b>Today</b>, 12:21 PM</h4>
          <div><dt>Shane</dt><dd>Is this Ilya Rozanov?</dd></div>
          <div><dt>Unknown Number</dt><dd>no</dd></div>
          <div><dt>Shane</dt><dd>Oh, but the dog collar had this number.</dd>
            <dd><img src="img1.jpg" class="calibre11"/></dd></div>
          <kbd class="typebar"></kbd>
        </dl>
        <div class="byline" style="text-align:center"><p>—×—</p></div>
        </body></html>
        """
        let blocks = EPUBBookParser.blocks(fromXHTML: xhtml)
        XCTAssertEqual(blocks.count, 3)
        guard case .chat(let chat) = blocks[1].kind else { return XCTFail("no chat") }
        XCTAssertEqual(chat.title, "Unknown Number")
        XCTAssertEqual(chat.items, [
            .note("Today, 12:21 PM"),
            .message(sender: "Shane", runs: [.init(text: "Is this Ilya Rozanov?")]),
            .message(sender: "Unknown Number", runs: [.init(text: "no")]),
            .message(sender: "Shane", runs: [.init(text: "Oh, but the dog collar had this number.")]),
            .image(sender: "Shane", source: "img1.jpg", alt: ""),
        ])
        XCTAssertEqual(chat.me, "Shane")
        XCTAssertEqual(blocks[2].kind, .rule)

        // A decorated contact header still names the other side.
        let other = EPUBBook.Chat(title: "Shane ☀️", items: [
            .message(sender: "Shane", runs: [.init(text: "a")]),
            .message(sender: "Shane", runs: [.init(text: "b")]),
            .message(sender: "Ilya", runs: [.init(text: "c")]),
        ])
        XCTAssertEqual(other.me, "Ilya")
    }

    func testResolveRelativeHrefs() {
        XCTAssertEqual(EPUBBookParser.resolve("ch1.xhtml", base: ""), "ch1.xhtml")
        XCTAssertEqual(EPUBBookParser.resolve("../Text/ch1.xhtml", base: "OEBPS/Styles"), "OEBPS/Text/ch1.xhtml")
    }
}

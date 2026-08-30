import XCTest
@testable import AO3Kit

/// Fixtures mirror the exact markup shapes AO3 serves (verified against live
/// pages 2026-08) without embedding anyone's actual fic.
final class HTMLExtractTests: XCTestCase {

    let workPage = """
    <html><body>
    <ul class="expandable secondary hidden" id="downloads">
      <li class="download"><a href="/downloads/74823621/Some_Work.azw3?updated_at=1788112176">AZW3</a></li>
      <li class="download"><a href="/downloads/74823621/Some_Work.epub?updated_at=1788112176">EPUB</a></li>
      <li class="download"><a href="/downloads/74823621/Some_Work.pdf?updated_at=1788112176">PDF</a></li>
    </ul>
    <div class="preface group">
      <h2 class="title heading">
        Harry&#8217;s First &amp; Best Friend
      </h2>
      <h3 class="byline heading">
        <a rel="author" href="/users/someone/pseuds/someone">someone</a>
      </h3>
    </div>
    </body></html>
    """

    func testTitle() {
        XCTAssertEqual(HTMLExtract.title(in: workPage), "Harry\u{2019}s First & Best Friend")
    }

    func testAuthors() {
        XCTAssertEqual(HTMLExtract.authors(in: workPage), ["someone"])
    }

    func testCoAuthorsDeduplicated() {
        let html = """
        <a rel="author" href="/users/a/pseuds/a">alpha</a>,
        <a rel="author" href="/users/b/pseuds/b">beta</a>,
        <a rel="author" href="/users/a/pseuds/a">alpha</a>
        """
        XCTAssertEqual(HTMLExtract.authors(in: html), ["alpha", "beta"])
    }

    func testEPUBPathPicksOnlyEpub() {
        XCTAssertEqual(
            HTMLExtract.epubPath(in: workPage),
            "/downloads/74823621/Some_Work.epub?updated_at=1788112176"
        )
    }

    func testSeriesWorkIDsInOrder() {
        let html = """
        <ul class="series work index group">
          <li id="work_128" class="work blurb group">
            <h4 class="heading">
              <a href="/works/128">First One</a>
              by <a rel="author" href="/users/x">x</a>
            </h4>
          </li>
          <li id="work_97" class="work blurb group">
            <h4 class="heading">
              <a href="/works/97">Second One</a>
              by <a rel="author" href="/users/x">x</a>
            </h4>
          </li>
        </ul>
        """
        XCTAssertEqual(HTMLExtract.seriesWorkIDs(in: html), [128, 97])
    }

    func testLoginPageDetection() {
        XCTAssertTrue(HTMLExtract.isLoginPage("<form id=\"new_user_session\">", finalURL: nil))
        XCTAssertTrue(HTMLExtract.isLoginPage("", finalURL: URL(string: "https://archiveofourown.org/users/login?restricted=true")))
        XCTAssertFalse(HTMLExtract.isLoginPage(workPage, finalURL: URL(string: "https://archiveofourown.org/works/74823621")))
    }

    func testEntityDecoding() {
        XCTAssertEqual(HTMLExtract.decodeEntities("&amp;&lt;&gt;&quot;&#39;&#x27;"), "&<>\"''")
        XCTAssertEqual(HTMLExtract.decodeEntities("caf&#233;"), "café")
    }

    func testMissingFieldsFailSoft() {
        XCTAssertNil(HTMLExtract.title(in: "<html></html>"))
        XCTAssertNil(HTMLExtract.epubPath(in: "<html></html>"))
        XCTAssertEqual(HTMLExtract.authors(in: "<html></html>"), [])
        XCTAssertEqual(HTMLExtract.seriesWorkIDs(in: "<html></html>"), [])
    }
}

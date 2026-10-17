import XCTest
@testable import AO3Kit

final class AO3LinkTests: XCTestCase {
    func testWorkURL() {
        XCTAssertEqual(AO3Link(text: "https://archiveofourown.org/works/74823621"), .work(id: 74823621))
    }

    func testChapterURL() {
        XCTAssertEqual(
            AO3Link(text: "https://archiveofourown.org/works/12345/chapters/67890"),
            .work(id: 12345)
        )
    }

    func testURLWithQueryParams() {
        XCTAssertEqual(
            AO3Link(text: "https://archiveofourown.org/works/12345?view_adult=true&view_full_work=true"),
            .work(id: 12345)
        )
    }

    func testCollectionScopedWork() {
        XCTAssertEqual(
            AO3Link(text: "https://archiveofourown.org/collections/some_collection/works/999"),
            .work(id: 999)
        )
    }

    func testSeriesURL() {
        XCTAssertEqual(AO3Link(text: "https://archiveofourown.org/series/9"), .series(id: 9))
    }

    func testLinkBuriedInPastedText() {
        XCTAssertEqual(
            AO3Link(text: "omg read this!! https://archiveofourown.org/works/128 so good"),
            .work(id: 128)
        )
    }

    func testMobileShareURLWithWWW() {
        XCTAssertEqual(AO3Link(text: "http://www.archiveofourown.org/works/42"), .work(id: 42))
    }

    func testNonAO3TextRejected() {
        XCTAssertNil(AO3Link(text: "https://example.com/works/123"))
        XCTAssertNil(AO3Link(text: "just some words"))
        XCTAssertNil(AO3Link(text: ""))
    }

    func testPageURLGatesAdultContent() {
        let url = AO3Link.work(id: 5).pageURL.absoluteString
        XCTAssertTrue(url.contains("view_adult=true"))
    }

    func testAllFindsEveryLinkInOrder() {
        let text = """
        https://archiveofourown.org/works/1
        https://archiveofourown.org/series/2, https://archiveofourown.org/works/3/chapters/9
        /works/4
        """
        XCTAssertEqual(AO3Link.all(in: text), [.work(id: 1), .series(id: 2), .work(id: 3), .work(id: 4)])
    }

    func testAllDropsDuplicatesAndNoise() {
        let text = "read https://archiveofourown.org/works/7 and archiveofourown.org/works/7?view_adult=true lol https://example.com/works/8"
        XCTAssertEqual(AO3Link.all(in: text), [.work(id: 7)])
        XCTAssertEqual(AO3Link.all(in: "nothing here"), [])
    }
}

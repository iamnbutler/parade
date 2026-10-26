import XCTest
@testable import AO3Kit

final class AO3UpdateCheckTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!

    func params(_ query: AO3WorkQuery) -> [String: String] {
        let items = URLComponents(url: query.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    func testIDQueryIsAnORChainSortedByUpdate() {
        let query = AO3WorkQuery(source: .ids([111, 222, 333]), sort: .updated)
        XCTAssertTrue(query.url.absoluteString.hasPrefix("https://archiveofourown.org/works/search?"))
        let p = params(query)
        XCTAssertEqual(p["work_search[query]"], "id:111 OR id:222 OR id:333")
        XCTAssertEqual(p["work_search[sort_column]"], "revised_at")
        XCTAssertNil(p["work_search[revised_at]"])
    }

    func testChunksAtFourHundredAndDropsRepeats() {
        let ids = Array(1...900) + [5, 6]
        let queries = AO3UpdateCheck.queries(ids: ids, since: nil, now: now)
        let chunks = queries.map { q -> [Int] in
            guard case .ids(let ids) = q.source else { return [] }
            return ids
        }
        XCTAssertEqual(chunks.map(\.count), [400, 400, 100])
        XCTAssertEqual(chunks.flatMap { $0 }, Array(1...900))
        XCTAssertTrue(queries.allSatisfy { $0.page == 1 && $0.sort == .updated && $0.revised == nil })
        XCTAssertEqual(AO3UpdateCheck.queries(ids: [], since: nil, now: now).count, 0)
    }

    func testSinceBecomesARevisedFieldWithADayOfOverlap() {
        let threeDaysAgo = now.addingTimeInterval(-3 * 86400)
        let query = AO3UpdateCheck.queries(ids: [1, 2], since: threeDaysAgo, now: now)[0]
        XCTAssertEqual(query.revised, .withinDays(4))
        let p = params(query)
        XCTAssertEqual(p["work_search[revised_at]"], "< 4 days")
        XCTAssertEqual(p["work_search[query]"], "id:1 OR id:2")

        // A check a minute ago still looks back a day.
        let justNow = AO3UpdateCheck.queries(ids: [1], since: now.addingTimeInterval(-60), now: now)[0]
        XCTAssertEqual(justNow.revised, .withinDays(2))
    }

    func testSinceCanGoInTheQueryText() {
        let since = ISO8601DateFormatter().date(from: "2026-10-21T09:30:00Z")!
        let query = AO3UpdateCheck.queries(ids: [1, 2], since: since, now: now, dateFilter: .inQuery)[0]
        let p = params(query)
        XCTAssertEqual(p["work_search[query]"], "(id:1 OR id:2) AND revised_at:[2026-10-20 TO *]")
        XCTAssertNil(p["work_search[revised_at]"])

        let alone = AO3WorkQuery(source: .tag("Crack"), revised: .inQuery(since: since))
        XCTAssertEqual(params(alone)["work_search[query]"], "revised_at:[2026-10-21 TO *]")
    }

    func testPagesThroughEachChunkAndYieldsBlurbs() async throws {
        let requested = Log<AO3WorkQuery>()
        let check = AO3UpdateCheck(now: { self.now }) { query in
            await requested.add(query)
            guard case .ids(let ids) = query.source else { return WorkResults(works: [], page: 1, hasNextPage: false) }
            // 25 matches in the first chunk (two pages), 1 in the second.
            let matched = ids.count == 400 ? Array(ids.prefix(25)) : Array(ids.prefix(1))
            let page = Array(matched.dropFirst((query.page - 1) * 20).prefix(20))
            let works = page.map { WorkBlurb(id: $0, title: "t\($0)", authors: ["a"]) }
            return WorkResults(works: works, total: matched.count, page: query.page,
                               hasNextPage: query.page * 20 < matched.count)
        }
        var batches: [[Int]] = []
        for try await blurbs in check.revisedWorks(ids: Array(1...450), since: nil) {
            batches.append(blurbs.map(\.id))
        }
        XCTAssertEqual(batches.map(\.count), [20, 5, 1])
        XCTAssertEqual(batches.last, [401])
        let pages = await requested.items.map(\.page)
        XCTAssertEqual(pages, [1, 2, 1])
    }

    func testStopsWhenAPageFailsAndNeverPagesPastTheChunk() async {
        let calls = Log<Int>()
        let check = AO3UpdateCheck(now: { self.now }) { query in
            await calls.add(query.page)
            // A listing that always claims more pages.
            return WorkResults(works: [WorkBlurb(id: query.page, title: "t", authors: [])],
                               page: query.page, hasNextPage: true)
        }
        var count = 0
        do {
            for try await _ in check.revisedWorks(ids: Array(1...30), since: nil) { count += 1 }
        } catch {
            XCTFail("\(error)")
        }
        XCTAssertEqual(count, 2)  // 30 IDs fit on two pages

        let failing = AO3UpdateCheck(now: { self.now }) { _ in throw AO3Error.rateLimited(retryAfter: nil) }
        do {
            for try await _ in failing.revisedWorks(ids: [1], since: nil) {}
            XCTFail("expected a rate limit")
        } catch {
            XCTAssertEqual(error as? AO3Error, .rateLimited(retryAfter: nil))
        }
    }

    func testRequestsGoThroughTheSchedulerAtBackgroundPriority() async throws {
        // Real client, real scheduler with a test clock; the session is never
        // reached because the scheduler is checked first via a stub protocol.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSearch.self]
        let clock = TestClock()
        let scheduler = AO3Scheduler(clock: clock)
        let client = AO3Client(session: URLSession(configuration: config), scheduler: scheduler)

        var ids: [Int] = []
        for try await blurbs in client.revisedWorks(ids: [76008221, 72894606, 1], since: nil) {
            ids += blurbs.map(\.id)
        }
        XCTAssertEqual(ids, [76008221, 72894606])
        XCTAssertEqual(StubSearch.lastQuery, "id:76008221 OR id:72894606 OR id:1")
    }

    // MARK: - blurb chapters and dates

    func testBlurbChapterCountsAndUpdatedDate() {
        let results = BlurbExtract.results(in: Self.wipPage, page: 1)
        XCTAssertEqual(results.works.count, 1)
        let wip = results.works[0]
        XCTAssertEqual(wip.id, 12345678)
        XCTAssertEqual(wip.chapters, "108/?")
        XCTAssertEqual(wip.chaptersPosted, 108)
        XCTAssertNil(wip.chaptersExpected)
        XCTAssertEqual(wip.isComplete, false)
        XCTAssertEqual(wip.date, "3 Oct 2026")
        XCTAssertEqual(wip.updated, ISO8601DateFormatter().date(from: "2026-10-03T00:00:00Z"))
        XCTAssertFalse(results.hasNextPage)

        let done = BlurbExtract.results(in: AO3SearchTests.searchPage, page: 1).works[0]
        XCTAssertEqual(done.chaptersPosted, 1)
        XCTAssertEqual(done.chaptersExpected, 1)
        XCTAssertEqual(done.updated, ISO8601DateFormatter().date(from: "2025-12-19T00:00:00Z"))

        var planned = WorkBlurb(id: 1, title: "t", authors: [])
        planned.chapters = "3/10"
        XCTAssertEqual(planned.chaptersPosted, 3)
        XCTAssertEqual(planned.chaptersExpected, 10)
        planned.chapters = nil
        XCTAssertNil(planned.chaptersPosted)
        XCTAssertNil(planned.updated)
    }

    /// A multi-chapter work in progress, shaped like AO3's search results:
    /// the posted count links to the latest chapter.
    static let wipPage = #"""
<h3 class="heading">1 Found  <a class="help symbol question modal" href="/help/work-search-results-help.html"></a></h3>
<ol class="work index group">
<li id="work_12345678" class="work blurb group work-12345678 user-1" role="article">
  <div class="header module">
    <h4 class="heading">
      <a href="/works/12345678">A Long One</a>
      by
      <a rel="author" href="/users/someone/pseuds/someone">someone</a>
    </h4>
    <ul class="required-tags">
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="complete-no iswip" title="Work in Progress"><span class="text">Work in Progress</span></span></a></li>
</ul>
    <p class="datetime">3 Oct 2026</p>
  </div>
  <dl class="stats">
    <dt class="words">Words:</dt>
    <dd class="words">512,040</dd>
    <dt class="chapters">Chapters:</dt>
    <dd class="chapters"><a href="/works/12345678/chapters/170000001">108</a>/?</dd>
  </dl>
</li>
</ol>
<ol role="navigation" aria-label="Pagination" class="pagination actions" title="pagination"><li class="previous" title="previous"><span class="disabled">&#8592; Previous</span></li> <li class="next" title="next"><span class="disabled">Next &#8594;</span></li></ol>
"""#
}

/// Answers any search with the two works of `AO3SearchTests.searchPage`, on one page.
final class StubSearch: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastQuery: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lastQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "work_search[query]" }?.value
        let html = AO3SearchTests.searchPage.replacingOccurrences(of: #"<li class="next""#, with: #"<li class="gone""#)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

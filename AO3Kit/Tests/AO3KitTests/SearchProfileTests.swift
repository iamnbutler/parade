import XCTest
@testable import AO3Kit

final class SearchProfileTests: XCTestCase {
    private func items(_ url: URL) -> [String: String] {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        return Dictionary((comps.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { a, _ in a }
    }

    func testSeedsFandomsMostFicsFirst() {
        var p = SearchProfile()
        XCTAssertTrue(p.seedIfNeeded(fandomLists: [["B", "A"], ["A"], ["C"], ["A", "A"], ["B"]]))
        XCTAssertEqual(p.fandoms.map(\.name), ["A", "B", "C"])
        XCTAssertTrue(p.seeded)

        // Never again: the person's changes stick.
        p.fandoms.removeFirst()
        XCTAssertFalse(p.seedIfNeeded(fandomLists: [["A"], ["Z"]]))
        XCTAssertEqual(p.fandoms.map(\.name), ["B", "C"])
    }

    func testResetAndClearKeepHidden() {
        var p = SearchProfile()
        p.fandoms = [TagRef(name: "X")]
        p.words = "slow burn"
        p.includeTags = [TagRef(name: "Fluff")]
        p.hiddenTags = [TagRef(name: "Major Character Death")]
        p.hiddenAuthors = ["someone"]

        p.reset(fandomLists: [["A"]])
        XCTAssertEqual(p.fandoms.map(\.name), ["A"])
        XCTAssertEqual(p.words, "")
        XCTAssertEqual(p.includeTags, [])
        XCTAssertEqual(p.hiddenTags.map(\.name), ["Major Character Death"])

        p.clear()
        XCTAssertEqual(p.fandoms, [])
        XCTAssertEqual(p.hiddenAuthors, ["someone"])
    }

    func testAnyOfFandomsByIDOrName() {
        var p = SearchProfile()
        XCTAssertEqual(p.queryText, "")
        p.fandoms = [TagRef(name: "Hades (Video Game)", canonical: "Hades (Supergiant Games Video Games)", id: 42),
                     TagRef(name: "Hollow Knight (Video Game)")]
        XCTAssertEqual(p.queryText, #"(filter_ids:42 OR tag:"Hollow Knight (Video Game)")"#)
        p.words = " slow burn "
        XCTAssertEqual(p.queryText, #"(slow burn) AND (filter_ids:42 OR tag:"Hollow Knight (Video Game)")"#)
        p.fandoms = [TagRef(name: #"A "quoted" one"#)]
        XCTAssertEqual(p.queryText, #"(slow burn) AND tag:"A \"quoted\" one""#)
        p.fandoms = []
        XCTAssertEqual(p.queryText, "slow burn")
    }

    func testProfileURL() {
        var p = SearchProfile()
        p.fandoms = [TagRef(name: "A", id: 1), TagRef(name: "B", id: 2)]
        p.includeTags = [TagRef(name: "Fluff"), TagRef(name: "x", canonical: "Hurt/Comfort")]
        p.hiddenTags = [TagRef(name: "Major Character Death")]
        p.explicitOnly = true
        p.completeOnly = true
        p.sort = .kudos
        let url = p.query(page: 3).url
        XCTAssertTrue(url.absoluteString.hasPrefix("https://archiveofourown.org/works/search?"), url.absoluteString)
        let q = items(url)
        XCTAssertEqual(q["work_search[query]"], "(filter_ids:1 OR filter_ids:2)")
        XCTAssertEqual(q["work_search[other_tag_names]"], "Fluff,Hurt/Comfort")
        XCTAssertEqual(q["work_search[excluded_tag_names]"], "Major Character Death")
        XCTAssertEqual(q["work_search[rating_ids]"], "13")
        XCTAssertEqual(q["work_search[complete]"], "T")
        XCTAssertEqual(q["work_search[language_id]"], "en")
        XCTAssertEqual(q["work_search[sort_column]"], "kudos_count")
        XCTAssertEqual(q["page"], "3")
    }

    func testDefaultsLeaveFiltersOut() {
        let q = items(SearchProfile().query().url)
        XCTAssertEqual(q["work_search[query]"], "")
        XCTAssertNil(q["work_search[rating_ids]"])
        XCTAssertNil(q["work_search[complete]"])
        XCTAssertNil(q["work_search[other_tag_names]"])
        XCTAssertNil(q["work_search[excluded_tag_names]"])
        XCTAssertNil(q["page"])
        XCTAssertEqual(q["work_search[sort_column]"], "revised_at")
    }

    func testBestMatchNeedsWords() {
        var p = SearchProfile()
        p.sort = .relevance
        XCTAssertEqual(p.effectiveSort, .updated)
        p.words = "enemies to lovers"
        XCTAssertEqual(p.effectiveSort, .relevance)
    }

    func testLocalFiltering() {
        var w = WorkBlurb(id: 7, title: "T", authors: ["Writer"])
        w.freeforms = ["Major Character Death"]
        var p = SearchProfile()
        XCTAssertTrue(p.shows(w))
        p.hiddenTags = [TagRef(name: "major character death")]
        XCTAssertFalse(p.shows(w))
        p.hiddenTags = []
        p.hiddenAuthors = ["writer"]
        XCTAssertFalse(p.shows(w))
        p.hiddenAuthors = []
        p.hideOwned = true
        XCTAssertTrue(p.shows(w, owned: [8]))
        XCTAssertFalse(p.shows(w, owned: [7]))
    }

    func testProfileRoundTripsAsJSON() throws {
        var p = SearchProfile()
        p.fandoms = [TagRef(name: "A", canonical: "A!", id: 1)]
        p.sort = .bookmarks
        p.explicitOnly = true
        let back = try JSONDecoder().decode(SearchProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testTagRefSameness() {
        XCTAssertTrue(TagRef(name: "a", id: 1).isSame(as: TagRef(name: "b", id: 1)))
        XCTAssertFalse(TagRef(name: "a", id: 1).isSame(as: TagRef(name: "a", id: 2)))
        XCTAssertTrue(TagRef(name: "Syn", canonical: "Canon").isSame(as: TagRef(name: "canon")))
    }

    func testResultCapNotice() {
        let html = #"<p class="notice">Displaying 100000 results out of 918,234. Please use the filters to narrow your search.</p>"#
        XCTAssertTrue(BlurbExtract.results(in: html, page: 5000).isCapped)
        XCTAssertFalse(BlurbExtract.results(in: "<h3 class=\"heading\">3 Found</h3>", page: 1).isCapped)
    }

    func testTagNameFromWorksPath() {
        XCTAssertEqual(TagExtract.tagName(fromWorksPath: "/tags/Hades%20(Supergiant%20Games%20Video%20Games)/works"),
                       "Hades (Supergiant Games Video Games)")
        XCTAssertEqual(TagExtract.tagName(fromWorksPath: "https://archiveofourown.org/tags/Hurt*s*Comfort/works"), "Hurt/Comfort")
        XCTAssertEqual(TagExtract.tagName(fromWorksPath: "/tags/Dr*d*%20Who%20*a*%20Co*q*/works"), "Dr. Who & Co?")
        XCTAssertNil(TagExtract.tagName(fromWorksPath: "/works"))
        // Round trip through the path builder.
        for name in ["A/B & C.", "What? #1", "Star*Light"] {
            XCTAssertEqual(TagExtract.tagName(fromWorksPath: "/tags/" + AO3WorkQuery.tagPath(name) + "/works"), name)
        }
    }

    func testTagListingNameAndID() {
        let html = #"<h2 class="heading">1 - 20 of 12,345 Works in <a class="tag" href="/tags/Hades%20(Supergiant%20Games%20Video%20Games)">Hades (Supergiant Games Video Games)</a></h2><a class="rss" href="/tags/98765/feed.atom">Subscribe</a>"#
        let listing = TagExtract.listing(html)
        XCTAssertEqual(listing.name, "Hades (Supergiant Games Video Games)")
        XCTAssertEqual(listing.id, 98765)
    }

    func testResolverCachesByAnyName() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("tags.json")
        let data = try JSONEncoder().encode(["hades (video game)": TagRef(name: "Hades (Video Game)", canonical: "Hades (SG)")])
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: file)
        let resolver = TagResolver(file: file)
        let hit = await resolver.cached("HADES (Video Game)")
        XCTAssertEqual(hit?.canonical, "Hades (SG)")
        let miss = await resolver.cached("Hollow Knight")
        XCTAssertNil(miss)
    }
}

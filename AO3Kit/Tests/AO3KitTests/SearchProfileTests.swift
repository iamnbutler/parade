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
        p.freeforms = TagRule(include: [TagRef(name: "Fluff")], exclude: [TagRef(name: "Major Character Death")])
        p.categories = [23: .include, 22: .exclude]
        p.warnings = [18: .exclude]
        p.completion = .complete
        p.hiddenAuthors = ["someone"]

        p.reset(fandomLists: [["A"]])
        XCTAssertEqual(p.fandoms.map(\.name), ["A"])
        XCTAssertEqual(p.words, "")
        XCTAssertEqual(p.freeforms.include, [])
        XCTAssertEqual(p.freeforms.exclude.map(\.name), ["Major Character Death"])
        XCTAssertEqual(p.categories, [22: .exclude])
        XCTAssertEqual(p.warnings, [18: .exclude])
        XCTAssertEqual(p.completion, .any)

        p.clear()
        XCTAssertEqual(p.fandoms, [])
        XCTAssertEqual(p.hiddenAuthors, ["someone"])
        XCTAssertTrue(p.seeded)
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

    func testWarningsAndCategories() {
        var p = SearchProfile()
        p.fandoms = [TagRef(name: "A", id: 1)]
        // Included: any of them. Excluded: none of them, by id.
        p.categories = [23: .include, 116: .include, 22: .exclude]
        p.warnings = [18: .exclude, 19: .exclude]
        XCTAssertEqual(p.queryText,
                       "filter_ids:1 AND (filter_ids:116 OR filter_ids:23) NOT filter_ids:18 NOT filter_ids:19 NOT filter_ids:22")
        p.fandoms = []
        p.categories = [:]
        XCTAssertEqual(p.queryText, "NOT filter_ids:18 NOT filter_ids:19")
        p.warnings = [16: .include]
        XCTAssertEqual(p.queryText, "filter_ids:16")
    }

    func testExcludedTagsByIDOrName() {
        var p = SearchProfile()
        p.excludedFandoms = [TagRef(name: "Big Fandom", id: 7)]
        p.relationships.exclude = [TagRef(name: "Unresolved/Ship")]
        XCTAssertEqual(p.queryText, "NOT filter_ids:7")
        let q = items(p.query().url)
        XCTAssertEqual(q["work_search[excluded_tag_names]"], "Unresolved/Ship")
    }

    func testProfileURL() {
        var p = SearchProfile()
        p.fandoms = [TagRef(name: "A", id: 1), TagRef(name: "B", id: 2)]
        p.title = " Lanterns "
        p.creator = "someone"
        p.relationships.include = [TagRef(name: "x", canonical: "A/B")]
        p.characters.include = [TagRef(name: "C"), TagRef(name: "D")]
        p.freeforms.include = [TagRef(name: "Fluff")]
        p.explicitOnly = true
        p.completion = .inProgress
        p.crossovers = .exclude
        p.singleChapter = true
        p.updatedWithin = .month
        p.sort = .kudos
        p.ascending = true
        let url = p.query(page: 3).url
        XCTAssertTrue(url.absoluteString.hasPrefix("https://archiveofourown.org/works/search?"), url.absoluteString)
        let q = items(url)
        XCTAssertEqual(q["work_search[query]"], "(filter_ids:1 OR filter_ids:2)")
        XCTAssertEqual(q["work_search[title]"], "Lanterns")
        XCTAssertEqual(q["work_search[creators]"], "someone")
        XCTAssertEqual(q["work_search[relationship_names]"], "A/B")
        XCTAssertEqual(q["work_search[character_names]"], "C,D")
        XCTAssertEqual(q["work_search[freeform_names]"], "Fluff")
        XCTAssertEqual(q["work_search[rating_ids]"], "13")
        XCTAssertEqual(q["work_search[complete]"], "F")
        XCTAssertEqual(q["work_search[crossover]"], "F")
        XCTAssertEqual(q["work_search[single_chapter]"], "1")
        XCTAssertEqual(q["work_search[revised_at]"], "< 1 month")
        XCTAssertEqual(q["work_search[language_id]"], "en")
        XCTAssertEqual(q["work_search[sort_column]"], "kudos_count")
        XCTAssertEqual(q["work_search[sort_direction]"], "asc")
        XCTAssertEqual(q["page"], "3")

        p.completion = .complete
        p.crossovers = .only
        let q2 = items(p.query().url)
        XCTAssertEqual(q2["work_search[complete]"], "T")
        XCTAssertEqual(q2["work_search[crossover]"], "T")
    }

    func testDefaultsLeaveFiltersOut() {
        let q = items(SearchProfile().query().url)
        XCTAssertEqual(q["work_search[query]"], "")
        for field in ["rating_ids", "complete", "crossover", "single_chapter", "revised_at", "title", "creators",
                      "relationship_names", "character_names", "freeform_names", "excluded_tag_names"] {
            XCTAssertNil(q["work_search[\(field)]"], field)
        }
        XCTAssertNil(q["page"])
        XCTAssertEqual(q["work_search[sort_column]"], "revised_at")
        XCTAssertEqual(q["work_search[sort_direction]"], "desc")
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
        w.categories = ["M/M"]
        var p = SearchProfile()
        XCTAssertTrue(p.shows(w))
        p.freeforms.exclude = [TagRef(name: "major character death")]
        XCTAssertFalse(p.shows(w))
        p.freeforms.exclude = []
        p.categories = [23: .exclude]
        XCTAssertFalse(p.shows(w))
        p.categories = [:]
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
        p.warnings = [18: .exclude]
        p.categories = [23: .include]
        p.characters = TagRule(include: [TagRef(name: "C")], exclude: [TagRef(name: "D")])
        p.updatedWithin = .year
        let back = try JSONDecoder().decode(SearchProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
    }

    func testReadsTheFirstVersionsProfile() throws {
        let old = #"{"fandoms":[{"name":"A","id":1}],"words":"x","includeTags":[{"name":"Fluff"}],"hiddenTags":[{"name":"Angst"}],"hiddenAuthors":["w"],"explicitOnly":true,"completeOnly":true,"hideOwned":false,"sort":"kudos_count","seeded":true}"#
        let p = try JSONDecoder().decode(SearchProfile.self, from: Data(old.utf8))
        XCTAssertEqual(p.fandoms.first?.id, 1)
        XCTAssertEqual(p.freeforms.include.map(\.name), ["Fluff"])
        XCTAssertEqual(p.freeforms.exclude.map(\.name), ["Angst"])
        XCTAssertEqual(p.completion, .complete)
        XCTAssertEqual(p.sort, .kudos)
        XCTAssertTrue(p.explicitOnly)
        XCTAssertTrue(p.seeded)
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

import XCTest
@testable import AO3Kit

final class AO3SearchTests: XCTestCase {
    func testParsesSearchResultBlurbs() {
        let results = BlurbExtract.results(in: Self.searchPage, page: 1)
        XCTAssertEqual(results.total, 56975)
        XCTAssertTrue(results.hasNextPage)
        XCTAssertEqual(results.works.map(\.id), [76008221, 72894606])

        let first = results.works[0]
        XCTAssertEqual(first.title, "please leave a message")
        XCTAssertEqual(first.authors, ["subcorax"])
        XCTAssertEqual(first.fandoms, ["Heated Rivalry (TV)", "Game Changers Series - Rachel Reid"])
        XCTAssertEqual(first.rating, "Teen And Up Audiences")
        XCTAssertEqual(first.warnings, ["No Archive Warnings Apply"])
        XCTAssertEqual(first.categories, ["M/M"])
        XCTAssertEqual(first.isComplete, true)
        XCTAssertEqual(first.date, "19 Dec 2025")
        XCTAssertEqual(first.relationships.first, "Shane Hollander/Ilya Rozanov")
        XCTAssertEqual(first.characters.last, "Background & Cameo Characters")
        XCTAssertEqual(first.freeforms.first, "Texting")
        XCTAssertEqual(first.series, ["Part 1 of You Have (81) Unread Messages"])
        XCTAssertEqual(first.words, 2407)
        XCTAssertEqual(first.chapters, "1/1")
        XCTAssertEqual(first.kudos, 120019)
        XCTAssertEqual(first.hits, 1065853)
        XCTAssertEqual(first.language, "English")
        XCTAssertTrue(first.summary?.hasPrefix("Sarah\nDoes anyone have the number") == true, first.summary ?? "")
        XCTAssertTrue(first.summary?.hasSuffix("Or: Ilya Rozanov is, apparently, one of the girls.") == true)

        XCTAssertEqual(results.works[1].summary,
                       "A video of Shane sucking Ilya’s dick is leaked. Over the next twenty-four hours, Ilya goes on an odyssey.")
        XCTAssertTrue(results.works[1].series.isEmpty)
    }

    func testLastPageHasNoNext() {
        let html = #"<ol class="pagination actions"><li class="previous" title="previous"><a rel="prev" href="/x?page=1">← Previous</a></li> <li class="next" title="next"><span class="disabled">Next →</span></li></ol>"#
        XCTAssertFalse(BlurbExtract.results(in: html, page: 2).hasNextPage)
    }

    func testTagListingTotal() {
        let html = #"<h2 class="heading">\n 1 - 20 of 5,431 Works in <a class="tag" href="/tags/Heated%20Rivalry%20(TV)">Heated Rivalry (TV)</a>\n</h2>"#
        XCTAssertEqual(BlurbExtract.results(in: html, page: 1).total, 5431)
    }

    func testTitleAuthorQueryAndLooseMatch() {
        let url = AO3WorkQuery(source: .titleAuthor(title: "Text Me", author: "taliiaa")).url.absoluteString
        XCTAssertTrue(url.contains("work_search%5Btitle%5D=Text%20Me"), url)
        XCTAssertTrue(url.contains("work_search%5Bcreators%5D=taliiaa"), url)

        var w = WorkBlurb(id: 1, title: "Love: A Retrospective", authors: ["evilphrog", "Aruhu_Baughs"])
        XCTAssertTrue(w.matches(title: "Love- A Retrospective", author: "evilphrog & Aruhu_Baughs"))
        XCTAssertTrue(w.matches(title: "love a retrospective", author: "Aruhu_Baughs"))
        XCTAssertFalse(w.matches(title: "Love: A Retrospective, Part 2", author: "evilphrog"))
        XCTAssertFalse(w.matches(title: "Love: A Retrospective", author: "someone else"))
        w.title = ""
        XCTAssertFalse(w.matches(title: "", author: ""))
    }

    func testQueryURLs() {
        let search = AO3WorkQuery(source: .search("heated rivalry"), sort: .kudos, completeOnly: true, page: 2).url.absoluteString
        XCTAssertTrue(search.hasPrefix("https://archiveofourown.org/works/search?"))
        XCTAssertTrue(search.contains("work_search%5Bquery%5D=heated%20rivalry"), search)
        XCTAssertTrue(search.contains("work_search%5Bsort_column%5D=kudos_count"))
        XCTAssertTrue(search.contains("work_search%5Bcomplete%5D=T"))
        XCTAssertTrue(search.contains("page=2"))

        let tag = AO3WorkQuery(source: .tag("Shane Hollander/Ilya Rozanov")).url.absoluteString
        XCTAssertEqual(tag, "https://archiveofourown.org/tags/Shane%20Hollander*s*Ilya%20Rozanov/works?view_adult=true")
        XCTAssertEqual(AO3WorkQuery.tagPath("Dr. Who & Co?"), "Dr*d*%20Who%20*a*%20Co*q*")
    }

    /// Two works from a real AO3 search page, its "Found" header and pagination.
    static let searchPage = #"""
<h3 class="heading">56,975 Found  <a class="help symbol question modal" aria-label="Work search results help" href="/help/work-search-results-help.html"><span class="symbol question"><span>?</span></span></a></h3>
<ol class="work index group">
<li id="work_76008221" class="work blurb group work-76008221 user-455291" role="article">
    <!--title, author, fandom-->
  <div class="header module">
    <!-- updated_at=1769620498 -->
    <h4 class="heading">
      <a href="/works/76008221">please leave a message</a>
      by

      <!-- do not cache -->
      <a rel="author" href="/users/subcorax/pseuds/subcorax">subcorax</a>



      
      
    </h4>

    <h5 class="fandoms heading">
      <span class="landmark">Fandoms:</span>
      <a class="tag" href="/tags/Heated%20Rivalry%20(TV)/works">Heated Rivalry (TV)</a>, <a class="tag" href="/tags/Game%20Changers%20Series%20-%20Rachel%20Reid/works">Game Changers Series - Rachel Reid</a>
      &nbsp;
    </h5>

    <!--required tags-->
    <ul class="required-tags">
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="rating-teen rating" title="Teen And Up Audiences"><span class="text">Teen And Up Audiences</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="warning-no warnings" title="No Archive Warnings Apply"><span class="text">No Archive Warnings Apply</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="category-slash category" title="M/M"><span class="text">M/M</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="complete-yes iswip" title="Complete Work"><span class="text">Complete Work</span></span></a></li>
</ul>
    <p class="datetime">19 Dec 2025</p>
  </div>

  <!--warnings again, cast, freeform tags-->
  <h6 class="landmark heading">Tags</h6>
  <ul class="tags commas">
    <li class='warnings'><strong><a class="tag" href="/tags/No%20Archive%20Warnings%20Apply/works">No Archive Warnings Apply</a></strong></li><li class='relationships'><a class="tag" href="/tags/Shane%20Hollander*s*Ilya%20Rozanov/works">Shane Hollander/Ilya Rozanov</a></li> <li class='relationships'><a class="tag" href="/tags/Minor%20or%20Background%20Relationship(s)/works">Minor or Background Relationship(s)</a></li><li class='characters'><a class="tag" href="/tags/Ilya%20Rozanov/works">Ilya Rozanov</a></li> <li class='characters'><a class="tag" href="/tags/Jackie%20Pike/works">Jackie Pike</a></li> <li class='characters'><a class="tag" href="/tags/Original%20Characters/works">Original Characters</a></li> <li class='characters'><a class="tag" href="/tags/Background%20*a*%20Cameo%20Characters/works">Background &amp; Cameo Characters</a></li><li class='freeforms'><a class="tag" href="/tags/Texting/works">Texting</a></li> <li class='freeforms'><a class="tag" href="/tags/Crack/works">Crack</a></li> <li class='freeforms'><a class="tag" href="/tags/Misunderstandings/works">Misunderstandings</a></li> <li class='freeforms'><a class="tag" href="/tags/Mistaken%20Identity/works">Mistaken Identity</a></li> <li class='freeforms'><a class="tag" href="/tags/Identity%20Reveal/works">Identity Reveal</a></li> <li class='freeforms'><a class="tag" href="/tags/Canon-Typical%20Violence/works">Canon-Typical Violence</a></li> <li class='freeforms'><a class="tag" href="/tags/(non-graphic%20reference%20to%20hockey%20injury)/works">(non-graphic reference to hockey injury)</a></li> <li class='freeforms'><a class="tag" href="/tags/Alternate%20Universe%20-%20Canon%20Divergence/works">Alternate Universe - Canon Divergence</a></li> <li class='freeforms'><a class="tag" href="/tags/Not%20Canon%20Compliant/works">Not Canon Compliant</a></li> <li class='freeforms'><a class="tag" href="/tags/WAG%20Ilya%20Rozanov/works">WAG Ilya Rozanov</a></li>
  </ul>

  <!--summary-->
    <h6 class="landmark heading">Summary</h6>
    <blockquote class="userstuff summary">
      <blockquote><p><b>Sarah</b><br>
Does anyone have the number for Shane's girl from Boston? I feel bad that they've been seeing each other for this long and we've never added her here.</p>
<p><b>Jackie</b><br>
Oh good point! Let me ask Hayden.</p>
<p><i>Jackie has added Lily to the conversation</i></p>
<p><b>Lily</b><br>
what<br>
what is this</p></blockquote><p>Or: Ilya Rozanov is, apparently, one of the girls.</p>
    </blockquote>

    <h6 class="landmark heading">Series</h6>
    <ul class="series">
        <li>
          Part <strong>1</strong> of <a href="/series/5541386">You Have (81) Unread Messages</a>
        </li>
    </ul>

  <!--stats-->

  <dl class="stats">
      <dt class="language">Language:</dt>
      <dd class="language" lang="en">English</dd>
    <dt class="words">Words:</dt>
    <dd class="words">2,407</dd>
    <dt class="chapters">Chapters:</dt>
    <dd class="chapters">1/1</dd>



    <dt class="comments">Comments:</dt>
    <dd class="comments"><a href="/works/76008221?show_comments=true#comments">3,601</a></dd>

    <dt class="kudos">Kudos:</dt>
    <dd class="kudos"><a href="/works/76008221#kudos">120,019</a></dd>

    <dt class="bookmarks">Bookmarks:</dt>
    <dd class="bookmarks"><a href="/works/76008221/bookmarks">22,289</a></dd>

  <dt class="hits">Hits:</dt>
  <dd class="hits">1,065,853</dd>

  </dl>


</li>

        <li id="work_72894606" class="work blurb group work-72894606 user-11492563" role="article">
    <!--title, author, fandom-->
  <div class="header module">
    <!-- updated_at=1767417151 -->
    <h4 class="heading">
      <a href="/works/72894606">and i spit out the seeds</a>
      by

      <!-- do not cache -->
      <a rel="author" href="/users/linearity/pseuds/linearity">linearity</a>



      
      
    </h4>

    <h5 class="fandoms heading">
      <span class="landmark">Fandoms:</span>
      <a class="tag" href="/tags/Game%20Changers%20Series%20-%20Rachel%20Reid/works">Game Changers Series - Rachel Reid</a>, <a class="tag" href="/tags/Heated%20Rivalry%20(TV)/works">Heated Rivalry (TV)</a>
      &nbsp;
    </h5>

    <!--required tags-->
    <ul class="required-tags">
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="rating-explicit rating" title="Explicit"><span class="text">Explicit</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="warning-no warnings" title="No Archive Warnings Apply"><span class="text">No Archive Warnings Apply</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="category-slash category" title="M/M"><span class="text">M/M</span></span></a></li>
<li><a class="help symbol question modal" title="Symbols key" href="/help/symbols_key"><span class="complete-yes iswip" title="Complete Work"><span class="text">Complete Work</span></span></a></li>
</ul>
    <p class="datetime">30 Oct 2025</p>
  </div>

  <!--warnings again, cast, freeform tags-->
  <h6 class="landmark heading">Tags</h6>
  <ul class="tags commas">
    <li class='warnings'><strong><a class="tag" href="/tags/No%20Archive%20Warnings%20Apply/works">No Archive Warnings Apply</a></strong></li><li class='relationships'><a class="tag" href="/tags/Shane%20Hollander*s*Ilya%20Rozanov/works">Shane Hollander/Ilya Rozanov</a></li><li class='characters'><a class="tag" href="/tags/Ilya%20Rozanov/works">Ilya Rozanov</a></li> <li class='characters'><a class="tag" href="/tags/Shane%20Hollander/works">Shane Hollander</a></li> <li class='characters'><a class="tag" href="/tags/Hayden%20Pike/works">Hayden Pike</a></li><li class='freeforms'><a class="tag" href="/tags/Sex%20Tapes/works">Sex Tapes</a></li> <li class='freeforms'><a class="tag" href="/tags/Coming%20Out/works">Coming Out</a></li> <li class='freeforms'><a class="tag" href="/tags/Alternate%20Universe%20-%20Canon%20Divergence/works">Alternate Universe - Canon Divergence</a></li>
  </ul>

  <!--summary-->
    <h6 class="landmark heading">Summary</h6>
    <blockquote class="userstuff summary">
      <p>A video of Shane sucking Ilya’s dick is leaked. Over the next twenty-four hours, Ilya goes on an odyssey.</p>
    </blockquote>


  <!--stats-->

  <dl class="stats">
      <dt class="language">Language:</dt>
      <dd class="language" lang="en">English</dd>
    <dt class="words">Words:</dt>
    <dd class="words">24,200</dd>
    <dt class="chapters">Chapters:</dt>
    <dd class="chapters">1/1</dd>



    <dt class="comments">Comments:</dt>
    <dd class="comments"><a href="/works/72894606?show_comments=true#comments">1,952</a></dd>

    <dt class="kudos">Kudos:</dt>
    <dd class="kudos"><a href="/works/72894606#kudos">65,937</a></dd>

    <dt class="bookmarks">Bookmarks:</dt>
    <dd class="bookmarks"><a href="/works/72894606/bookmarks">15,687</a></dd>

  <dt class="hits">Hits:</dt>
  <dd class="hits">768,429</dd>

  </dl>


</li>

        </ol>
<ol role="navigation" aria-label="Pagination" class="pagination actions" title="pagination"><li class="previous" title="previous"><span class="disabled">&#8592; Previous</span></li> <li><span class="current">1</span></li> <li><a rel="next" href="/works/search?page=2&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">2</a></li> <li><a href="/works/search?page=3&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">3</a></li> <li><a href="/works/search?page=4&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">4</a></li> <li><a href="/works/search?page=5&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">5</a></li> <li><a href="/works/search?page=6&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">6</a></li> <li><a href="/works/search?page=7&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">7</a></li> <li><a href="/works/search?page=8&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">8</a></li> <li><a href="/works/search?page=9&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">9</a></li> <li class="gap">…</li> <li><a href="/works/search?page=2848&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">2848</a></li> <li><a href="/works/search?page=2849&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">2849</a></li> <li class="next" title="next"><a rel="next" href="/works/search?page=2&amp;view_adult=true&amp;work_search%5Bquery%5D=heated+rivalry&amp;work_search%5Bsort_column%5D=kudos_count">Next &#8594;</a></li></ol>
"""#
}

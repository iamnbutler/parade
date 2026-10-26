# AO3 Search — design

Finding new fics on AO3 from inside Parade. Not a port of AO3's search form:
a small set of filters that stay put, seeded from the library you already
have.

Status: phases 0–3 are built, on both platforms. Facts about AO3 below
come from the otwarchive source and from other clients' code (see
*Sources*). The ones the design depends on were checked against the live
site on 2026-10-25 and are marked **verified**.

---

## 1. What's wrong with AO3's search, and what we do instead

| AO3 | Parade |
|---|---|
| Two pages of fields: the search form, plus a filter sidebar with its own rules | One form, set up on its own page. The results page shows a short summary of it. |
| Several fandoms means fics in **all** of them (crossovers only) | Several fandoms means fics in **any** of them. That's how people read. |
| Several categories or warnings means **all** of them | Include means **any** of them: "F/F or Multi". |
| The search form can't exclude anything | Every warning, category, fandom, relationship, character and tag can be included or excluded. |
| Every search starts empty | Your search is sticky. It's still set up the way you left it, on every device. |
| A first search starts from nothing | A first search starts from the fandoms in your library. |
| Ratings are five checkboxes | One switch: **Explicit only**. Off means every rating. |
| You can't tell what you already have | Results show **In library** / **To Read**, and there's an option to hide fics you already have. |
| Tags are typed exactly or they don't match | You pick tags by name, and Parade resolves them to AO3's canonical tag. |

The form covers AO3's search options:
- words (any field), title, creator
- fandoms, with crossovers to include, exclude or show only
- Explicit only
- each archive warning and category: any, include or exclude
- relationships, characters and additional tags, each included or excluded
- complete or in progress, single chapter, date updated
- every sort AO3 offers, in either direction

Parade adds excluded creators and "hide fics I already have".

**Cut on purpose:**
- the Work Stats fields (hits, kudos, comments, bookmarks)
- word count
- language (English always)
- ratings other than Explicit

Sorting by kudos, hits, bookmarks or comments stays: that's a sort, not a filter.

## 2. The search profile

One value, saved and synced, that every search is built from:
`SearchProfile` in `AO3Kit/Sources/AO3Kit/SearchProfile.swift`. It holds:
- words, title and creator
- fandoms and excluded fandoms, and crossovers
- Explicit only
- warnings and categories, as `[AO3 tag id: include | exclude]`
- a `TagRule` (include / exclude lists) for each of relationships,
  characters and additional tags
- excluded creators
- completion, single chapter and updated within
- sort and direction
- hide-owned and seeded

Every tag is a `TagRef`: the name as picked, plus AO3's canonical name and
id once it's been looked up. Profiles saved by the first version, with its
`includeTags` / `hiddenTags` / `completeOnly`, still decode.

### Where it lives

It's stored as `Search.json` in the library folder, beside `Favorites.txt`
and `Collections.txt`. That way it syncs through iCloud and can be edited
by hand. iCloud placeholder (`.Search.json.icloud`) handling works the same
way as for Favorites. The last results page is not persisted: it's cheap
to fetch again and goes stale.

### Seeding (first open only)

When `seeded == false`:
1. `fandoms` becomes every fandom across `detailsIndex`, most fics first.
   Fandoms that appear only as a crossover partner are included too.
2. `sort` is `.updated`, so the first screen shows what's new in your
   fandoms.
3. `seeded` is set to `true`.

After that the profile changes only when the person changes it. New
fandoms that show up in the library later are **not** added
automatically, because that would undo deliberate removals. Instead, the
fandom editor offers them: "In your library, not in your search:
*Fandom X* (4 fics) +".

### Clearing

- **Reset to my fandoms** re-runs seeding.
- **Clear all** empties the fandoms, words and include tags.
- Hidden tags and authors survive both. They're a standing preference, and
  each one has its own unhide action.

## 3. Turning the profile into an AO3 request

### Facts this depends on

From `WorksController#work_search_params`, `WorkQuery` and `TaggableQuery`:
- `*_names` fields (`fandom_names`, `other_tag_names` and so on) are split
  on commas and **ANDed**. AO3's form can't express "any of these
  fandoms".
- `work_search[query]` is an Elasticsearch `query_string` with
  `default_operator: AND`, and it can search indexed fields directly. That
  includes `filter_ids`, which holds a work's tags plus their canonical
  and meta tags. So `filter_ids:(A OR B)` gives an OR across fandoms,
  synonyms included. **Verified:** `filter_ids:110676730` finds 8,576
  works, the same count as the canonical Hades tag's own listing. A
  six-fandom OR returned works from each of the six.
- **Verified:** searching a synonym by name finds almost nothing.
  `fandom_names=Hades (Video Game)` found 3 works; its canonical tag has
  8,576.
- `rating_ids`: Explicit is `13`.
- `language_id`: `en`.
- `complete`: `T`.
- `excluded_tag_names`: comma-separated, matched by name.
- Logged out, restricted works never appear. That's fine for v1, which is
  public works only.

### The request

```
/works/search?
  work_search[query]=(<words>) AND filter_ids:(<fandom ids, OR'd>)
                     AND filter_ids:(<included warnings, OR'd>) AND filter_ids:(<included categories, OR'd>)
                     NOT filter_ids:<each excluded warning, category or tag with an id>
  work_search[title], work_search[creators]
  work_search[relationship_names|character_names|freeform_names]=<included, canonical, comma-separated>
  work_search[excluded_tag_names]=<excluded tags AO3 has no id for>
  work_search[rating_ids]=13              # Explicit only
  work_search[complete]=T|F               # complete / in progress
  work_search[crossover]=F|T              # exclude / only
  work_search[single_chapter]=1
  work_search[revised_at]=< 1 week|month|6 months|year
  work_search[sort_column]=…  work_search[sort_direction]=asc|desc
  work_search[language_id]=en
  page=N
```

**Verified live:** warning and category IDs come from AO3's own form:
- warnings: 14, 16, 17, 18, 19 and 20
- categories: 116 F/F, 22 F/M, 21 Gen, 23 M/M, 2246 Multi, 24 Other

Counts for the Hades fandom (8,576 works):
- M/M or F/F finds 5,646. That's M/M's 5,098 plus F/F's 651, less the 103 tagged both.
- Excluding Major Character Death finds 8,214, which is 8,576 less its 362. `NOT filter_ids:18` and `excluded_tag_names` give the same count.

- Every search goes through `/works/search`, so there's only one request
  shape to get right.
- **Best match** (`_score`) only makes sense when there are words; without
  them it falls back to Updated, and the form says so.
- **No fandoms** searches all of AO3.

### Resolving tags (name → canonical name + id)

Fandom names come from EPUBs. An EPUB has whatever the work was tagged
with, which may be a synonym ("BNHA" rather than "僕のヒーローアカデミア | Boku no
Hero Academia | My Hero Academia"). Searching by a synonym's name only
matches works tagged with that exact synonym. Searching by its id through
`filter_ids` doesn't have that problem, so resolution matters.

`TagResolver` lives in AO3Kit and is a persistent cache keyed by
name → `TagRef`. It's never refetched once resolved, because tag ids don't
change. Sources, cheapest first:

1. **`/works?tag_id=<name>`.** **Verified:** this 302s to the canonical
   tag's listing, `/tags/<canonical>/works`. That page names the tag in
   its heading ("1 - 20 of 8,576 Works in <a>…</a>") and links its RSS
   feed by id (`/tags/110676730/feed.atom`). One request per name, ever,
   gives both the canonical name and the id.
2. **If there's no id** (an unwrangled tag, or no feed link), the name is
   searched as text: `tag:"Name"`. A tag AO3 doesn't know (404) is cached
   as itself, so it isn't asked about again.

A search resolves its own unresolved tags first, at `.user` priority,
showing "Looking up 3 tags on AO3…". Once a search has loaded, library
fandoms the search leaves out are resolved quietly at `.background`
priority. That way a synonym of a searched fandom ("MDZS") stops being
offered under "In your library, not in your search".

Resolved tags are cached in `Application Support/Parade/ao3-tags.json`.
A test library uses `ao3-tags-testlibrary.json` instead, as it does for
the database.

`/autocomplete/*` is disallowed in AO3's robots.txt, and no client we
looked at uses it. Tag suggestions therefore come from the library's own
vocabulary (`searchVocabulary` already exists), plus "use *what you
typed*". What you typed resolves on submit like any other name.

## 4. Fetching: pages, caching, being polite

All of this goes through the existing `AO3Scheduler`, which provides:
- one request at a time
- 3 s spacing (±20%)
- `.user` before `.background`
- Retry-After honoured on 429/503/525
- exponential back-off with a 15-minute cap
- a circuit breaker

Search needs no new rate-limit machinery, only discipline on top of it.

**AO3's limits.** otwarchive's Rack::Attack config throttles 300 requests
per 5 minutes per IP, plus a separate limit on search backends, and sends
Retry-After on 429. Production may be stricter: ao3_api notes about 12 a
minute. At 3 s spacing, Parade tops out at about 20 a minute. On 429 the
scheduler already backs off, so this is fine, but it's the reason for
the rules below.

| Client | Gap between requests | On a 429 |
|---|---|---|
| FanFicFare | 4 s, randomized 0.5–1.5× | retries with back-off |
| ao3_api | 12 per minute | — |
| ao3downloader | — | waits Retry-After, or 300 s without it |
| Parade | 3 s (±20%) | already in line with these |

**Pagination rules:**
- 20 works a page.
- **Infinite scroll, one page at a time.** Page N+1 is fetched only when
  the list scrolls within about 5 rows of the end. Never more than one
  page ahead, and never a background crawl of all pages.
- The last page is the one with no `li.next` link; `hasNextPage` already
  parses this. AO3 caps results at 100,000 (5,000 pages), and past that it
  silently repeats the last page. The paging stops there and shows "AO3
  shows at most 100,000 — narrow the search".
- The total comes from the "N Found" heading, which shows the uncapped
  count. `BlurbExtract` parses it already.
- Duplicates are removed by work id across pages. Results shift while you
  scroll on an Updated sort.

**Not wasting requests:**
- Changing filters doesn't search on every tap. Edits in the filter sheet
  apply when the sheet closes. Typed words apply on Return, or after 1.5 s
  idle, the same rule as the library search.
- A changed profile cancels the in-flight fetch. Cancelling the task takes
  it out of the scheduler queue; that's already supported.
- An in-memory page cache keyed by the request URL lasts 10 minutes. Going
  into a work's preview and back, or switching tabs, costs nothing.
- A profile change resets to page 1. The old pages stay cached, so undoing
  the change is free.

**Showing the wait.** The scheduler's `stateUpdates()` drives a line under
the filter bar:
- `.waiting`: "AO3 asked us to slow down — continuing at 8:42"
- `.paused`: "Paused until 8:55 — AO3 is busy"

A results page never shows a bare spinner for minutes.

**Cloudflare.** We see 525/503 from Cloudflare, sometimes for long
stretches; it happened during this research. These are already treated as
rate limits. Another client, CO3, falls back to a WebView when it gets a
`_cf_chl_opt` challenge page. That's out of scope for v1. If challenges
show up in practice, detect the page and say "AO3 is checking browsers —
try again shortly" rather than retrying blindly.

## 5. Screens

- **Results** (`SearchView`). On iPhone this is the Search tab; on Mac it's
  the sidebar section.
  - A card at the top sums up the search in a few plain lines ("Harry
    Potter · no crossovers", "F/F or Multi · no Major Character Death",
    "Complete · updated this year", "Sorted by kudos"), with **Edit
    Search** under them.
  - Below the card, results page in as you scroll.
- **The form** (`SearchForm`) opens as a sheet and edits a copy of the
  search. Nothing is asked of AO3 until **Search**; **Cancel** drops the
  edits. Its sections, in order:
  - Words
  - Fandoms, with suggestions from the library
  - Crossovers
  - Rating
  - Archive warnings and Categories: each row has Any / Include / Exclude
  - Relationships, Characters, Additional tags: type to add, then
    Include or Exclude
  - The work
  - Order
  - Your library
  - Start over / Clear
- **The preview** (`WorkPreview`). Every tag on a result can be included
  in or excluded from the search, by its kind; this applies at once.
- **Debug:** `PARADE_SCREEN=search-form[@categories|@tags|@end]` opens the
  form alone, scrolled to a section. It's for simulator screenshots, which
  can't tap.

## 6. Code layout

**AO3Kit (tested, no UI):**
- `AO3WorkQuery.Source.profile`: builds the URL.
- `SearchProfile` and `TagRef`, with Codable.
- `TagResolver`:
  - parses the tag page (canonical name, id from the feed link,
    synonym-of)
  - caches into a JSON file in Application Support
- `BlurbExtract` additions:
  - `isMaxResults` (the 100k notice)
  - `bookmarks`, `comments` (sorting only, never shown as filters)
  - Cloudflare challenge detection → `AO3Error.challenged`

**App:**
- `AppModel+Search.swift`, extending `AppModel` like the other model
  pieces:
  - profile load, save and seed
  - the results pager (pages, dedupe, cancellation, 10-minute cache)
- `SearchView` (iOS tab and Mac section)
- `SearchFilterBar`
- `FandomEditor` / `TagEditor`
- `WorkPreview`
- `BlurbRow`

**Tests:**
- AO3Kit:
  - URL building for every profile shape
  - fixture HTML: results, last page, 100k cap, tag page, synonym tag
    page, Cloudflare challenge
  - TagResolver caching
  - seeding from a sample `detailsIndex`
- The scheduler's back-off is already covered by `AO3SchedulerTests`.
- UITest: the profile survives relaunch, and the chips reflect it.

## 7. Phases

0. **Verify.** Done 2026-10-25, through intermittent Cloudflare 525s.
   These were the questions:
   - Does `filter_ids:(…OR…)` give the union? Compare its count with each
     fandom's count alone.
   - Does a synonym's `/tags/<name>/works` redirect to the canonical tag?
   - Does every canonical fandom page carry `/tags/<id>/feed.atom`?
   - Is the page size 20?
   - Save fixtures as we go.
1. **AO3Kit:** profile, URL builder, TagResolver, parser additions, tests.
2. **iOS Search tab:**
   - filter bar
   - fandom editor
   - results with paging
   - Save to To Read
   - sticky `Search.json`
3. **Preview, hiding, tag actions, owned badges.** Mac sidebar section.
4. **Polish:** the scheduler-state line and the "not in your search"
   suggestion are done. Still to do:
   - Cloudflare challenge messaging (`_cf_chl_opt` detection)
   - "Search only this" on a tag

## 8. Open questions

- **Should hidden tags also hide fics in the library?** Probably not:
  hidden is about discovery.
- **Per-fandom saved searches**, e.g. "Hades, Explicit, Complete" as a
  named preset? The single sticky profile covers most of it. Add presets
  only if switching back and forth turns out to be common.
- **The robots.txt grey area.** It disallows `/works/search?` and
  `/works?` for crawlers. Parade is a person's own client, fetching one
  page per scroll, with an honest User-Agent and contact address. AO3's
  ToS FAQ allows scraping that isn't spam, AI training or rehosting. We
  keep it that way: no background crawling of search results, ever.

## Sources

- otwarchive:
  - `app/controllers/works_controller.rb` (`work_search_params`)
  - `app/models/search/work_query.rb`, `taggable_query.rb`,
    `work_search_form.rb`
  - `app/models/concerns/filterable.rb`
  - `config/initializers/rack_attack.rb`
  - `config/config.yml` (`MAX_SEARCH_RESULTS`, `RATE_LIMIT_*`)
- ao3_api, `AO3/search.py` and `AO3/requester.py`: rating ids, 12/min.
- FanFicFare `defaults.ini`: `slow_down_sleep_time:4`.
- ao3downloader `repo.py`: Retry-After, else 300 s.
- CO3 `web/requestManager.js`: Cloudflare detection and WebView
  fallback.
- AO3 Savior, AO3 Auto Filters userscripts: blacklists, sticky filters.

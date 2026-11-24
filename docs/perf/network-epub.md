# Performance: networking and EPUB processing (AO3Kit)

Audit of `AO3Kit` (requests to AO3 and its fallbacks, parsing AO3 pages,
building and reading EPUBs) and the update-check flow in
`Shared/AppModel.swift`. Storage/file writes and SwiftUI rendering are
covered by separate audits.

**Summary.** Parade already makes few requests. The update check is a
batched search, search pages and tag lookups are cached, and every request
goes through one polite scheduler. The waste is in a few flows that repeat
a request they don't need, and in CPU work: parsing redid whole-string
passes and recompiled regular expressions over and over. The CPU fixes are
in this lane (opening a long fic is 5× faster). The request fixes that
change what gets saved are left as recommendations.

## How this was measured

- `AO3Kit/Tests/AO3KitTests/PerfBenchmarks.swift`: timings on made-up works
  with fic-like text (curly quotes, entities, italics), at 10, 40 and 120
  chapters of 60 paragraphs each (127 KB, 504 KB and 1.5 MB of HTML), plus
  the fixture library from `scripts/make-fixtures.py`. A counting
  `URLProtocol` (`CountingAO3`) records the requests each flow makes.
  These tests are skipped unless `PARADE_BENCH=1` is set:

  ```sh
  cd AO3Kit
  PARADE_BENCH=1 PARADE_FIXTURES=/path/to/fixtures \
    swift test -c release -Xswiftc -enable-testing --filter PerfBenchmarks
  ```

- Hot spots were found with `sample` on a release test build.
- Each fix was checked for unchanged output: the reader's blocks for 4,000
  fuzzed XHTML documents, `EPUBBookParser` and `EPUBDetailsParser` on the
  10 fixture EPUBs, a search page, entity decoding and the export parser
  were dumped on `main` and on this lane, and the two dumps were
  byte-identical.
- Live AO3 requests: two `HEAD` requests (a work page and a download), to see
  whether AO3 sends cache validators. Both got **429** with
  `Cache-Control: no-store` and no `Retry-After`, so I stopped there.
- All timings are best of 3–5 runs, release build, on an M-series Mac.
  iPhones will be slower, but the ratios hold.

## Findings, ranked by impact

| # | Finding | Where | Status |
|---|---------|-------|--------|
| 1 | Opening a long fic in the reader: ~9 ms of CPU per chapter | `EPUBBook.swift` | **Fixed**: 1117 → 218 ms for 120 chapters |
| 2 | Updating a fic that hasn't changed downloads it again, backs up the old copy and rewrites it in iCloud | `AppModel.swift:1829` → `save` | Recommendation |
| 3 | While AO3's EPUB downloads are off, every save first asks for the EPUB and gets a 404 | `AO3Client.swift:94` | **Fixed**: 3 → 2 requests per save |
| 4 | `WorkDetails.latestDate` built a `DateFormatter` on every call, on the main actor | `EPUBDetails.swift:64` | **Fixed**: 62 µs → 0.2 µs |
| 5 | Regular expressions were compiled again on every call (details index, search pages, entity decoding) | `HTMLExtract.swift:76`, `AO3Search.swift`, `EPUBDetails.swift` | **Fixed**: details 0.40 → 0.16 ms per EPUB; search page 28 → 18 ms |
| 6 | Building an EPUB from AO3's HTML download | `AO3SaverClient.swift`, `WorkPage.swift` | **Partly fixed**: 609 → 271 ms for 120 chapters |
| 7 | Saving from search, or linking, fetches the work page the search result already described | `AppModel.swift:1411`, `:1566` | Recommendation |
| 8 | Wayback fallback fetches the single-chapter page before the full-work page | `WaybackClient.swift:50`, `AppModel.swift:1453` | Recommendation |
| 9 | Series: only the first page of works is read; works already saved are downloaded again | `HTMLExtract.swift:59`, `AppModel.swift:1359` | Recommendation (also a correctness bug) |
| 10 | The reader holds every image of a book in memory | `EPUBBook.swift:210` | Recommendation |
| — | Scheduler, update check, search paging, tag resolution | | Fine as they are; see the end |

### 1. Reading an EPUB: whole-chapter copies on every paragraph (fixed)

`EPUBBookParser.parse` runs every time a fic is opened in the reader. It runs
off the main thread (`ReaderView.swift:127`, `Task.detached`), but the person
is waiting on it: a 120-chapter fic took **1.1 s** to show, and 5 ms of that
work went into each 12 KB chapter. The XML parser itself takes 0.08 ms per
chapter. Everything else was Parade's own code:

- `xmlSafe` (`EPUBBook.swift:377`) made one `replacingOccurrences` pass for
  each of its 34 entity names. A chapter almost always contains an `&`, so
  the whole chapter was copied 34 times. That was 349 ms of the 1,117 ms.
  **Fix:** one pass over the UTF-8 bytes with a dictionary lookup: 1.7 ms
  for the same 120 chapters. The fuzz test against the old version found
  one difference: an entity followed directly by a combining mark
  (`&zwj;` + U+0301) used to stay unresolved and then broke the XML parse;
  now it resolves.
- `flush()` (`:721`) trimmed the end of each paragraph with
  `text.reversed().drop{…}.reversed()`, which walks and rebuilds the whole
  paragraph one Character at a time. In the profile this was about half the
  builder's time. **Fix:** `removeLast()` while the last character is a
  space or newline. The other trims now look only at the ends of the
  paragraph or stop early, and the `" \n"` passes run only when the text
  has a newline.
- `isTypedBreak` (`:686`) built a filtered copy of every paragraph to decide
  whether it was a "* * *" scene break. **Fix:** return at the first
  character that isn't a break mark.
- `append` (`:707`) copied the last run before adding text to it, so the
  run's string was copied on every `foundCharacters` callback. **Fix:**
  append in place. `foundCharacters` (`:641`) also ran a regex on every
  callback; it now does so only when the text has a tab, CR or LF.
- `archive[path]` in ZIPFoundation walks the central directory on each
  lookup, and the parser looked up every chapter and image. **Fix:** build
  a path-to-entry dictionary once (`:164`).

| 120 chapters, 1.5 MB | before | after |
|---|---|---|
| `EPUBBookParser.parse` | 1117 ms | **218 ms** |
| `blocks(fromXHTML:)` ×120 chapters | 1053 ms | 222 ms |
| `xmlSafe` ×120 | 349 ms | 1.7 ms |

**Left:** on a 1.5 MB book the remaining ~1.8 ms per chapter is spread
across Swift string handling in `BlockBuilder`. Parsing only the chapters
near the reading position, and the rest later, would make opening feel
instant. That changes how the reader pages through the book, so it's a
recommendation.

### 2. "Update" on a fic that hasn't changed redoes everything (recommendation)

`AppModel.update(_:)` (`:1829`) → `downloadWork` → `fetchWork` + `downloadEPUB`
→ `Organizer.place`. If the work hasn't changed since it was saved, that
still costs:

- 2 AO3 requests, with at least 3 s of scheduler spacing between them;
- a full EPUB download (tens of KB to several MB);
- a move of the old copy into `Backups/`, kept for 30 days;
- a new file written into the iCloud library, which iCloud uploads.

The work page's download link already says when the work last changed
(`?updated_at=<unix time>`, parsed into `WorkInfo.updatedAt` in
`AO3Client.fetchWork`), and Parade fetches that page first anyway.

**Fix:** keep the `updated_at` of each saved copy (e.g. in the library
database, next to the fic id). On Update, after `fetchWork`, if
`work.updatedAt` equals the stored value and the chapter count matches,
say "Already up to date" and stop. That saves 1 request, the download, a
backup and an iCloud upload per no-op update. This needs a field in
storage, which is the storage audit's area, so it isn't done here. Risk:
a missing stored value has to mean "download", never "skip".

The update **check** (`checkForUpdates`, `:1766`) is already efficient:
one search request names up to 400 work ids (`AO3WorkQuery.maxIDs`),
filtered to works revised since the last check, so 10,000 fics take about
25 requests at background priority and nothing is downloaded. It runs
only when asked.

### 3. EPUB downloads off: a 404 on every save (fixed)

While AO3 has EPUB downloads switched off but still shows the link,
`downloadEPUB` asked for the EPUB, got a 404, then fetched the HTML
download. That happened on every save: 3 requests and 2 spacing gaps
instead of 2 and 1. For a 20-work series or a batch of links, that is 20
wasted requests to a site that's already rate-limiting us, and about a
minute of waiting.

**Fix** (`AO3Client.swift:94`, `EPUBsOff`): after an EPUB link fails and its
HTML download works, the client remembers it for 30 minutes and goes
straight to the HTML download. Anything unexpected sends it back the usual
way:

- if the HTML download fails for any reason other than a rate limit or the
  waiting room, the memory is cleared and the EPUB is tried (the HTML is
  not requested twice);
- a successful EPUB download clears the memory;
- after 30 minutes the EPUB is tried again.

The cost is that if AO3 turns EPUBs back on, saves within those 30 minutes
are built from the HTML download, as they already were while EPUBs were
off.

Measured with `CountingAO3`:
`/works/…, /downloads/….epub (404), /downloads/….html` the first time, then
`/works/…, /downloads/….html`.

### 4. `latestDate` made a DateFormatter per call, on the main actor (fixed)

`WorkDetails.latestDate` (`EPUBDetails.swift:64`) built and configured a new
`DateFormatter` every time it was read: **62 µs** each. It's read on the
main actor:

- for every fic when sorting by Last Updated (`AppModel.swift:651`): about 62 ms
  for 1,000 fics;
- for every visible row in that sort (`FicRow.swift:140`) on each render;
- for every fic in `checkForUpdates`.

**Fix:** parse the fixed `yyyy-MM-dd` shape by hand (0.2 µs). Anything else
falls back to one shared, preconfigured formatter. A test checks that the
hand parse matches the formatter for every day from 1999 to 2031, and that
invalid dates such as Feb 29 2023 are left to the formatter.

### 5. Regex compiled on every call (fixed)

`HTMLExtract.firstMatch` and `allMatches`, `EPUBBookParser.firstMatch` and
`allMatches`, `BlurbExtract.ranges`, and `EPUBDetailsParser`'s helpers all
called `NSRegularExpression(pattern:)` on every call. A search-page blurb
runs about 20 patterns, and indexing an EPUB's details runs about a dozen.
`decodeEntities` compiled 2 regexes and made 8 replace passes even on
strings without a `&`.

**Fix:** `RegexCache` (compiled once per pattern and shared;
`NSRegularExpression` is immutable and thread-safe; capped at 512
patterns), and `decodeEntities` returns early when there's no `&`.

| | before | after |
|---|---|---|
| `EPUBDetailsParser.parse`, fixture library ×50 (500 EPUBs) | 202 ms | **80 ms** |
| Search results page, 20 blurbs, 105 KB | 28 ms | **18 ms** |

The details index reads every EPUB in the library on first launch and when
files change, so a 5,000-fic library's first index drops from about 2 s of
CPU to 0.8 s.

### 6. Building an EPUB from AO3's HTML download (partly fixed)

This path is used when AO3's EPUBs are off, and for every ao3saver.com save.
`AO3ExportParser.parse` → `XHTMLFragment.make` per chapter → `xmlSafe` (finding 1).

| 120 chapters, 1.5 MB | before | after |
|---|---|---|
| `AO3ExportParser.parse` | 609 ms | **271 ms** |
| `XHTMLFragment.make` ×120 | 384 ms | 45 ms |
| `WorkPageEPUB.write` | 7.6 ms | 7.6 ms (fine) |

**Left:** `WorkPageParser.element` (`WorkPage.swift:182`) finds an element by
running Foundation regex searches (`String.range(of:options:.regularExpression)`)
from the cursor to the end of the document, once per tag it balances. This
costs ~25 ms per 500 KB per call. `parse` calls it on the whole document
for `#chapters` and again for `#afterword`, and once per chapter.
Rewriting it as a single forward scan over UTF-8 would take most of the
remaining 271 ms. It runs off the main actor once per save, and the save
already waits 3 s between requests, so this is low priority and left as a
recommendation.

### 7. Saving from search or linking fetches the work page again (recommendation)

`download(workID:title:toRead:)` (`AppModel.swift:1411`, saving a search
result) and `relink` (`:1566`, which follows a search in `linkNextUnlinked`)
call `fetchWork` before downloading. The search blurb already has the
title, authors and chapters. That's 2 requests per save where 1 could do:
AO3 serves `/downloads/<id>/<anything>.epub`.

The page fetch does three things the blurb can't:

- it detects a restricted work (login page);
- it gets the `updated_at` that busts AO3's download cache;
- it gets the current chapter count for the chapter guard.

**Fix, if wanted:** for saves from a search result less than a few minutes
old, build `WorkInfo` from the blurb and download
`/downloads/<id>/<id>.epub` directly, falling back to `fetchWork` on any
error. That halves requests for "save from search" and for bulk linking
(20 fics per batch). Medium risk: a stale download cached at AO3's CDN
could be saved. If this lands, keep the chapter guard against the blurb's
count.

### 8. Wayback fallback fetches the wrong snapshot first (recommendation)

When AO3 is down, `downloadWork` falls back to the Wayback Machine with
`original: "https://archiveofourown.org/works/<id>"` (`AppModel.swift:1453`).
For any multi-chapter work, that snapshot holds only chapter 1, so
`WaybackClient.fetchWork` (`:50`) then fetches the `view_full_work=true`
snapshot as well: 2 page fetches of up to several MB each, plus the EPUB
attempt.

**Fix:** when the caller has no specific snapshot URL (the automatic
fallback), try the full-work URL first and the plain URL second. Single-chapter
works whose full-work URL was never archived would then take one extra 404,
so the order could depend on the chapter count, if known. This runs on the
Wayback Machine's own queue, not AO3's, so it's low priority.

### 9. Series (recommendation; partly a correctness bug)

- `HTMLExtract.seriesWorkIDs` reads only the series page it was given. AO3
  shows 20 works per series page, so works 21 and later of a long series
  are never saved. This is a correctness bug as well as a missing request.
- Adding a series link downloads every work again (2 requests each), even
  those already saved and current. With finding 2's stored `updated_at`,
  works already in the library could be skipped (or only checked), which
  would turn a 20-work series re-add from 41 requests into 1–3.

### 10. The reader holds every image in memory (recommendation)

`EPUBBookParser.parse` puts every image the text uses into `book.images`
(`EPUBBook.swift:210`) before the book opens. Fics with many embedded images
(comics, chat screenshots) hold all of them in memory as `Data` while
reading. **Fix:** keep the archive path and load each image when its block
is shown (and cache a few). This touches the reader views, so it's left
for the rendering audit.

## Looked at and fine

- **AO3Scheduler.** It sends one request at a time, 3 s ±20% after the
  previous one finished (`AO3Scheduler.swift:40`). It backs off for
  max(Retry-After, 20 s·2ⁿ) after a 429/503/525, opens a breaker after 3
  in 5 minutes, and rests background work for 60 s after 20 requests.
  Parsing happens outside the turn, so a slow parse doesn't hold up the
  queue. The 3 s gap does add at least 3 s between a save's page fetch and
  its download. Given that AO3 answered both of my two probe requests with
  429, I would not shorten it. Fewer requests (findings 2, 3, 7, 9) is the
  better lever.
- **No HTTP caching or conditional requests.** The session is ephemeral
  with no `URLCache`. AO3's 429 responses say `no-store`. Whether its
  pages and downloads send `ETag` or `Last-Modified` is unverified, because
  both probes were rate-limited. A conditional GET would still be a
  request; the `updated_at` comparison (finding 2) gets the same saving
  without depending on AO3's headers.
- **Search paging** (`SearchModel.page`) caches pages by URL and loads one
  page at a time only as the list nears its end. **Tag resolution**
  (`TagResolver`) asks once per tag name, ever, and joins requests already
  in flight.
- **`fetchWork` extraction**: 2.3 ms for a 55 KB work page. Fine.
- **`ChapterGuard.chapterCount`**: reads only the `.ncx` entry, not the
  whole EPUB (0.5 ms for 120 chapters). It runs on the main actor in
  `AppModel.save` and `Organizer.place`; small enough.
- **Waiting-room check**: looks at the first 20 KB of each HTML response
  (microseconds). For downloads it reads the file only when the response
  isn't a plain success.
- **`WorkPageEPUB.write`**: 7.6 ms for 120 chapters, written once. Fine.

## What changed in this lane

- `EPUBBook.swift`: one-pass `xmlSafe`; `flush`, `append`,
  `foundCharacters` and `isTypedBreak` without whole-paragraph copies;
  zip entries indexed once.
- `EPUBDetails.swift`: `latestDate` without a formatter per call.
- `RegexCache.swift` (new); `HTMLExtract`, `EPUBBook`, `AO3Search` and
  `EPUBDetails` use it. `decodeEntities` returns early when there's no `&`.
- `AO3Client.swift`: remembers when AO3's EPUB downloads are off (`EPUBsOff`).
- Tests (`PerfRegressionTests.swift`):
  - `xmlSafe` against the old implementation on 2,000 fuzzed strings;
  - reader whitespace handling;
  - `latestDate` and the hand-parsed day against the formatter for 11,000
    days;
  - request counts with EPUBs off, the fallback when the HTML download is
    missing, and the 30-minute expiry.
- Benchmarks (`PerfBenchmarks.swift`, skipped unless `PARADE_BENCH=1`).

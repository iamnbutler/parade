# UI performance: rendering, invalidation, the reader

An audit of Parade's SwiftUI side: what redraws, what runs on the main
thread, what the reader lays out, and what the UI writes. Storage writes and
AO3/EPUB processing have their own audits; this one stops at the view layer.

Findings are ranked by impact. The ones marked **Fixed** are fixed in
the `perf-ui` lane. The rest are recommendations.

## How it was measured

- **Fixture:** a synthetic AO3-style EPUB, *The Long Hall*: 40 chapters,
  about 395,000 words, with notes panels, quoted callouts and section
  breaks. It sat alongside the ten `make-fixtures.py` fics in a throwaway
  library: a fresh simulator device for iOS, and
  `PARADE_TEST_LIBRARY=/tmp/…` on the Mac.
- **Counters:** a temporary, uncommitted probe counted body evaluations, line
  rebuilds, page builds, model publishes and position saves, and timed the
  builds. A debug-only hook opened the fic and drove the reader: 600 row
  crossings in scroll mode (setting the scroll position the way a finger
  does) and 60 page turns in page mode.
- **Pagination scaling:** timed with a standalone AppKit benchmark built with
  `-O`, using the same TextKit loop on 0.5M, 1M and 2M characters.
- **Numbers:** simulator numbers come from a debug build, so they are high
  in absolute terms. Compare them with each other, not against a frame
  budget.
- **Not measured:** Anvil's simulator input wasn't available (the device's
  HID digitizer service was missing), and Mac desktop input was not
  approved. So tab switching and live window resizing were read from code,
  not timed.

## Findings

### 1. Page mode: pagination grew about 8× each time the book doubled. **Fixed**

`ReaderView.swift`, `paginate(_:size:pad:)`

- **What happened:** one `NSLayoutManager` got one `NSTextContainer` per page
  for the whole book. TextKit 1's cost per container grows with the number
  of containers already attached.
- **How often:** every time a fic opens in page mode, and again on every
  change of text size, page color or window size.
- **Cost (AppKit, `-O`, 340×640 pt pages):**

  | Characters | Pages | One stack | Per chapter |
  |---|---|---|---|
  | 0.5M | 736 | 2.3 s | 0.16 s |
  | 1.0M | 1,475 | 17.9 s | 0.34 s |
  | 2.0M | 2,946 | **147 s** | **0.67 s** |

  In the simulator, *The Long Hall* showed a spinner for about 158 s before
  its first page. With the fix it shows in about 5 s, and most of that is
  the debug build.
- **Fix:** paginate each chapter with its own TextKit stack. Chapters
  already open on a fresh page (the form feed), so the page breaks are the
  same. Before removing the old function, I checked old against new in the
  app: identical page ranges on a 6-chapter fic with notes panels and quoted
  callouts (363 pages), and on the small fixtures.

### 2. iOS page mode: every page turn built all 2,437 pages. **Fixed**

`ReaderView.swift`, `PagedReader.pager` → `pageContent`

- **What happened:** the page-style `TabView` calls its `ForEach` closure
  for every tab on each update. That closure did each page's work directly:
  `attributedSubstring`, a binary search for the section, and
  `paged.text.string as NSString`. The last one copies the whole book's
  text, because the backing string was mutable.
- **How often:** on every page turn, for every page in the book.
- **Measured:** 60 turns caused **155,968** page-content builds (2,437 per
  turn). After the fix: **281** page bodies (about 4.5 per turn, the pages
  actually shown).
- **Fix:**
  - The per-page work moved into a `BookPage` view whose initializer only
    stores values; its `body` runs for the pages on screen.
  - `PagedText` keeps an immutable copy of the text and its `NSString`,
    bridged once.

### 3. Scroll mode: the whole book's rows were rebuilt every time a row crossed the top. **Fixed**

`ReaderView.swift`, `ReaderPage.lines`

- **What happened:**
  - `lines` was a computed property calling `ReaderLines.build(book)`. That
    walks every block, joins each block's runs into a new string
    (`Block.text`), lowercases it for `isLabel`, and counts its characters
    for `isByline`.
  - `.scrollPosition(id: $topLine)` changes `topLine` whenever a row passes
    the top, which re-evaluated the body and rebuilt all of it.
- **Measured:** 600 row crossings caused 601 rebuilds, **11.2 s** of
  main-thread time (about 19 ms each in a debug build, over a frame on any
  device). After the fix: **one** build (20 ms) when the fic opens.
- **Fix:**
  - `ReaderView` builds the lines once per copy of the fic and passes them
    to both readers and the contents list.
  - The rows sit in an equatable `ReaderRows` view (equal while the book
    version and text size are), so scrolling re-evaluates only the thin
    outer body.
  - Page mode reuses the same lines.

### 4. Mac page mode: every width step during a window drag laid out the book again. **Fixed**

`ReaderView.swift`, `PagedReader.body` `.task(id:)` → `layOut`

- **What happened:** the task's id includes the page size in whole points,
  so a live resize starts a new layout at nearly every frame.
  - `PagedText.build` runs on the main thread: 54–73 ms in a debug build for
    *The Long Hall*.
  - The `Task.detached` pagination isn't cancelled when the `.task` is, so
    every step's pagination ran to completion. Before fix 1, that was up to
    147 s each.
- **Fix:** a relayout with pages already up waits 250 ms. A newer size
  cancels it first, so a drag lays out once, at the end. The first layout
  isn't delayed. Text size and paper changes also pass through the wait,
  which is unnoticeable and merges repeated taps on A+.

### 5. Page turns saved the same reading position twice. **Fixed**

`ReaderView.swift`, `PagedReader.go(to:)`

- **What happened:** the TabView selection binding echoes the page it was
  just set to, and `go(to:)` saved the position again. Each save is a
  synchronous SQLite write on the main thread through GRDB.
- **Measured:** 77 saves for 62 turns.
- **Fix:** `go(to:)` returns early when the page and anchor haven't
  changed. (Not re-measured after the fix.)

### 6. Every chapter heading compiled a regex and built a `NumberFormatter`. **Fixed**

`ReaderView.swift`, `BlockView.chapter(_:)` and `spelledChapter(_:)`

- **What happened:** `NSRegularExpression(pattern:)` was compiled on every
  call, and a fresh `NumberFormatter` was made for "Chapter one".
- **How often:** every time a heading row is drawn, and once per heading in
  every `PagedText.build`.
- **Fix:** both are now static and created once.

### 7. Library lists filtered the whole library two to four times per redraw. **Fixed**

`MacRootView.swift` (`libraryList`, `collectionList`, `browseList`) and
`LibraryView.swift`

- **What happened:** `filteredSections`, `libraryFlat`, `filteredGroups` and
  `model.items(for: .tag…)` are computed properties. Each was evaluated
  again for the `List`, the empty state (`noSearchResults`) and the header
  count. With a search typed, each pass runs two
  `localizedCaseInsensitiveContains` per fic.
- **How often:** every redraw of the list's parent, which happens on any
  `AppModel` change (see finding 8) and on every keystroke.
- **Fix:** each body filters once into a local `let` and shares it.

### 8. One `ObservableObject` model redraws every observer on any change. *Recommendation*

`AppModel.swift:136`

- **What happens:**
  - `AppModel` is an `ObservableObject` with about 30 `@Published`
    properties.
  - Every `FicRow`, `BlurbRow`, `FicDetailView`, `FicPager`,
    `ContinueReadingRow`, `FloatingListControls` and list parent observes
    it, through `@EnvironmentObject`.
  - So any write redraws all of them: a status line, a toast, the
    `updating` set, `lastReadID`, a details-index chunk.
- **Measured:**
  - Launch publishes 14–16 changes. With 11 fics, `FicRow` bodies ran 84–157
    times, about 12 per row.
  - Updating one fic publishes about 8–15 times: `isWorking`, `updating`,
    status lines, toast, `updatesAvailable`, then the rescan's `library`.
    Each time, every visible row and the list's parent run again; on iOS
    that includes `FicPager`, which filters the whole list.
- **Cost:** in proportion to visible rows times publishes, plus the parent's
  filtering. Lists are lazy, so this doesn't grow with library size, but a
  batch download writing a status line per fic redraws the whole UI each
  time.
- **Fix (ordered by risk):**
  1. Give `FicRow` plain values (`isFavorite`, `hasUpdate`, `isUpdating`)
     and have it hold the model unobserved, the way `ReaderView` already
     does. Its actions only call methods.
  2. Move the activity log (`statusLines`), `toast` and `updating` into a
     small object of their own.
  3. Move `AppModel` to `@Observable`. The deployment targets (iOS 17,
     macOS 14) allow it, and views would track only the properties they
     read.

### 9. `PagedText.build` runs on the main thread. *Recommendation*

`ReaderView.swift`, `PagedText.build` (`@MainActor`)

- **What happens:** the whole book's `NSAttributedString` is built on the
  main thread. That includes decoding every image (`PlatformImage(data:)`)
  and rendering the end drawing with `ImageRenderer`.
- **Cost:** 54–73 ms for *The Long Hall* in a debug build, once per layout.
  It's a hitch when the reader opens and on each text size or paper change.
- **Fix:** convert the palette to platform colors and render the drawing on
  main, then build the string in the detached task with the pagination.
  Nothing else in it needs the main actor. I left this out because it
  touches the Sendable boundaries around `Palette` and `EPUBBook`.

### 10. Reader images are decoded in `body` every time a row appears. *Recommendation*

`ReaderView.swift`, `ReaderImage.body` (`PlatformImage(data:)`)

- **What happens:** the image is decoded on the main thread whenever its
  lazy row is built: scrolling past and back, or a text size change.
- **Cost:** a few ms per large image, and only fics with images pay it.
- **Fix:** decode once per book, off main, in `load()`, into a
  `[String: PlatformImage]` in the environment. A global cache keyed by
  path would collide between books, since AO3 names images the same way.

### 11. Mac: the backdrop `GeometryReader` redraws the root on every frame change. *Recommendation*

`MacRootView.swift:212-218`

- **What happens:** `onChange(of: geo.frame(in: .global))` writes
  `backdropFrame`, which is `@State` on `MacRootView`. So during a window
  drag or sidebar resize, the root body runs every frame, including the
  library list's filtering (smaller after fix 7).
- **Fix:** keep the frame in a small child view or preference that only
  `BackdropSlice` reads, or store it in a reference box the sidebar
  observes.

### 12. Smaller items. *Recommendations*

- **`FlowLayout`** (`FicNavigation.swift`): every chip is measured twice
  per pass, by `sizeThatFits` and again by `placeSubviews`, both through
  `arrange`. Cache the rows in `Layout`'s cache. It matters on detail pages
  with 50+ tags.
- **`FicDetailView.details`** (`FicDetailView.swift:21`): it calls
  `model.cachedDetails(for:)` on each of about 10 reads per body, and each
  call builds a cache key from the URL path and date. `isToRead` also
  standardizes two URLs per body. Read it once per body.
- **`BlockView.styled`** builds an `AttributedString` per row body. That's
  fine now that rows aren't rebuilt while scrolling. If profiling shows it,
  precompute it in `ReaderLines.Line`.
- **The paged reader doesn't re-lay out when the open fic is updated.** Its
  `.task(id:)` key has no book version, so it keeps the old pages. This is
  correctness, not speed, and it was there before this change; worth adding
  `linesVersion` to the key.

## Checked and fine

- **Reading position writes:**
  - Scroll mode saves 600 ms after scrolling settles: 2 saves across 600
    row crossings, to the device's SQLite database.
  - `Reading.json` in iCloud is written only when the reader closes, the
    app goes to the background, or every 15 minutes, and only when there
    are pending positions.
  - Nothing goes to UserDefaults per scroll.
- **The reader doesn't observe the model.** `ReaderView` holds `AppModel`
  unobserved, so library changes don't re-lay out the page.
- **Scroll-driven chrome** (`BackToTop`, `hidesOnScrollDown`) maps scroll
  geometry to a `Bool` and writes state only when it flips.
- **Leather surfaces:** the grain tile is baked once (`Grain.tile`), the
  gradients are static, and nothing is generated per frame. The
  large-radius shadows (`embossed(lifted:)`, `PaperClipping`) appear on a
  handful of cards, not on list rows. There are no blurs or materials in
  content; the iOS bar uses the system's.
- **No timers or repeating tasks** keep running off screen. The iCloud wait
  in `ReaderView.load()` polls every 500 ms only while that file is
  downloading, and it's cancelled with the view.
- **Sorted and grouped library views** are cached in the model
  (`flatCache`, `sectionCache`, `tagCache`) and invalidated only on library
  or details changes.

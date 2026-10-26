# Changelog

## Unreleased

### Changed
- **Search AO3 has a proper form.** Set the search up on its own page, then
  search; the results page shows a short summary of it with Edit Search.
  - Every archive warning and category can be included (any of them) or
    excluded.
  - Fandoms, relationships, characters and additional tags can each be
    included or excluded.
  - Crossovers (include, exclude, only), complete or in progress, single
    chapter, updated within, title, creator, and every sort AO3 has, in
    either direction.
  - Any tag on a result's page can be included in or excluded from the
    search. Searches saved by 0.6.0 carry over.

## 0.6.0 — 2026-10-25

### Added
- **Read in Parade.** Fics open in Parade's own reader, as pages or one
  scroll. It has contents, text size and page color, and it remembers your
  place across devices. Fic formatting comes through: alignment, tables,
  images, and texting-style chat logs drawn as phone threads.
- **Search AO3**: a Search tab on iPhone and a sidebar section on Mac.
  - The first search covers the fandoms in your library. It stays as you
    leave it, synced through `Search.json` in the library folder.
  - Fandoms match any of them, not AO3's all-of-them. Fandom names from
    EPUBs are looked up as AO3's canonical tags, so a synonym like "Mo Dao
    Zu Shi" finds the whole fandom.
  - Filters: Explicit only, Complete only, tags to include, hidden tags
    and authors, and hide fics you already have.
  - Results show what's already in your library or To Read. Save to To
    Read or the library from a row or the preview.
  - Results load one page at a time as you scroll, through the same polite
    request queue as downloads.
- **To Read**: fics saved for later wait in a folder of their own, beside
  the library. Add one to the library when it's a keeper.
- **Continue reading**: the fic you read last, on any device, sits at the
  top of the library. Long lists get a Back to Top arrow and a Resume
  button.
- **Link fics to AO3**: for EPUBs downloaded outside Parade, find the work
  on AO3 and swap in AO3's own copy, with its link, tags, summary and
  series. The old file goes to Backups. If search misses, paste the
  work's link.
- Library search remembers recent searches, suggests your fandoms, ships
  and tags, and matches summaries.
- Sort by fandom.

### Changed
- **A new look**: Leather & Ink — a warm dark theme with book typefaces,
  drawings for empty pages, and a new app icon.
- **iPhone tabs** are Library, To Read, Collections, Search and Settings.
  Favorites is the first row in Collections. Tab headers slide away as a
  list scrolls down and come back when it scrolls up.
- **Check AO3 for Updates** asks AO3 for a few hundred fics per request
  instead of fetching every fic. Every AO3 request now waits its turn: one
  at a time, a few seconds apart, backing off when AO3 asks.
- Fic details and search run from a local database on each device, so big
  libraries open and search faster.
- Section headings scroll with their fics instead of pinning.

### Removed
- Apple Books integration: sending fics to Books, auto-import, Import All
  and the Apple Events permission, and the fic page's Books button. Fics
  are read in Parade's own reader.
- The Add sheet's Paste button, which started downloading in one tap.
  Paste into the link field instead.

### Fixed
- Battery: background refreshes stop rewriting caches that didn't change.
- iOS: scrolling lists no longer washes out row text under section headers.

## 0.5.1 — 2026-10-20

### Fixed
- Swiping between fics no longer jerks or bounces: pages arrive with their
  details already showing instead of flashing a spinner and jumping, and
  the pager no longer redraws itself mid-swipe.

## 0.5.0 — 2026-10-17

### Added
- **Collections** — your own categories, separate from AO3's tags. Make
  them in the Collections tab (or the Mac sidebar), then long-press /
  right-click any fic, or use the Collections button on its page. Stored in
  `Collections.txt` in the library folder, so they sync through iCloud and
  can be edited by hand.
- **Batch download** — paste any number of AO3 work or series links at once
  (one per line, comma-separated, or buried in text). They download one
  after another, politely spaced; duplicates are skipped.
- **Update one fic** — Update is in every fic's swipe actions and
  long-press / right-click menu, and always re-downloads the fic when
  tapped. Updating is only ever manual. Fics flagged by "Check AO3 for
  Updates" show a yellow dot at the end of the row, and that now survives
  relaunching the app.
- **Swipe between fics** (iPhone/iPad) — a fic's page swipes sideways to
  its neighbors in whatever list you opened it from.
- **New sorts**: By Series (sections in part order, standalone fics last)
  and Date Added. Updating a fic keeps its original added date.
- **Browse by tag** — the Fandoms tab is now Browse: fandoms, series,
  relationships, characters, or tags. Tags, fandoms, and the series line on
  a fic's page are tappable and open every fic that shares them.
- An **Update** button on every fic's page, and a "No results" message
  when a search matches nothing.

### Fixed
- Fic dates show which date they are (downloaded, added, updated) and are
  in the order the list is sorted by.
- Favorites and collection changes no longer flicker back while the
  library is being rescanned.
- "Check AO3 for Updates" no longer overlaps other downloads.
- Mac: "Add a Folder to Library…" refuses the library itself (which would
  have scrambled it) and starts in your home folder.
- Mac: following a tag from a fic's details opens it in Browse, with Back
  retracing your steps; the detail pane clears when the new list doesn't
  include the fic.

## 0.4.2 — 2026-09-01

### Fixed
- The library streams in as it's found instead of appearing all at once —
  on a phone reading a large iCloud library for the first time, fics show
  up within a second instead of after a long silent scan.
- Real loading states everywhere: "Loading your library…", "Moving your
  library into iCloud Drive › Parade…", and "Reading fic details…" replace
  the misleading empty screens ("No fics yet" while still loading was the
  bug behind the "library is empty" TestFlight feedback).

## 0.4.1 — 2026-08-31

### Fixed
- Large libraries no longer freeze or crash the app on launch. All library
  scanning, migration, and iCloud download requests now run in the
  background — the app opens instantly and the list fills in. Verified
  with a 100,000-fic library.

### Changed
- Fic metadata (tags, fandoms, series…) is now cached between launches, so
  the library is parsed once ever instead of on every launch.
- Sorting and search no longer re-sort the whole library on every screen
  update; big libraries stay responsive while switching sorts and typing.
- iCloud downloads for a still-syncing library are requested once, not
  re-requested every refresh; rescans space themselves out for huge
  libraries.

## 0.4.0 — 2026-08-31

### Changed
- The library now lives in Parade's own iCloud Drive folder ("iCloud
  Drive › Parade") on both platforms — no folder picking or connecting,
  ever. Existing libraries (the old "Fan Fiction" folders, and anything
  saved locally on the phone) move in automatically on first launch;
  nothing is deleted — duplicates are kept in Backups/.
- Fics are now filed by source: `ao3/Author/Title.epub`, paving the way
  for other archives later. Backups follow the same shape
  (`Backups/ao3/Author/…`).
- A folder of EPUBs dropped anywhere in the library folder is noticed and
  filed automatically within seconds.
- Without an iCloud account the library falls back to "On My iPhone ›
  Parade" (or `~/Documents/Parade` on the Mac).

### Fixed
- macOS: closing the reader windows Apple Books opens during import works
  again in signed release builds (the hardened runtime needed an
  Apple Events entitlement).

## 0.3.3 — 2026-08-31

### Fixed
- iOS: the library now refreshes itself every few seconds while the app is
  open, and when returning to the app — fics synced in through iCloud
  appear without a manual pull-to-refresh.

## 0.3.2 — 2026-08-31

### Fixed
- The app now reports its real version (About, TestFlight, and update
  checks previously all saw "1.0 (1)").

## 0.3.1 — 2026-08-31

### Changed
- The macOS DMG is now signed and notarized — it opens without any
  security warnings.
- iOS builds ship through TestFlight.

## 0.3.0 — 2026-08-30

### Added
- Fic updates: "Check AO3 for Updates" (Settings on both platforms, and the
  Library menu on macOS) asks AO3 whether each fic changed since its EPUB
  was made. Changed fics get an Update badge in lists and an Update button
  in their details; updating re-downloads the fic.
- Updates are non-destructive: the previous EPUB moves to
  Backups/Author/Title (date).epub inside the library folder instead of
  being overwritten. The Backups folder never shows up in the library.
- Library sort mode "Last Updated" — newest fic content first, using the
  update date inside each EPUB.
- Favorites: star a fic (swipe right on iOS, right-click on macOS, or the
  Favorite button in its details) and browse them in a Favorites tab /
  sidebar section. The list is a plain `Favorites.txt` in the library
  folder, so it syncs through iCloud along with the fics.
- Library sort modes: by author (grouped, as before) or by title.

### Changed
- The book button is gone from list rows — sending a fic to Apple Books
  lives in its details (and the right-click menu on macOS).
- Deleting a fic now asks for confirmation first. (It removes the file from
  the library folder — and other devices via iCloud; copies already in
  Apple Books stay.)
- Auto-import into Apple Books now defaults to off; turn it on in Settings.
  (Copies that already changed the toggle keep their choice.)

## 0.2.0 — 2026-08-30

### Added
- Fic details: summary, rating, warnings, category, fandoms, relationships,
  characters, tags, series, and word/chapter/date stats — parsed from inside
  each EPUB, fully offline. Shown in a resizable detail pane on macOS and a
  detail screen on iOS, with buttons for Apple Books and the original work
  page.
- Fandoms view (iOS tab / macOS sidebar section): browse fandoms and drill
  into one to see its fics. A fic's place in an author's series shows in its
  details.
- Search filters on all lists — matches title, author, series, fandoms,
  tags, relationships, characters, category (F/M, Gen, …), rating, and
  warnings.
- macOS: standard three-column layout (sidebar / list / detail) with the
  system sidebar toggle and resizable columns.
- macOS: "Add a Folder to Library…" moves an existing Author/epub tree into
  the library folder; a Library menu with "Import All to Apple Books".
- macOS: automatic update checks (Sparkle), "Check for Updates…" in the app
  menu.

### Changed
- Bulk sends to Apple Books now close the reader windows Books opens, in
  batches — no more hundreds of open books.
- Auto-import into Apple Books only applies to fics arriving one at a time
  (a pasted link, or synced from the phone); bulk arrivals wait for an
  explicit "Import All".
- The Library list reads the folder directly; the Library view surfaces
  folder permission errors instead of showing an empty library.

## 0.1.0 — 2026-08-30

Initial release: paste an AO3 work or series link, get AO3's own EPUB filed
as Author/Title.epub in your library folder (iCloud Drive), one-tap into
Apple Books on iOS, automatic import into Apple Books on macOS via the
menu-bar watcher.

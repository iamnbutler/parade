# Changelog

## Unreleased

### Added
- **Settings › Restore.** When an update replaces a fic, Parade has always
  kept the old copy in a Backups folder; now you can see those copies and
  put one back. Recently Updated lists each earlier version with when it
  was backed up and its size, and Recently Deleted lists deleted fics.
  Restore puts either one back where it came from, the library or To
  Read. The copy it replaces is kept as a backup, so you can switch back.
  A fic with an earlier version also shows it on its own page, with a
  Restore button.
- **Deleting a fic moves it to Trash** for 30 days instead of deleting
  it, on every device. Backups and Trash both live in the library's
  iCloud folder, so they sync, and they're never shown in the library.
- **Backups and deleted fics are removed after 30 days**, at launch and
  after each update. Parade still keeps an older backup while it's bigger
  than the fic in your library, since that copy may have chapters a bad
  download lost.

### Fixed
- **Fics saved with only their first chapter.** While AO3's EPUB downloads
  are off, Parade builds the EPUB from AO3's HTML download, and it was
  reading every chapter after the first as missing, so multi-chapter fics
  (by work or chapter link, from search, or from ao3saver.com) saved with
  chapter one alone. They save whole again. Update a fic that came out
  short and it comes back complete.
- **An update never leaves you with less.** If a download has fewer
  chapters than the copy you have, or than AO3 says are posted, Parade
  keeps your copy as it was and says how many chapters were missing,
  instead of replacing it.
- **A deleted fic could stay in the list, or come back.** If Parade was
  reading the library folder when you deleted a fic, that read finished
  with the fic still in it and put it back on screen. To Read also didn't
  drop the fic straight away. Now the list refreshes again after any
  change made while it's reading, and a deleted To Read fic leaves the
  list at once.

## 0.10.0 — 2026-11-15

### Added
- **Mature works are hidden in Search until you say you're 18 or older.**
  A first-launch question asks once; Keep them hidden is the default, and
  closing it also keeps them hidden. Settings › Mature works turns them on
  or off, per device. While they're off, Search leaves out works AO3 rates
  Mature, Explicit or Not Rated, and "Explicit only" is hidden. Fics you
  save yourself are never hidden.
- **Report on AO3**: in the More menu of a search result, and in Settings
  › About Parade, which also links the privacy policy and support page.

### Fixed
- Links on AO3's other addresses (ao3.org, archiveofourown.com, .net and
  .gay) are recognized. Before, a pasted ao3.org link left Download
  greyed out with nothing to say why.
- Chapter-only links (`archiveofourown.org/chapters/<id>`, with no
  `/works/` in them) work: Parade asks AO3 which work the chapter is in.
  Before, they left Download greyed out.
- The Add fics box says so when it can't find an AO3 link in what you
  pasted, in rose, and Download stays tappable instead of going quietly
  grey (on iPhone a greyed-out button still flashes when tapped, which
  looked like it was working).

## 0.9.1 — 2026-11-15

### Fixed
- **AO3's waiting room.** While AO3 recovers it queues visitors behind a
  Cloudflare waiting room. Parade used to read that as rate limiting and
  back off for ten minutes at a time; now it recognizes the queue, says
  it's in line, keeps its place (the pass cookie is shared by everything
  Parade asks AO3), checks back every twenty seconds or so and carries on
  when let in, for up to half an hour. Adding fics and search show it, and
  Stop waiting is there if you'd rather not.
- When AO3 is down or overloaded, saving by link or from search no longer
  fails with "Couldn't read the AO3 page (EPUB download link)". Parade says
  AO3 isn't serving the work, then looks for a saved copy at ao3saver.com
  and in the Wayback Machine, and saves that if it finds one.
- **AO3 has turned EPUB downloads off** (its HTML download still works).
  Parade now takes the HTML download and builds the EPUB from it, with the
  same tags, summary, notes and every chapter, so fics save and read as
  usual. The preface says it was built from the HTML download; Update on
  the fic's page fetches AO3's own EPUB once those are back.
- A work page whose download link Parade can't find (or finds on another
  AO3 host) still downloads.

## 0.9.0 — 2026-11-15

### Added
- **Ellipsus Reader links**: paste an `ellipsus.com/read/…` link and Parade
  saves the story as an EPUB in an `ellipsus` folder of the library, with
  its author, summary, formatting and a link back to the Reader page. It
  has no AO3 link until you give it one.
- **Change an AO3 link.** A fic linked to the wrong AO3 work now has Change
  Link on its page: paste the right work's link, or search for it.

### Changed
- The AO3 link box on a fic's page always has a place to paste a link, so
  you can link a fic without searching AO3 first. ao3saver and Wayback
  links work there too.

## 0.8.0 — 2026-11-12

### Added
- **ao3saver.com links**: paste an ao3saver.com work link (with or without
  `?version=`) and Parade saves that version, built into an EPUB with the
  same tags, summary, notes and chapters as AO3's own export. No AO3
  needed.
- **Back to top** at the end of a fic, in both Pages and Scroll: one tap
  returns to the first page.

## 0.7.0 — 2026-10-31

### Added
- **Wayback Machine links**: paste a web.archive.org link to an AO3 work
  when AO3 is down. Parade uses AO3's EPUB if the archive has it, and
  otherwise builds one from the archived page, with the same tags, summary,
  notes and chapters as AO3's own export. A chapter link brings in the
  full-work snapshot if there is one; if only some chapters were archived,
  it says so.

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

### Fixed
- Works with "works inspired by this one" were filed under those works'
  authors too; only the work's own byline counts now.

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

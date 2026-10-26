# Parade — manual test plan

Every user-facing feature, on both platforms. Run it before a release, or
after any change that touches the library, navigation, or downloads.

## Setup

Never test against a real library. Use the synthetic fixtures
(`scripts/make-fixtures.py`: 10 fics, 5 authors, 3 two-part series).

**iOS simulator** (no iCloud → the app uses its local Documents folder):

```sh
xcodebuild -project Parade.xcodeproj -scheme Parade \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build-sim build CODE_SIGNING_ALLOWED=NO
xcrun simctl install booted build-sim/Build/Products/Debug-iphonesimulator/Parade.app
DOCS="$(xcrun simctl get_app_container booted com.natebutler.parade data)/Documents"
python3 -I scripts/make-fixtures.py "$DOCS/ao3"
xcrun simctl launch booted com.natebutler.parade
```

**macOS** (debug builds only — `PARADE_TEST_LIBRARY` swaps in a scratch
folder with its own settings and caches, skips iCloud and migration):

```sh
xcodebuild -project Parade.xcodeproj -scheme Parade -destination 'platform=macOS' \
  -derivedDataPath build-mac build CODE_SIGNING_ALLOWED=NO
mkdir -p /tmp/parade-test/ao3 && python3 -I scripts/make-fixtures.py /tmp/parade-test/ao3
PARADE_TEST_LIBRARY=/tmp/parade-test build-mac/Build/Products/Debug/Parade.app/Contents/MacOS/Parade
```

Settings › "Saving to" must read `Test library › /tmp/parade-test` before
going further.

**Network.** Fixture work ids (999000000+) are far above any real AO3 id:
Update and batch downloads against them exercise the error paths. (An
earlier fixture set used 90000000+, which ARE real works — regenerate old
fixtures before testing.) Real downloads go
to one public work at a time, never in bulk, and the results are deleted
afterwards.

Legend: (iOS) / (Mac) = platform-specific; unmarked = both.

## 1. Launch & loading

- 1.1 Fresh launch shows "Loading your library…", then the list — never
  "No fics yet" while loading.
- 1.2 Empty library folder shows "No fics yet" with add instructions.
- 1.3 Unreadable library folder shows the error state with Try Again.
- 1.4 Files dropped into the folder appear without relaunching
  (iOS: within ~15s or on reactivation; Mac: within ~15s or Scan Now / ⌘R).
- 1.5 A stray `Author/Title.epub` folder at the root is filed into `ao3/`.

## 2. Library list

- 2.1 **By Author**: one section per author, A→Z; fics newest first.
- 2.2 **By Title**: flat, A→Z, rows show author.
- 2.3 **By Series**: section per series A→Z, parts in order (Part 1 before
  2), "Not in a Series" last.
- 2.4 **Date Added**: newest first, subtitle says "added …".
- 2.5 **Last Updated**: by the date inside the EPUB.
- 2.6 Sort choice survives relaunch.
- 2.7 Search matches title, author, series, fandom, relationship,
  character, additional tag, rating, warning, category; sections with no
  matches disappear; clearing restores everything.
- 2.8 (iOS) Pull to refresh works.
- 2.9 Row badges: star for favorites; yellow dot at the END of the row for
  fics with an update flagged; "iCloud…" for undownloaded placeholders.

## 3. Row actions

- 3.1 Leading swipe: Favorite / Unfavorite toggles the star.
- 3.2 Trailing swipe: Update and Delete (Remove inside a collection).
- 3.3 Delete asks for confirmation; Cancel keeps the fic; Delete removes
  the file (and its empty author folder), its favorite, its collection
  memberships, and its update flag.
- 3.4 Context menu (long-press / right-click): favorite, Collections ›
  (checkmarks + New Collection…), Update from AO3, (Mac) Reveal in
  Finder, Delete.

## 4. Fic detail

- 4.1 Title, author(s), series line, collections line, summary, stats,
  rating/warnings/category text, fandom/relationship/character/tag chips.
- 4.2 Action buttons never squeeze or break mid-word; they wrap.
- 4.3 Update button appears (prominent) only when flagged; otherwise
  Update lives in the Collections menu.
- 4.4 Share opens the share sheet with the EPUB.
- 4.5 AO3 opens the work page.
- 4.6 Favorite toggles and stays in sync with the list star.
- 4.7 Tapping a chip opens every fic with that tag; tapping the series
  line opens the series in part order; fics there open their details.
- 4.8 (Mac) Selecting another fic resets the detail column's navigation.

## 5. Swipe between fics (iOS)

- 5.1 Opening any fic shows THAT fic (content matches title) with
  "N of M" — test first, middle and last rows of each sort.
- 5.2 Swipe left/right moves one fic; title and counter follow.
- 5.3 The neighbors match the list it was opened from: library (each
  sort, and with a search active), favorites, a tag list, a series, a
  collection.
- 5.4 First and last fic don't over-scroll into blank pages.

## 6. Browse

- 6.1 Picker (toolbar) switches Fandoms / Series / Relationships /
  Characters / Tags; choice survives relaunch.
- 6.2 Counts are right; a fic in two fandoms appears under both.
- 6.3 Filter matches value names and fics inside them.
- 6.4 Drill-in lists the fics; series lists are in part order.
- 6.5 Loading state while details are being read; empty state after.

## 7. Favorites

- 7.1 Empty state with instructions.
- 7.2 Lists favorites A→Z by title; filter works.
- 7.3 Unfavoriting removes it from the list immediately.
- 7.4 `Favorites.txt` in the library folder matches, and survives relaunch.

## 8. Collections

- 8.1 Empty state; create from the tab's + and the empty-state button.
- 8.2 Create from a fic's context menu and detail page — the fic is added.
- 8.3 Blank and duplicate names are refused (Create disabled / no-op).
- 8.4 Toggle membership from the menus (checkmarks reflect state).
- 8.5 Collection list shows counts; opening shows its fics (newest
  added first); filter works.
- 8.6 Trailing swipe inside a collection is Remove, not Delete.
- 8.7 Rename keeps members and stays on the screen; Delete asks, keeps
  the fics in the library, returns to the list.
- 8.8 (Mac) Collections in the sidebar: select, right-click rename/delete,
  "New Collection…" row.
- 8.9 `Collections.txt` matches; hand edits to it show up after a rescan;
  survives relaunch.

## 9. Adding fics

- 9.1 Download button disabled until the text contains a link; label is
  "Download N" for several.
- 9.2 Batch: several links (newlines, commas, buried in prose) → each
  processed in turn, duplicates (incl. chapter links) counted once.
- 9.3 Non-AO3 text via Paste → clear error.
- 9.4 Errors keep the sheet open with the log; success closes it.
- 9.5 Sheet can't be dismissed mid-download; Cancel works otherwise.
- 9.6 (Mac) Menu-bar popover: paste link → downloads; Open Library,
  Scan Now, Quit work.
- 9.7 One real download (single public work) files as
  `ao3/Author/Title.epub`, appears in the list with details.

## 10. Updates (always manual)

- 10.1 Nothing contacts AO3 or downloads on its own — launch, idle, and
  rescans make no AO3 requests.
- 10.2 Update (swipe / menu / detail) always re-downloads, shows a row
  spinner, then a toast with the outcome.
- 10.3 Re-downloading a real fic moves the old EPUB to
  `Backups/ao3/Author/Title (stamp).epub` and keeps its Date Added.
- 10.4 Update while another download runs → "Busy" toast, nothing queued.
- 10.5 Settings › Check AO3 for Updates only flags (yellow dot), never
  downloads; flags survive relaunch; updating clears the flag.

## 11. Settings

- 11.1 "Saving to" label correct; footer text accurate.
- 11.2 Activity log shows the last lines, errors in red.
- 11.3 (Mac) Add a Folder to Library merges an `Author/x.epub` tree; Scan
  Now refreshes.

## 12. Mac-only shell

- 12.1 Sidebar: Library, Browse, Favorites, Settings, Collections section.
- 12.2 Toolbar: sort menu only on Library; Browse picker only on Browse;
  + everywhere except Settings.
- 12.3 Library menu: Check AO3 for Updates, Import All, Scan Now (⌘R).
- 12.4 Window resizes down to its minimum without clipping; columns
  collapse.

## 13. Scale

- 13.1 With ~5,000 fics: launch streams in, sorts switch without a
  freeze, search stays responsive, the pager opens instantly mid-list.

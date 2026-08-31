# Changelog

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

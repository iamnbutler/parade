# Changelog

## Unreleased (0.2.0)

### Added
- Fic details: summary, rating, warnings, category, fandoms, relationships,
  characters, tags, series, and word/chapter/date stats — parsed from inside
  each EPUB, fully offline. Shown in a resizable detail pane on macOS and a
  detail screen on iOS, with buttons for Apple Books and the original work
  page.
- Fandoms view (iOS tab / macOS sidebar section): fics grouped by fandom,
  with a toggle to group by an author's series instead (sorted by part
  number).
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

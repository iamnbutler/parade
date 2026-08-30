# Parade

Paste an AO3 link → get AO3's own EPUB export filed as `Author/Title.epub` in
your library folder (iCloud Drive) → Apple Books. One universal SwiftUI app:
on iOS it's a Library/Settings tabbed app with a share-to-Books button per
fic; on macOS the same app adds a menu-bar presence that watches the library
folder and silently imports every new fic into Apple Books — so with Books'
iCloud syncing on, fics added from the phone appear in Books everywhere with
zero extra taps.

**The filesystem is the source of truth.** The Library view is a live
enumeration of the `Author/Title.epub` tree — there is no separate database.
Fics synced in from another device appear automatically; deleting the file is
deleting the fic.

## Layout

- `AO3Kit/` — Swift package with all the logic: link parsing (works,
  chapters, series, collection-scoped), AO3 page scraping (title, authors,
  EPUB URL, restricted/rate-limit detection), and the `Author/Title`
  organizer. `cd AO3Kit && swift test` runs the unit tests.
- `Shared/` — the app, one multiplatform target for iOS + macOS:
  - `AppModel.swift` — destination folder handling (default: iOS
    `Documents/Fan Fiction`, macOS `iCloud Drive/Fan Fiction`; custom via
    security-scoped bookmark), library enumeration (including `.icloud`
    placeholders, which it asks iCloud to materialize), the download
    pipeline, and — macOS only — the 15s folder watcher + Apple Books import.
  - `Views/` — Library (grouped by author, + sheet to add), Settings, and
    the macOS `MenuBarView` popover.

## Building

The Xcode project is generated — don't edit `Parade.xcodeproj` by hand:

```sh
xcodegen generate        # after changing project.yml or adding files
```

One `Parade` scheme builds for iPhone/iPad or Mac depending on the
selected destination. Signing is automatic (team baked into project.yml).

## Behavior notes

- No conversion happens: AO3 serves EPUBs itself (`/downloads/{id}/….epub`).
  The scraper fails soft with a clear error if AO3's markup ever changes.
- Works and whole series links are supported; series downloads are spaced
  ~1.5s apart, and AO3 rate-limits (429) surface as "try again" rather than
  retry-hammering. Restricted (login-only) works are detected and reported.
- Re-downloading a fic overwrites its file (same fic, newer text); the Mac
  watcher re-imports it to Books because the mtime changed.
- The Mac watcher **baselines** a folder on first sight: existing books are
  not auto-imported (no surprise mass-import) — "Import a Folder of Books…"
  in Settings is the explicit way to bring an existing `[Author]/[epub]`
  library (e.g. a Calibre tree) into Apple Books, batched 20 at a time.
- iOS Apple Books has no import API, so the phone flow ends with one share
  tap; the Mac side is what makes it fully automatic (Books on macOS imports
  silently on open, then Books iCloud sync fans out to all devices — the Mac
  must be signed into the iCloud account whose Books should receive them).

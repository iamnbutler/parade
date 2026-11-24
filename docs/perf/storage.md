# Storage, file I/O and writes: performance pass

November 2026. Scope: the library folder (the iCloud container), the device
database, the state files Parade writes into the library, backups and Trash,
migration. Networking/EPUB parsing and SwiftUI rendering were audited
separately.

Line numbers are as of this branch (`perf-storage`). **Fixed** items are in
this branch's PR. The rest are recommendations.

## How it was measured

- A throwaway library at `/tmp/parade-perf/lib`: 9,140 stub EPUBs across
  3,000 author folders. Nate's library and the iCloud container were never
  touched. The test library's own database
  (`library-testlibrary.sqlite`) was moved aside during the runs and put back
  afterwards.
- Folder walk: a release-built copy of `scanLibrary`'s loop, run on warm local
  APFS.
- Search index: `LibraryDatabase.swift` compiled unchanged into a small
  harness (GRDB 7 + AO3Kit) that indexes 9,000 fics in chunks of 200, as
  `runDetailsIndexing` does, then prunes 900. The same harness checks the v1
  to v2 migration.
- The app: debug build on macOS with `PARADE_TEST_LIBRARY`, launched in the
  background for 40 s with temporary `NSLog` counters on scans and details
  passes. Run against `main` and against this branch.
- No Instruments traces were taken.

| Measurement (9k fics) | Before | After |
|---|---|---|
| First search-index build (DB writes only) | 10.5 s | 0.9 s |
| Prune 900 stale entries | 2.5 s | 0.09 s |
| Full folder walk, release build, warm local disk | 150 ms | 150 ms (unchanged, but it runs less often) |
| Duplicate `normalizeLayout` listing per walk | 8 ms | 0 (only when a stray is found) |
| App launch, test library: walks run | 2 (5.4 s and 3.5 s wall) | 1 (0.3 s wall) |

The launch wall times include waiting to get back onto the main actor.
"Before" had a second walk queued behind the first, and a second details pass
after it. I haven't attributed the whole 10× to one cause, so treat these as
counts, not exact costs. An iPhone over a cold iCloud container is several
times slower than a warm Mac disk, so each avoided walk is worth more there.

### Walks and writes per action (iCloud library)

A "walk" is a full folder scan plus a details-index pass over every item on
the main actor.

| Action | Before | After |
|---|---|---|
| Launch | local-root walk + container walk + watcher-gather walk (+1 if a tab's onAppear lands mid-scan) | the same, minus the onAppear one (see R2) |
| Switch tab (iOS: Library, Favorites, Browse) | 1 walk + 1 details pass, every time | 0 (a safety-net walk at most every 5 min) |
| Toggle favorite / edit a collection | 1 small write, then the watcher echoes it: 1 walk | 1 small write + 1 small re-read |
| Close the reader | Reading.json rewritten whole if anything was pending, then echoed: 1 walk | rewritten only if this device has a newer place, and no walk |
| Change the AO3 search profile | Search.json write, then echoed: 1 walk | write, no walk |
| Another device changes Favorites/Reading/Search/Collections | 1 walk | 0 walks, re-read the file |
| Add a fic, macOS | 2 walks back to back + 1 watcher echo | 1 + echo |
| Update a fic, macOS | 2 walks + echo; chapter check unzips old and new EPUBs twice | 1 + echo; each unzipped once |
| Delete a fic | 1 walk + echo walk + 1 Backups/Trash listing | the same walks (see R1), plus 1 more Backups/Trash listing: the watcher now relists them when they change, so a delete or update on another device shows in Settings › Restore |

## Findings, ranked by impact

### 1. Search index: deleting by `itemID` scanned the whole FTS table per fic (fixed)

`Shared/Store/LibraryDatabase.swift:116` (`upsert`) and `:136` (`prune`)

- **What happened:** `DELETE FROM search WHERE itemID = ?` ran before every
  insert, and again in prune. `itemID` is `UNINDEXED` in the FTS5 table, so
  each delete read the whole index.
- **How often:** once per fic in every indexing chunk. That covers the first
  launch, a new device, every fic added or updated, and every prune after
  renames or deletes.
- **Cost:** quadratic. 9k fics: 10.5 s of writes; 50k fics would take minutes.
  The work runs on a utility task, so it's battery and disk time rather than
  UI time. It also holds the database's write lock that whole time.
- **Fix:** a `searchRow(itemID PRIMARY KEY)` table gives each fic a fixed
  rowid. The FTS row is inserted with that rowid and deleted by it. Migration
  `v2-search-rowids` rebuilds the existing index in place and keeps one row
  per fic. The harness checks the migrated search, replacement and prune.
  Result: 0.9 s and 0.09 s.

### 2. Every library screen's `onAppear` forced a full walk and details pass (fixed)

`Shared/Views/LibraryView.swift:42,163`, `BrowseView.swift:65`,
`MacRootView.swift:252`, now `AppModel.refreshIfStale` (`AppModel.swift:263`)

- **What happened:** Library, Favorites and Browse called `refreshLibrary()` +
  `buildDetailsIndex()` on every appearance.
- **How often:** every iOS tab switch, and every pop back to a list.
- **Cost:** a full walk of every provider and author folder (150 ms warm on a
  Mac; much more on an iPhone over iCloud), plus a main-actor pass over every
  item, building two cache-key strings each. In iCloud the watcher already
  reports every change, so these walks found nothing new.
- **Fix:** `refreshIfStale()`, the same rule `appBecameActive` already used.
  In iCloud it walks only if the last walk ended more than 5 minutes ago; on
  local folders, more than 15 s. It skips if a walk is running. Pull to
  refresh, Try again and Scan Now still force a walk. The lane note about
  `RefreshCoalescer` still holds: delete, add and restore still call the
  forced path.

### 3. The watcher walked the whole library for any change, including Parade's own writes (fixed)

`Shared/Store/LibraryWatcher.swift:73`, `AO3Kit/Sources/AO3Kit/LibraryChange.swift`,
`AppModel.libraryChanged` (`AppModel.swift:240`)

- **What happened:** every `NSMetadataQueryDidUpdate` called `libraryChanged()`,
  which ran a walk, a details pass and a Reading.json pull. Writing
  Favorites.txt, Collections.txt, Reading.json or Search.json comes back
  through the query about 4 s later (2 s batching + 2 s debounce), so each
  small write cost a full walk. Another device's reading-position flush cost
  every other device a walk too.
- **Fix:** the update's userInfo names the changed items. `LibraryChange.classify`
  sorts their paths into three kinds:
  - `.state`: a root state file. Re-read Favorites.txt and Collections.txt off
    the main actor, and publish only if they changed.
  - `.keptCopies`: something in Backups or Trash. Relist them.
  - `.library`: anything else. Walk.

  The first gathering, an update that names no paths, or a path outside the
  root falls back to `.all`, which is the old behaviour. The classifier has
  unit tests, including `/private/var` vs `/var` paths.

### 4. macOS: a download or update walked the library twice in a row (fixed)

`AppModel.handle` (`:1377`) and `AppModel.update` (`:1897`)

- **What happened:** `await refreshLibraryNow()` was followed by
  `#if os(macOS) await scanNow()`, and `scanNow()` is just `refreshLibraryNow()`.
  It's left over from when Scan Now also imported to Apple Books.
- **Fix:** dropped the second call.

### 5. Reading.json: rewritten whole even when nothing was newer, with unstable key order (fixed in part)

`AppModel.flushReadingPositions` (`:1250`), `positionEncoder` (`:1295`)

- **What happened:** opening a fic marks a position pending
  (`ReaderView.swift:123`), so closing the reader rewrote the whole
  Reading.json (every fic's place, on every device) and iCloud uploaded it.
  That happened even when the merged result equalled the file, for example a
  fic reopened at the place another device already wrote. The encoder didn't
  sort keys, so the same content got a different byte order each run.
- **Fix:** skip the write (still mark the rows synced) when the merged
  positions equal the file's, and encode with `.sortedKeys`.
- **Left as recommendations:**
  - Flush, pull and decode run on the main actor. That's fine at hundreds of
    fics, a hitch at reader close at tens of thousands. Move them to a
    detached task.
  - Entries for deleted fics are never removed, so the file only grows. Prune
    ids that are in neither the library nor Trash when flushing.
  - Closing the reader triggers two or three flushes (reader `onDisappear`,
    then scene `.inactive` and `.background`). The `pending` check keeps them
    cheap, but each one reads the database.

### 6. Every walk listed the root and every provider folder twice (fixed)

`AppModel.scanLibrary` (`:505`), `LibraryMigrator.normalizeLayout` (`LibraryMigrator.swift:78`)

- **What happened:** `normalizeLayout` ran before every walk. It lists the
  root, then lists each root folder in full (`ao3/` holds every author) to
  look for stray EPUBs.
- **Cost:** about 8 ms warm locally per walk. More over iCloud.
- **Fix:** the walk notices an `.epub` sitting where an author folder should
  be. Only then does it normalize and walk again. Same behaviour, one listing.

### 7. Updating a fic unzipped both EPUBs twice for the chapter check (fixed)

`AppModel.save` (`:1559`), `Organizer.place` (`Organizer.swift:39`)

- **What happened:** `save` ran `ChapterGuard.check(temp, replacing: item.url)`,
  then `place` ran it again with `replacing: dest`. For an update those are
  the same file, so it opened both ZIPs twice. If the saved copy is dataless
  on macOS, the first open also forces a download.
- **Fix:** `save` checks only when the copy being replaced sits at a different
  path than the destination.

### R1. Parade's own fic writes still echo back as a second walk (recommendation, medium)

- **What happens:** add, update, delete and restore each walk once, then the
  watcher reports the same files and walks again.
- **Suggested fix:** keep a short-lived set of paths Parade itself moved or
  wrote (place, backUp, trash, restore), each with its time. When an update
  names only those paths, within about 30 s and after a walk has finished
  since, skip it.
- **Why not done here:** it touches Organizer, KeptCopies and every call site.
  Getting it wrong hides a real change, which is the bug the
  `RefreshCoalescer` note warns about.

### R2. Launch still walks two or three times on iCloud devices (recommendation, medium)

`AppModel.init` (`:210`) and `connectCloudRoot` (`:270`)

- **What happens:**
  1. `init` walks the local root before iCloud resolves. On iCloud devices
     that's the empty Documents folder: cheap, but wasted.
  2. `connectCloudRoot` walks the container.
  3. The query's `DidFinishGathering` reports `.all` and walks again, plus
     another details pass.
- **Suggested fix:** once the container is known, ignore the gather if a walk
  started after `query.start()`. Separately, defer the first local walk until
  the container lookup returns, keeping the local walk on devices without
  iCloud.
- **Why not done here:** I couldn't verify on a fresh device whether files
  that appear during gathering always show up in the directory listing too.

### R3. Download progress makes the watcher walk over and over during a big sync (recommendation, medium)

`LibraryWatcher.swift:36,73`, `AppModel.requestDownloads` (`:602`)

- **What happens:** on a new device the scan asks iCloud to download every
  placeholder: the whole library, eagerly. Each completed download is a
  `.library` change. Every update resets the 2 s debounce, so a steady stream
  can hold the walk off. When the stream pauses, the walk runs, finds more
  downloads, and the cycle repeats.
- **Suggested fix:** when every changed path is an EPUB that already exists in
  `library`, update only that item's `isDownloaded`/date in place instead of
  walking.
- **Product question:** whether every fic should download eagerly at all
  (gigabytes on a new phone), or only on open plus the most recent N.

### R4. The details pass is whole-library work on the main actor (recommendation, low-medium)

`AppModel.runDetailsIndexing` (`:863`)

- **What happens:** every pass builds `cacheKey` strings for every item twice
  (the lookup and `validKeys`), compares dictionaries, and may prune. It runs
  after every walk, and `SearchView.onAppear` asks for it too.
- **Suggested fix:** skip the pass when the walk didn't change `library`.
  `performRefresh` already knows this from `sameGroups`.

### R5. Pruning and listing Backups and Trash (low)

`AppModel.pruneKeptCopies` (`:1797`), `KeptCopies.prune`/`list` (`KeptCopies.swift:221,106`)

- **What happens:** after every update, `prune` walks Backups and Trash in both
  roots. Then `refreshKeptCopies` walks them again, and the next launch walks
  them again. These are small trees with no file reads, so it's cheap today.
- **Suggested fix:** have `prune` return the list it built, so the second
  listing isn't needed. Prune at launch at most once a day (a stamp in
  defaults).

### R6. TagResolver rewrites its whole cache file per tag (low; local only)

`TagResolver.save` (`TagResolver.swift:82`)

- **What happens:** each resolved tag rewrites `ao3-tags.json` atomically. The
  background fandom resolve does this N times in a row. The file is in
  Application Support, so nothing syncs.
- **Suggested fix:** debounce the save, or save once per batch.

### R7. Reading positions write to SQLite on the main actor per page turn (low)

`AppModel.saveReadingPosition` (`:1229`)

- **What happens:** one WAL write per page turn (scroll mode is debounced to
  600 ms). It's local, sub-millisecond, and never syncs; Reading.json is
  batched. Fine as is. Noted only because it's on the main actor.

### Checked and fine

- **Favorites.txt and Collections.txt:** written only on a real change,
  sorted and deterministic. They're small whole-file atomic writes, which is
  the right shape for iCloud.
- **Search.json:** written only when the profile changes (the form edits a
  draft and applies it on Done). `.sortedKeys` and pretty printing, so the
  bytes are deterministic. Our own save coming back is a no-op
  (`reloadFromDisk` compares values).
- **Backups and Trash:** moves (renames), never copies, so iCloud syncs a
  rename rather than re-uploading the EPUB. Listing reads names and sizes
  only and never opens files or forces downloads.
- **LibraryMigrator.merge at launch:** a `fileExists` per legacy store; it
  lists only stores that exist.
- **The details cache** moved from a whole-file JSON in Caches to row writes
  in the database in an earlier release.
- **No `NSFileCoordinator`:** the app does no file coordination, so there's
  no coordination overhead. Correctness against concurrent iCloud writes is
  out of scope here.
- **The scan doesn't open EPUBs or force downloads:** it reads names, dates
  and the `.icloud` placeholder convention. Metadata comes from the details
  pass, cached per path and mtime in the database.

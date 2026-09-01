import Foundation
import SwiftUI
import AO3Kit
#if os(macOS)
import AppKit
#endif

/// One fic in the library. Derived entirely from the filesystem — the
/// `Author/Title.epub` tree is the single source of truth; there is no
/// separate database to drift out of sync.
struct LibraryItem: Identifiable, Hashable {
    /// Source folder the fic lives under ("ao3" today).
    let provider: String
    let author: String
    let title: String
    /// The real EPUB location (even when only an iCloud placeholder exists yet).
    let url: URL
    let date: Date
    /// False while the file is still an undownloaded ".….icloud" placeholder.
    let isDownloaded: Bool

    var id: String { provider + "/" + author + "/" + title }
}

/// How the Library list is arranged.
enum LibrarySort: String, CaseIterable, Identifiable {
    case author, title, updated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .author: "By Author"
        case .title: "By Title"
        case .updated: "Last Updated"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library: [(author: String, items: [LibraryItem])] = []
    @Published var statusLines: [String] = []
    @Published var isWorking = false
    @Published var destinationLabel = ""
    @Published var libraryError: String?
    /// A folder scan is in flight (the first one over a cold iCloud folder
    /// can take a while).
    @Published private(set) var isScanning = false
    /// Legacy stores are being moved into the current root.
    @Published private(set) var isMigrating = false
    /// EPUB metadata (tags, fandoms…) is being read in the background.
    @Published private(set) var isIndexing = false
    /// At least one full scan of the current root has finished.
    @Published private(set) var hasLoadedOnce = false

    private let client = AO3Client()
    private let defaults = UserDefaults.standard
    private(set) var destinationRoot: URL
    /// True once the library root is the app's iCloud container.
    private var inCloud = false

    #if os(macOS)
    @Published var autoImport: Bool {
        didSet { defaults.set(autoImport, forKey: Keys.autoImport) }
    }
    private var timer: Timer?
    /// relativePath → last-imported mtime, so each EPUB version reaches
    /// Apple Books exactly once.
    private var imported: [String: TimeInterval]
    #endif

    private enum Keys {
        static let folderBookmark = "destinationBookmark.v1"
        static let autoImport = "autoImport.v1"
        static let imported = "importedFiles.v1"
        static let baselinedFolder = "baselinedFolder.v1"
    }

    init() {
        #if os(macOS)
        autoImport = defaults.object(forKey: Keys.autoImport) as? Bool ?? false
        imported = defaults.dictionary(forKey: Keys.imported) as? [String: TimeInterval] ?? [:]
        #endif
        destinationRoot = Self.localRoot()
        updateDestinationLabel()
        refreshLibrary()
        Task { await self.connectCloudRoot() }
        #if os(macOS)
        startWatching()
        #else
        startAutoRefresh()
        #endif
    }

    #if os(iOS)
    private var refreshTimer: Timer?

    /// Poll the library folder while the app is in the foreground, so fics
    /// synced in through iCloud show up without a manual refresh. (The
    /// timer doesn't fire in the background; the folder is re-read the
    /// moment views reappear anyway.)
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isWorking, self.autoRefreshDue else { return }
                self.refreshLibrary()
                self.buildDetailsIndex()
            }
        }
    }
    #endif

    // MARK: - destination folder (the app's iCloud container)

    /// Where the library lives until iCloud resolves — and permanently, for
    /// devices without an iCloud account: the app's own Documents folder
    /// ("On My iPhone › Parade" / ~/Documents/Parade).
    private static func localRoot() -> URL {
        #if os(iOS)
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Parade", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Makes the app's iCloud container ("iCloud Drive › Parade") the library
    /// root and pulls every older store into it. The container lookup runs
    /// off-main because its first call can do real work.
    private func connectCloudRoot() async {
        let container = await Task.detached(priority: .userInitiated) {
            FileManager.default.url(forUbiquityContainerIdentifier: nil)?
                .appendingPathComponent("Documents", isDirectory: true)
        }.value
        if let container {
            try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            destinationRoot = container
            inCloud = true
            // New root, new first scan — the loading state should show
            // until the container has actually been read once.
            hasLoadedOnce = false
        } else {
            status("iCloud is unavailable — keeping the library on this device.")
        }
        updateDestinationLabel()
        isMigrating = true
        await migrateLegacyStores()
        isMigrating = false
        await refreshLibraryNow()
        buildDetailsIndex()
    }

    /// Every place a previous version kept the library, merged into the
    /// current root: the old "Fan Fiction" folders, (iOS) a folder connected
    /// through the old picker, and the local fallback once iCloud is up.
    /// Move-only and idempotent — see LibraryMigrator.
    private func migrateLegacyStores() async {
        var stores: [URL] = []
        #if os(iOS)
        stores.append(contentsOf: legacyPickedStores())
        stores.append(Self.localRoot().appendingPathComponent("Fan Fiction", isDirectory: true))
        #else
        let home = FileManager.default.homeDirectoryForCurrentUser
        stores.append(home.appendingPathComponent(
            "Library/Mobile Documents/com~apple~CloudDocs/Fan Fiction", isDirectory: true))
        stores.append(home.appendingPathComponent("Documents/Fan Fiction", isDirectory: true))
        #endif
        if inCloud { stores.append(Self.localRoot()) }
        for store in stores { await mergeStore(store) }
    }

    /// One store's merge. The file moves run off the main actor — a big
    /// migration over cold iCloud folders must never freeze the UI.
    private func mergeStore(_ store: URL) async {
        let root = destinationRoot
        let result = await Task.detached(priority: .userInitiated) {
            try? LibraryMigrator.merge(store: store, into: root)
        }.value
        guard let result else { return }
        // Placeholders can't move until downloaded; a later launch
        // finishes the job.
        requestDownloads(result.pendingDownloads)
        if !result.favoriteLines.isEmpty {
            favorites.formUnion(Self.favoriteIDs(at: favoritesFile))
            favorites.formUnion(result.favoriteLines.map(Self.normalizeFavoriteID))
            saveFavorites()
        }
        if result.movedEPUBs > 0 {
            status("Moved \(result.movedEPUBs) fic\(result.movedEPUBs == 1 ? "" : "s") into \(destinationLabel)")
        }
        // A fully drained legacy folder disappears (never Documents itself).
        if store.lastPathComponent != "Documents",
           store.standardizedFileURL.path != root.standardizedFileURL.path {
            await Task.detached {
                if LibraryMigrator.isEffectivelyEmpty(store) {
                    try? FileManager.default.removeItem(at: store)
                }
            }.value
        }
    }

    #if os(iOS)
    /// The folder a previous version connected through the folder picker.
    /// Its fics are pulled into the container, then the bookmark is dropped.
    private func legacyPickedStores() -> [URL] {
        guard inCloud, let data = defaults.data(forKey: Keys.folderBookmark) else { return [] }
        defaults.removeObject(forKey: Keys.folderBookmark)
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return [] }
        return [url]
    }
    #endif

    private func updateDestinationLabel() {
        if inCloud {
            destinationLabel = "iCloud Drive › Parade"
        } else {
            #if os(iOS)
            destinationLabel = "On My iPhone › Parade"
            #else
            destinationLabel = "Documents › Parade"
            #endif
        }
    }

    // MARK: - library (filesystem is the source of truth)

    /// Snapshot of one background pass over the library folder.
    private struct LibraryScan {
        var groups: [(author: String, items: [LibraryItem])] = []
        var favorites: Set<String> = []
        var placeholders: [URL] = []
        var error: String?
    }

    private var refreshTask: Task<Void, Never>?
    /// Placeholders whose download has already been requested this run, so a
    /// large still-syncing library isn't re-requested on every refresh.
    private var requestedDownloads: Set<String> = []
    private var lastRefreshEnd = Date.distantPast
    private var lastScanDuration: TimeInterval = 0

    /// Timers poll every 15 seconds, but a huge library shouldn't be
    /// rescanned back-to-back — scans stay spaced at 10× their own cost.
    var autoRefreshDue: Bool {
        Date().timeIntervalSince(lastRefreshEnd) >= max(15, lastScanDuration * 10)
    }

    /// Schedules a background rescan; results land back on the main actor.
    /// Cheap to call often — concurrent calls share one scan.
    func refreshLibrary() {
        Task { await self.refreshLibraryNow() }
    }

    func refreshLibraryNow() async {
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await self.performRefresh() }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    /// Bumped per scan (and on completion) so partial results from a
    /// superseded scan can never overwrite a newer library.
    private var scanGeneration = 0

    private func applyPartialScan(_ groups: [(author: String, items: [LibraryItem])], generation: Int) {
        guard scanGeneration == generation else { return }
        library = groups
        flatCache = [:]
        fandomCache = nil
    }

    private func performRefresh() async {
        let root = destinationRoot
        scanGeneration += 1
        let gen = scanGeneration
        isScanning = true
        defer { isScanning = false }
        let started = Date()
        // While the visible library is empty (first launch, or the root just
        // moved), results stream in as the walk finds them instead of
        // holding everything until the whole folder has been read.
        var onPartial: (@Sendable ([(author: String, items: [LibraryItem])]) -> Void)?
        if library.isEmpty {
            onPartial = { [weak self] groups in
                Task<Void, Never> {
                    await self?.applyPartialScan(groups, generation: gen)
                }
            }
        }
        let scan = await Task.detached(priority: .userInitiated) {
            Self.scanLibrary(root: root, onPartial: onPartial)
        }.value
        scanGeneration += 1  // straggler partials become no-ops
        lastScanDuration = Date().timeIntervalSince(started)
        lastRefreshEnd = Date()
        guard root.path == destinationRoot.path else { return }  // root moved mid-scan
        if let error = scan.error {
            // Don't swallow this: on macOS a denied Files-and-Folders / iCloud
            // Drive permission looks exactly like an empty folder otherwise.
            libraryError = error
            library = []
            return
        }
        libraryError = nil
        favorites = scan.favorites
        library = scan.groups
        flatCache = [:]
        fandomCache = nil
        hasLoadedOnce = true
        requestDownloads(scan.placeholders)
    }

    /// The full folder walk. Runs off the main actor — launch and refresh
    /// must never block the UI on filesystem (or cold iCloud metadata) work.
    private nonisolated static func scanLibrary(
        root: URL,
        onPartial: (@Sendable ([(author: String, items: [LibraryItem])]) -> Void)? = nil
    ) -> LibraryScan {
        // Self-heal stray drops (an author folder at the root, etc.) so
        // nothing in the folder can exist undetected.
        LibraryMigrator.normalizeLayout(root: root)
        let fm = FileManager.default
        var scan = LibraryScan()
        let favoritesFile = root.appendingPathComponent("Favorites.txt")
        if fm.fileExists(atPath: root.appendingPathComponent(".Favorites.txt.icloud").path) {
            scan.placeholders.append(favoritesFile)
        }
        scan.favorites = favoriteIDs(at: favoritesFile)

        let providerDirs: [URL]
        do {
            providerDirs = try fm.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])
        } catch {
            scan.error = "Can't read \(root.path): \(error.localizedDescription)"
            return scan
        }

        // <root>/<provider>/<Author>/<Title>.epub — authors merge across
        // providers into one list per author name.
        var byAuthor: [String: [LibraryItem]] = [:]
        var lastEmit = Date()
        for providerDir in providerDirs {
            guard (try? providerDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  providerDir.lastPathComponent != Organizer.backupsFolder else { continue }
            let provider = providerDir.lastPathComponent
            let authorDirs = (try? fm.contentsOfDirectory(
                at: providerDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for dir in authorDirs {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      dir.lastPathComponent != Organizer.backupsFolder else { continue }
                let files = (try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [])) ?? []
                for file in files {
                    guard let item = Self.libraryItem(for: file, provider: provider, author: dir.lastPathComponent)
                    else { continue }
                    byAuthor[item.author, default: []].append(item)
                    if !item.isDownloaded {
                        scan.placeholders.append(item.url)
                    }
                }
                if let onPartial, !byAuthor.isEmpty,
                   Date().timeIntervalSince(lastEmit) > 0.35 {
                    lastEmit = Date()
                    onPartial(Self.sortedGroups(byAuthor))
                }
            }
        }
        scan.groups = Self.sortedGroups(byAuthor)
        return scan
    }

    private nonisolated static func sortedGroups(
        _ byAuthor: [String: [LibraryItem]]
    ) -> [(author: String, items: [LibraryItem])] {
        byAuthor
            .map { author, items in (author: author, items: items.sorted { $0.date > $1.date }) }
            .sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
    }

    /// Asks iCloud to materialize placeholders so they become readable —
    /// once per file per app run, off the main thread.
    private func requestDownloads(_ urls: [URL]) {
        let fresh = urls.filter { requestedDownloads.insert($0.path).inserted }
        guard !fresh.isEmpty else { return }
        Task.detached(priority: .utility) {
            for url in fresh {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
    }

    private nonisolated static func libraryItem(for file: URL, provider: String, author: String) -> LibraryItem? {
        let name = file.lastPathComponent
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if name.lowercased().hasSuffix(".epub") {
            return LibraryItem(
                provider: provider, author: author,
                title: file.deletingPathExtension().lastPathComponent,
                url: file, date: date, isDownloaded: true)
        }
        // iCloud placeholder: ".Title.epub.icloud" stands in for "Title.epub".
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            let realName = String(name.dropFirst().dropLast(".icloud".count))
            guard realName.lowercased().hasSuffix(".epub") else { return nil }
            let realURL = file.deletingLastPathComponent().appendingPathComponent(realName)
            return LibraryItem(
                provider: provider, author: author,
                title: (realName as NSString).deletingPathExtension,
                url: realURL, date: date, isDownloaded: false)
        }
        return nil
    }

    // MARK: - sorted views of the library (cached, never per-render)

    private var flatCache: [LibrarySort: [LibraryItem]] = [:]
    private var fandomCache: [(name: String, items: [LibraryItem])]?

    /// Every item in the given order — computed once per library/details
    /// change so list bodies never re-sort 100k items per render.
    func flatItems(_ sort: LibrarySort) -> [LibraryItem] {
        if let cached = flatCache[sort] { return cached }
        let all = library.flatMap(\.items)
        let sorted: [LibraryItem]
        switch sort {
        case .author:
            sorted = all  // library groups are already author-ordered
        case .title:
            // Precompute keys: a localized compare inside sort() is O(n log n)
            // expensive comparisons; lowercasing once per item is O(n).
            sorted = all.map { ($0.title.lowercased(), $0) }
                .sorted { $0.0 < $1.0 }.map(\.1)
        case .updated:
            sorted = all.map { (contentDate($0), $0) }
                .sorted { $0.0 > $1.0 }.map(\.1)
        }
        flatCache[sort] = sorted
        return sorted
    }

    // MARK: - fic details (parsed out of the EPUB itself)

    /// item.id → metadata, for whatever has been parsed so far. Series
    /// grouping and search read from this; it fills in the background.
    @Published private(set) var detailsIndex: [String: WorkDetails] = [:]
    /// "path|mtime" → details. Persisted to Caches so a library is parsed
    /// once ever, not once per launch.
    private var detailsCache: [String: WorkDetails] = [:]
    private var detailsCacheLoaded = false
    private var lastCacheSave = Date.distantPast
    private var indexTask: Task<Void, Never>?

    private nonisolated static var detailsCacheFile: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("parade-details-cache.json")
    }

    private nonisolated static func cacheKey(_ item: LibraryItem) -> String {
        item.url.path + "|" + String(item.date.timeIntervalSince1970)
    }

    private func didUpdateDetails() {
        flatCache[.updated] = nil
        fandomCache = nil
    }

    /// Rich metadata for one fic, read from inside its EPUB (summary, tags,
    /// series, stats…). Cached per file version.
    func details(for item: LibraryItem) async -> WorkDetails? {
        let key = Self.cacheKey(item)
        if let hit = detailsCache[key] {
            guard hit != WorkDetails() else { return nil }  // known unparseable
            detailsIndex[item.id] = hit
            return hit
        }
        let url = item.url
        let parsed = await Task.detached(priority: .userInitiated) {
            try? EPUBDetailsParser.parse(epubAt: url)
        }.value
        if let parsed {
            detailsCache[key] = parsed
            detailsIndex[item.id] = parsed
            didUpdateDetails()
        }
        return parsed
    }

    /// Walks the library parsing any EPUBs not yet in the index — off the
    /// main actor, in batches, against the persistent cache.
    func buildDetailsIndex() {
        guard indexTask == nil else { return }
        indexTask = Task { [weak self] in
            self?.isIndexing = true
            await self?.runDetailsIndexing()
            self?.isIndexing = false
            self?.indexTask = nil
        }
    }

    private func runDetailsIndexing() async {
        if !detailsCacheLoaded {
            detailsCacheLoaded = true
            let file = Self.detailsCacheFile
            let loaded = await Task.detached(priority: .utility) { () -> [String: WorkDetails] in
                guard let data = try? Data(contentsOf: file) else { return [:] }
                return (try? JSONDecoder().decode([String: WorkDetails].self, from: data)) ?? [:]
            }.value
            detailsCache.merge(loaded) { current, _ in current }
        }
        let items = library.flatMap(\.items).filter(\.isDownloaded)

        // Everything the cache already knows lands in one batch. An empty
        // WorkDetails is the "known unparseable" sentinel — cached so a bad
        // file is attempted once ever, but never surfaced.
        var fromCache: [String: WorkDetails] = [:]
        var toParse: [LibraryItem] = []
        for item in items {
            if let hit = detailsCache[Self.cacheKey(item)] {
                if hit != WorkDetails(), detailsIndex[item.id] == nil { fromCache[item.id] = hit }
            } else {
                toParse.append(item)
            }
        }
        if !fromCache.isEmpty {
            detailsIndex.merge(fromCache) { _, new in new }
            didUpdateDetails()
        }

        // Parse the rest in chunks off-main; publish per chunk so the UI
        // enriches progressively without 100k separate invalidations.
        for start in stride(from: 0, to: toParse.count, by: 200) {
            if Task.isCancelled { break }
            let chunk = Array(toParse[start..<min(start + 200, toParse.count)])
            let parsed = await Task.detached(priority: .utility) { () -> [(id: String, key: String, details: WorkDetails)] in
                chunk.map { item in
                    (item.id, Self.cacheKey(item), (try? EPUBDetailsParser.parse(epubAt: item.url)) ?? WorkDetails())
                }
            }.value
            var enriched = false
            for entry in parsed {
                detailsCache[entry.key] = entry.details
                if entry.details != WorkDetails() {
                    detailsIndex[entry.id] = entry.details
                    enriched = true
                }
            }
            if enriched { didUpdateDetails() }
            saveDetailsCache(throttled: true)
        }

        // Final save, dropping cache entries for files that no longer exist
        // at that version so the cache can't grow without bound.
        let validKeys = Set(items.map(Self.cacheKey))
        detailsCache = detailsCache.filter { validKeys.contains($0.key) }
        saveDetailsCache(throttled: false)
    }

    private func saveDetailsCache(throttled: Bool) {
        if throttled, Date().timeIntervalSince(lastCacheSave) < 10 { return }
        lastCacheSave = Date()
        let snapshot = detailsCache
        let file = Self.detailsCacheFile
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    /// Fics grouped by fandom (a fic in several fandoms appears in each).
    /// Only as complete as the details index; cached between changes.
    var fandomGroups: [(name: String, items: [LibraryItem])] {
        if let cached = fandomCache { return cached }
        var byFandom: [String: [LibraryItem]] = [:]
        for item in library.flatMap(\.items) {
            guard let details = detailsIndex[item.id] else { continue }
            for fandom in details.fandoms {
                byFandom[fandom, default: []].append(item)
            }
        }
        let groups = byFandom
            .map { name, items in
                (name: name, items: items.sorted {
                    ($0.author.lowercased(), $0.title.lowercased()) < ($1.author.lowercased(), $1.title.lowercased())
                })
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        fandomCache = groups
        return groups
    }

    /// Search across title, author, and (once indexed) series, fandoms,
    /// tags, relationships, and characters. Allocation-free per item —
    /// this runs library-size times per keystroke.
    func item(_ item: LibraryItem, matches query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(query) { return true }
        if item.author.localizedCaseInsensitiveContains(query) { return true }
        guard let d = detailsIndex[item.id] else { return false }
        if let series = d.seriesName, series.localizedCaseInsensitiveContains(query) { return true }
        for list in [d.fandoms, d.additionalTags, d.relationships, d.characters, d.categories, d.rating, d.warnings] {
            for value in list where value.localizedCaseInsensitiveContains(query) { return true }
        }
        return false
    }

    func delete(_ item: LibraryItem) {
        let fm = FileManager.default
        try? fm.removeItem(at: item.url)
        let dir = item.url.deletingLastPathComponent()
        if let remaining = try? fm.contentsOfDirectory(atPath: dir.path), remaining.isEmpty {
            try? fm.removeItem(at: dir)
        }
        #if os(macOS)
        imported.removeValue(forKey: relativePath(of: item.url))
        persistImported()
        #endif
        if favorites.remove(item.id) != nil { saveFavorites() }
        // Drop it from the visible list immediately; the background rescan
        // confirms.
        library = library.compactMap { group in
            let items = group.items.filter { $0.id != item.id }
            return items.isEmpty ? nil : (author: group.author, items: items)
        }
        flatCache = [:]
        fandomCache = nil
        refreshLibrary()
    }

    // MARK: - favorites

    /// Favorited fic ids. Backed by Favorites.txt in the library folder
    /// (one Author/Title per line), so it syncs through iCloud with the
    /// fics themselves and can be edited by hand.
    @Published private(set) var favorites: Set<String> = []

    private var favoritesFile: URL { destinationRoot.appendingPathComponent("Favorites.txt") }

    var favoriteItems: [LibraryItem] {
        flatItems(.title).filter { favorites.contains($0.id) }
    }

    func isFavorite(_ item: LibraryItem) -> Bool { favorites.contains(item.id) }

    func toggleFavorite(_ item: LibraryItem) {
        if favorites.remove(item.id) == nil { favorites.insert(item.id) }
        saveFavorites()
    }

    /// Reads a Favorites.txt into normalized ids. Also used by the
    /// background scan, so it must stay off-actor.
    private nonisolated static func favoriteIDs(at file: URL) -> Set<String> {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return Set(
            text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .map(normalizeFavoriteID))
    }

    /// Favorites written before providers existed were "Author/Title";
    /// current ids are "provider/Author/Title".
    private nonisolated static func normalizeFavoriteID(_ line: String) -> String {
        line.components(separatedBy: "/").count == 2 ? Organizer.ao3 + "/" + line : line
    }

    private func saveFavorites() {
        let text = favorites.sorted().joined(separator: "\n") + "\n"
        try? text.write(to: favoritesFile, atomically: true, encoding: .utf8)
    }

    // MARK: - download pipeline

    func handle(_ text: String) async {
        guard !isWorking else { return }
        guard let link = AO3Link(text: text) else {
            status("⚠️ \(AO3Error.notAnAO3Link.localizedDescription)")
            return
        }
        isWorking = true
        statusLines = []
        defer { isWorking = false }

        do {
            let ids = try await client.workIDs(for: link)
            if case .series = link {
                status("Series with \(ids.count) work\(ids.count == 1 ? "" : "s")…")
            }
            for (index, id) in ids.enumerated() {
                if index > 0 {
                    // Be polite to AO3 between series downloads.
                    try? await Task.sleep(for: .seconds(1.5))
                }
                do {
                    try await downloadWork(id: id)
                } catch {
                    status("⚠️ Work \(id): \(error.localizedDescription)")
                }
            }
        } catch {
            status("⚠️ \(error.localizedDescription)")
        }
        await refreshLibraryNow()
        #if os(macOS)
        await scanNow()
        #endif
    }

    private func downloadWork(id: Int) async throws {
        status("Fetching work \(id)…")
        let work = try await client.fetchWork(id: id)
        status("Downloading “\(work.title)” by \(work.authorLabel)…")
        let temp = try await client.downloadEPUB(work)
        let dest = try Organizer(root: destinationRoot).place(temp, for: work)
        status("✓ Saved \(relativePath(of: dest))")
    }

    // MARK: - fic updates (against AO3)

    /// Item ids whose work changed on AO3 since the local EPUB. Filled by
    /// checkForUpdates(); cleared per fic when it's re-downloaded.
    @Published private(set) var updatesAvailable: Set<String> = []
    @Published private(set) var isCheckingUpdates = false

    func hasUpdate(_ item: LibraryItem) -> Bool { updatesAvailable.contains(item.id) }

    /// The fic's last content change (from inside the EPUB), for the
    /// Last Updated sort; falls back to the file date until parsed.
    func contentDate(_ item: LibraryItem) -> Date {
        detailsIndex[item.id]?.latestDate ?? item.date
    }

    /// Asks AO3 whether each fic changed since its EPUB was made, comparing
    /// the download link's updated_at stamp to the date inside the EPUB.
    /// One request per fic, politely spaced — explicit action, never automatic.
    func checkForUpdates() async {
        guard !isCheckingUpdates, !isWorking else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        await refreshLibraryNow()
        let items = library.flatMap(\.items).filter(\.isDownloaded)
        status("Checking \(items.count) fic\(items.count == 1 ? "" : "s") against AO3…")
        var checked = 0, found = 0
        for item in items {
            guard let d = await details(for: item),
                  let workID = d.workID,
                  let local = d.latestDate else { continue }
            if checked > 0 { try? await Task.sleep(for: .seconds(1.5)) }
            do {
                let info = try await client.fetchWork(id: workID)
                checked += 1
                // The EPUB's date is day-resolution; only a strictly later
                // day counts, so a same-day download isn't a false positive.
                if let ts = info.updatedAt,
                   Date(timeIntervalSince1970: TimeInterval(ts)).timeIntervalSince(local) >= 86_400 {
                    updatesAvailable.insert(item.id)
                    found += 1
                }
                if checked % 10 == 0 { status("…\(checked)/\(items.count) checked") }
            } catch AO3Error.rateLimited {
                status("⚠️ AO3 is rate-limiting — stopped at \(checked)/\(items.count). Try again later.")
                break
            } catch {
                // One unreadable work shouldn't stop the sweep.
            }
        }
        status(found == 0
            ? "✓ Checked \(checked) fic\(checked == 1 ? "" : "s") — everything is current"
            : "✓ \(found) update\(found == 1 ? "" : "s") available")
    }

    /// Re-downloads one fic from AO3. The old EPUB is kept in Backups/.
    func update(_ item: LibraryItem) async {
        guard !isWorking else { return }
        var workID = detailsIndex[item.id]?.workID
        if workID == nil { workID = (await details(for: item))?.workID }
        guard let workID else {
            status("⚠️ “\(item.title)” has no AO3 work link inside it")
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await downloadWork(id: workID)
            updatesAvailable.remove(item.id)
        } catch {
            status("⚠️ \(error.localizedDescription)")
        }
        await refreshLibraryNow()
        #if os(macOS)
        await scanNow()
        #endif
    }

    func status(_ line: String) {
        statusLines.append(line)
        if statusLines.count > 8 { statusLines.removeFirst() }
    }

    private func relativePath(of url: URL) -> String {
        url.path.replacingOccurrences(of: destinationRoot.path + "/", with: "")
    }

    // MARK: - Apple Books (macOS)

    #if os(macOS)
    /// Sends one fic to Apple Books (silent import) and remembers it.
    func addToBooks(_ item: LibraryItem) {
        guard sendToBooks([item.url]) else { return }
        markImported(item.url)
        persistImported()
        status("→ Books: \(item.title)")
    }

    @discardableResult
    private func sendToBooks(_ urls: [URL]) -> Bool {
        guard let books = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iBooksX") else {
            status("⚠️ Apple Books not found")
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.open(urls, withApplicationAt: books, configuration: config)
        return true
    }

    /// "Opening" an EPUB is the only supported way into Books' library, but it
    /// also opens a reader window per book — close them so a bulk import
    /// doesn't bury the user in 300 windows. Best-effort AppleScript (the
    /// first use prompts once to allow controlling Books).
    private func closeBooksWindows() {
        let script = NSAppleScript(source: #"tell application "Books" to close every window"#)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }

    private func markImported(_ url: URL) {
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        imported[relativePath(of: url)] = mtime
    }

    private func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.autoRefreshDue else { return }
                self.scan()
            }
        }
        scan()
    }

    /// One poll of the library folder: refresh the view, and auto-import
    /// EPUBs that arrived or changed since the last look.
    func scan() {
        Task { await self.scanNow() }
    }

    func scanNow() async {
        await refreshLibraryNow()
        let downloaded = library.flatMap(\.items).filter(\.isDownloaded)

        // First look at a folder: baseline its existing contents as already
        // imported, so switching folders never mass-imports by surprise —
        // "Import a Folder of Books…" is the explicit way to do that.
        if defaults.string(forKey: Keys.baselinedFolder) != destinationRoot.path {
            imported = [:]
            downloaded.forEach { markImported($0.url) }
            persistImported()
            defaults.set(destinationRoot.path, forKey: Keys.baselinedFolder)
            if !downloaded.isEmpty {
                status("Found \(downloaded.count) existing book\(downloaded.count == 1 ? "" : "s") — use “Import a Folder of Books…” to send them to Apple Books.")
            }
            return
        }

        guard autoImport else { return }
        let currentPaths = Set(downloaded.map { relativePath(of: $0.url) })
        let fresh = downloaded.filter { item in
            let mtime = item.date.timeIntervalSince1970
            if let seen = imported[relativePath(of: item.url)], seen >= mtime { return false }
            return true
        }

        // Auto-import is for single-URL downloads (pasted here, or synced in
        // from the phone one fic at a time). A large batch landing at once —
        // an initial iCloud sync, a folder copied in by hand — is bulk:
        // baseline it and leave Books to the explicit "Import All".
        if fresh.count > 20 {
            fresh.forEach { markImported($0.url) }
            imported = imported.filter { currentPaths.contains($0.key) }
            persistImported()
            status("Found \(fresh.count) new fics — bulk arrival, skipping auto-import. Use “Import All to Apple Books” to send them.")
            return
        }

        var imports = 0
        for item in fresh {
            guard sendToBooks([item.url]) else { return }
            markImported(item.url)
            status("→ Books: \(item.title)")
            imports += 1
        }
        if imports > 0 {
            // Don't leave reader windows piling up on an unattended Mac.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                self.closeBooksWindows()
            }
        }
        // Forget deleted files so a future re-download imports again.
        imported = imported.filter { currentPaths.contains($0.key) }
        persistImported()
    }

    /// Merges an existing `[Author]/…/[epub]` tree (e.g. a Calibre library)
    /// INTO the library folder — the folder is the source of truth, so
    /// getting fics into Parade (and from there into Books, via the watcher)
    /// means getting the files into the folder. Files are moved; duplicates
    /// already in the library are left in place at the source.
    func mergeFolder(_ folder: URL) async {
        let fm = FileManager.default
        var moved = 0, skipped = 0, failed = 0
        guard let enumerator = fm.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            status("⚠️ Can't read \(folder.lastPathComponent)")
            return
        }
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "epub" {
            // Author = the top-level folder the epub sits under (Calibre nests
            // Author/Title/file.epub — the first component is still the author).
            let relParts = url.path
                .replacingOccurrences(of: folder.path + "/", with: "")
                .components(separatedBy: "/")
            let author = relParts.count > 1 ? relParts[0] : "Unknown Author"
            if author == Organizer.backupsFolder { skipped += 1; continue }
            let authorDir = destinationRoot
                .appendingPathComponent(Organizer.ao3, isDirectory: true)
                .appendingPathComponent(Organizer.sanitize(author), isDirectory: true)
            let dest = authorDir.appendingPathComponent(url.lastPathComponent)
            if fm.fileExists(atPath: dest.path) {
                skipped += 1
                continue
            }
            do {
                try fm.createDirectory(at: authorDir, withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: url, to: dest)
                } catch {
                    // Cross-volume moves fail; copy then remove.
                    try fm.copyItem(at: url, to: dest)
                    try? fm.removeItem(at: url)
                }
                // Baseline the file so the watcher does NOT auto-import it —
                // Books auto-import is only for single-URL downloads; bulk
                // goes through the explicit "Import All to Apple Books".
                markImported(dest)
                moved += 1
            } catch {
                failed += 1
            }
        }
        persistImported()
        var summary = "✓ Merged \(moved) fic\(moved == 1 ? "" : "s") into the library"
        if skipped > 0 { summary += ", \(skipped) already there" }
        if failed > 0 { summary += ", \(failed) failed" }
        status(summary)
        if moved > 0 {
            status("Use “Import All to Apple Books” to send them to Books.")
        }
        refreshLibrary()
    }

    /// Explicit bulk action: send every EPUB in the library to Apple Books,
    /// batched, tidying the reader windows Books opens along the way.
    func importAllToBooks() async {
        await refreshLibraryNow()
        let epubs = library.flatMap(\.items).filter(\.isDownloaded).map(\.url)
        guard !epubs.isEmpty else {
            status("⚠️ Library is empty")
            return
        }
        status("Importing \(epubs.count) book\(epubs.count == 1 ? "" : "s") to Apple Books…")
        for start in stride(from: 0, to: epubs.count, by: 20) {
            let batch = Array(epubs[start..<min(start + 20, epubs.count)])
            guard sendToBooks(batch) else { return }
            try? await Task.sleep(for: .milliseconds(1500))
            closeBooksWindows()
        }
        epubs.forEach { markImported($0) }
        persistImported()
        status("✓ Sent \(epubs.count) book\(epubs.count == 1 ? "" : "s") to Apple Books")
    }

    private func persistImported() {
        defaults.set(imported, forKey: Keys.imported)
    }
    #endif
}

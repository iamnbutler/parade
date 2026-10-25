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
    /// Last write — when this version of the EPUB was saved.
    let date: Date
    /// When the fic first arrived (file creation date; updates keep it).
    let added: Date
    /// False while the file is still an undownloaded ".….icloud" placeholder.
    let isDownloaded: Bool

    var id: String { provider + "/" + author + "/" + title }
}

/// How the Library list is arranged.
enum LibrarySort: String, CaseIterable, Identifiable {
    case author, title, series, fandom, added, updated
    var id: String { rawValue }
    var label: String {
        switch self {
        case .author: "By Author"
        case .title: "By Title"
        case .series: "By Series"
        case .fandom: "By Fandom"
        case .added: "Date Added"
        case .updated: "Last Updated"
        }
    }
    /// Sorts shown as sections (author / series headers) rather than flat.
    var isGrouped: Bool { self == .author || self == .series || self == .fandom }
    /// Grouped sorts whose sections mix authors, so rows name theirs.
    var mixesAuthors: Bool { self == .series || self == .fandom }
}

/// A browsable kind of AO3 metadata — each value becomes a drill-in list.
enum TagKind: String, CaseIterable, Identifiable, Hashable {
    case fandoms, series, relationships, characters, tags
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fandoms: "Fandoms"
        case .series: "Series"
        case .relationships: "Relationships"
        case .characters: "Characters"
        case .tags: "Tags"
        }
    }

    /// One of them, lowercased: "fandom", "series".
    var singular: String {
        switch self {
        case .fandoms: "fandom"
        case .series: "series"
        case .relationships: "relationship"
        case .characters: "character"
        case .tags: "tag"
        }
    }

    func values(in d: WorkDetails) -> [String] {
        switch self {
        case .fandoms: d.fandoms
        case .series: d.seriesName.map { [$0] } ?? []
        case .relationships: d.relationships
        case .characters: d.characters
        case .tags: d.additionalTags
        }
    }
}

/// One tag (or fandom, series…), as a navigation value.
struct TagSelection: Hashable {
    let kind: TagKind
    let name: String
}

/// One user collection, as a navigation value.
struct CollectionSelection: Hashable {
    let name: String
}

/// Which list a fic was opened from — so the detail screen can page
/// through its neighbors in the same order.
enum FicList: Hashable {
    case library(LibrarySort, query: String)
    case favorites(query: String)
    case tag(TagSelection, query: String)
    case collection(String, query: String)
    case toRead(query: String)

    /// The list's name, as a running head says it: "Library, 3 of 26".
    var title: String {
        switch self {
        case .library: "Library"
        case .favorites: "Favorites"
        case .tag(let tag, _): tag.name
        case .collection(let name, _): name
        case .toRead: "To Read"
        }
    }
}

/// A place in a fic: the block a reader had at the top of the screen,
/// counted within its section so a fic that gains a chapter keeps its place.
struct ReadingPosition: Codable, Equatable {
    var section: Int
    var block: Int
    /// When it was last read (absent in positions saved before this).
    var date: Date?

    func samePlace(as other: ReadingPosition?) -> Bool {
        other.map { $0.section == section && $0.block == block } ?? false
    }
}

/// Navigation value for opening one fic from a list.
struct FicRoute: Hashable {
    let item: LibraryItem
    let list: FicList
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
    private let defaults: UserDefaults

    /// Debug builds only: `PARADE_TEST_LIBRARY=/some/folder` runs the app
    /// against that folder instead of the iCloud library — no migration,
    /// separate settings and caches, nothing sent to Apple Books — so it can
    /// be exercised with fixtures without touching a real library.
    nonisolated static let testLibrary: URL? = {
        #if DEBUG
        guard let path = ProcessInfo.processInfo.environment["PARADE_TEST_LIBRARY"],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
        #else
        return nil
        #endif
    }()

    /// Where settings live — the views' @AppStorage too. A test library
    /// gets its own suite so testing never touches real preferences.
    nonisolated static var settingsStore: UserDefaults {
        testLibrary == nil
            ? .standard
            : UserDefaults(suiteName: "com.natebutler.parade.testlibrary") ?? .standard
    }
    private(set) var destinationRoot: URL
    /// True once the library root is the app's iCloud container.
    @Published private(set) var inCloud = false

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
        static let updatesAvailable = "updatesAvailable.v1"
        static let recentSearches = "recentSearches.v1"
    }

    init() {
        defaults = Self.settingsStore
        #if os(macOS)
        autoImport = defaults.object(forKey: Keys.autoImport) as? Bool ?? false
        imported = defaults.dictionary(forKey: Keys.imported) as? [String: TimeInterval] ?? [:]
        #endif
        updatesAvailable = Set(defaults.stringArray(forKey: Keys.updatesAvailable) ?? [])
        recentSearches = defaults.stringArray(forKey: Keys.recentSearches) ?? []
        destinationRoot = Self.testLibrary ?? Self.localRoot()
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
        if let test = Self.testLibrary {
            try? FileManager.default.createDirectory(at: test, withIntermediateDirectories: true)
            destinationRoot = test
            destinationLabel = "Test library › \(test.path)"
            await refreshLibraryNow()
            buildDetailsIndex()
            return
        }
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
        var collections = FicCollections()
        var placeholders: [URL] = []
        var toRead: [LibraryItem] = []
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
        refreshLastRead()
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
        invalidateDerived()
    }

    /// Bumped on every local favorites / collections write, so a scan that
    /// read the files before the write can't roll the change back.
    private var localEditStamp = 0

    private func performRefresh() async {
        let root = destinationRoot
        let editStampAtStart = localEditStamp
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
        if localEditStamp == editStampAtStart {
            favorites = scan.favorites
            collections = scan.collections
        }
        // An unchanged library isn't republished: every publish redraws the
        // lists and pager, and the iOS refresh runs every 15 seconds.
        if !Self.sameGroups(library, scan.groups) {
            library = scan.groups
            invalidateDerived()
        }
        if toRead != scan.toRead {
            toRead = scan.toRead
            idCache = nil
        }
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
        let collectionsFile = root.appendingPathComponent(Self.collectionsFileName)
        if fm.fileExists(atPath: root.appendingPathComponent(".\(Self.collectionsFileName).icloud").path) {
            scan.placeholders.append(collectionsFile)
        }
        scan.collections = (try? String(contentsOf: collectionsFile, encoding: .utf8)).map(FicCollections.init(text:)) ?? FicCollections()

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
                  providerDir.lastPathComponent != Organizer.backupsFolder,
                  providerDir.lastPathComponent != Organizer.toReadFolder else { continue }
            let provider = providerDir.lastPathComponent
            let authorDirs = (try? fm.contentsOfDirectory(
                at: providerDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for dir in authorDirs {
                guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      dir.lastPathComponent != Organizer.backupsFolder else { continue }
                let files = (try? fm.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                    options: [])) ?? []
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
        // To Read is a small library of its own, laid out the same way.
        let toReadRoot = root.appendingPathComponent(Organizer.toReadFolder, isDirectory: true)
        if fm.fileExists(atPath: toReadRoot.path) {
            let inner = scanLibrary(root: toReadRoot)
            scan.toRead = inner.groups.flatMap(\.items).sorted { $0.added > $1.added }
            scan.placeholders += inner.placeholders
        }
        return scan
    }

    private nonisolated static func sameGroups(
        _ a: [(author: String, items: [LibraryItem])], _ b: [(author: String, items: [LibraryItem])]
    ) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.author == $1.author && $0.items == $1.items }
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
        let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        let date = values?.contentModificationDate ?? .distantPast
        let added = values?.creationDate ?? date
        if name.lowercased().hasSuffix(".epub") {
            return LibraryItem(
                provider: provider, author: author,
                title: file.deletingPathExtension().lastPathComponent,
                url: file, date: date, added: added, isDownloaded: true)
        }
        // iCloud placeholder: ".Title.epub.icloud" stands in for "Title.epub".
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            let realName = String(name.dropFirst().dropLast(".icloud".count))
            guard realName.lowercased().hasSuffix(".epub") else { return nil }
            let realURL = file.deletingLastPathComponent().appendingPathComponent(realName)
            return LibraryItem(
                provider: provider, author: author,
                title: (realName as NSString).deletingPathExtension,
                url: realURL, date: date, added: added, isDownloaded: false)
        }
        return nil
    }

    // MARK: - sorted views of the library (cached, never per-render)

    private var flatCache: [LibrarySort: [LibraryItem]] = [:]
    private var sectionCache: [LibrarySort: [(name: String, items: [LibraryItem])]] = [:]
    private var tagCache: [TagKind: [(name: String, items: [LibraryItem])]] = [:]
    private var idCache: [String: LibraryItem]?

    /// Drops every derived view of the library. `detailsOnly` keeps the
    /// orderings that don't read EPUB metadata.
    private func invalidateDerived(detailsOnly: Bool = false) {
        if detailsOnly {
            for sort in [LibrarySort.updated, .series, .fandom] {
                flatCache[sort] = nil
                sectionCache[sort] = nil
            }
        } else {
            flatCache = [:]
            sectionCache = [:]
            idCache = nil
        }
        tagCache = [:]
        vocabularyCache = nil
    }

    /// Every item in the given order — computed once per library/details
    /// change so list bodies never re-sort 100k items per render.
    func flatItems(_ sort: LibrarySort) -> [LibraryItem] {
        if let cached = flatCache[sort] { return cached }
        let sorted: [LibraryItem]
        switch sort {
        case .author, .series, .fandom:
            sorted = sections(sort).flatMap(\.items)
        case .title:
            // Precompute keys: a localized compare inside sort() is O(n log n)
            // expensive comparisons; lowercasing once per item is O(n).
            sorted = library.flatMap(\.items).map { ($0.title.lowercased(), $0) }
                .sorted { $0.0 < $1.0 }.map(\.1)
        case .added:
            sorted = library.flatMap(\.items).sorted { $0.added > $1.added }
        case .updated:
            sorted = library.flatMap(\.items).map { (contentDate($0), $0) }
                .sorted { $0.0 > $1.0 }.map(\.1)
        }
        flatCache[sort] = sorted
        return sorted
    }

    /// The library as titled sections, for the grouped sorts: one per
    /// author, or one per series (in part order) with standalone fics last.
    /// Flat sorts come back as a single untitled section.
    func sections(_ sort: LibrarySort) -> [(name: String, items: [LibraryItem])] {
        if let cached = sectionCache[sort] { return cached }
        let result: [(name: String, items: [LibraryItem])]
        switch sort {
        case .author:
            result = library.map { (name: $0.author, items: $0.items) }
        case .series:
            let series = tagGroups(.series)
            let inSeries = Set(series.flatMap { $0.items.map(\.id) })
            let standalone = flatItems(.title).filter { !inSeries.contains($0.id) }
            result = series + (standalone.isEmpty ? [] : [(name: Self.standaloneSection, items: standalone)])
        case .fandom:
            // Each fic once, under its first-listed (primary) fandom, so the
            // list never shows the same row twice.
            var byFandom: [String: [LibraryItem]] = [:]
            var unknown: [LibraryItem] = []
            for item in flatItems(.title) {
                if let fandom = detailsIndex[item.id]?.fandoms.first {
                    byFandom[fandom, default: []].append(item)
                } else {
                    unknown.append(item)
                }
            }
            result = byFandom
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { (name: $0.key, items: $0.value) }
                + (unknown.isEmpty ? [] : [(name: "Fandom unknown", items: unknown)])
        default:
            result = [(name: "", items: flatItems(sort))]
        }
        sectionCache[sort] = result
        return result
    }

    static let standaloneSection = "Not in a Series"

    /// Looks a fic up by id (favorites, collections, selection).
    func item(withID id: String) -> LibraryItem? {
        if idCache == nil {
            // The library's copy wins over a To Read one of the same fic.
            idCache = Dictionary((library.flatMap(\.items) + toRead).map { ($0.id, $0) }) { first, _ in first }
        }
        return idCache?[id]
    }

    // MARK: - to read

    /// Fics saved to read later, newest first: `<root>/To Read/…`, kept out
    /// of the library until added to it.
    @Published private(set) var toRead: [LibraryItem] = []

    private var toReadRoot: URL {
        destinationRoot.appendingPathComponent(Organizer.toReadFolder, isDirectory: true)
    }

    func isToRead(_ item: LibraryItem) -> Bool {
        item.url.standardizedFileURL.path.hasPrefix(toReadRoot.standardizedFileURL.path + "/")
    }

    /// Moves a To Read fic into the library, filed as any download is; a
    /// copy already there is backed up, as an update would be. Its id —
    /// and so its reading place, favorite and collections — stays the same.
    func addToLibrary(_ item: LibraryItem) async {
        guard isToRead(item) else { return }
        guard item.isDownloaded else {
            showToast("\(item.title.quoted) is still downloading from iCloud")
            return
        }
        do {
            let organizer = Organizer(root: destinationRoot, provider: item.provider)
            try organizer.place(item.url, author: item.url.deletingLastPathComponent().lastPathComponent,
                                title: item.url.deletingPathExtension().lastPathComponent)
            let dir = item.url.deletingLastPathComponent()
            if let left = try? FileManager.default.contentsOfDirectory(atPath: dir.path), left.isEmpty {
                try? FileManager.default.removeItem(at: dir)
            }
            toRead.removeAll { $0.id == item.id }
            idCache = nil
            showToast("Added \(item.title.quoted) to the library")
        } catch {
            showToast("Couldn't add \(item.title.quoted): \(error.localizedDescription)")
        }
        await refreshLibraryNow()
    }

    /// The fics in one list, in the order that list shows them.
    func items(for list: FicList) -> [LibraryItem] {
        switch list {
        case .library(let sort, let query):
            return flatItems(sort).filter { item($0, matches: query) }
        case .favorites(let query):
            return favoriteItems.filter { item($0, matches: query) }
        case .tag(let tag, let query):
            return (tagGroups(tag.kind).first { $0.name == tag.name }?.items ?? [])
                .filter { item($0, matches: query) }
        case .collection(let name, let query):
            return items(inCollection: name).filter { item($0, matches: query) }
        case .toRead(let query):
            return toRead.filter { item($0, matches: query) }
        }
    }

    // MARK: - fic details (parsed out of the EPUB itself)

    /// item.id → metadata, for whatever has been parsed so far. Series
    /// grouping and search read from this; it fills in the background.
    @Published private(set) var detailsIndex: [String: WorkDetails] = [:] {
        didSet { vocabularyCache = nil }
    }
    /// "path|mtime" → details. Persisted to Caches so a library is parsed
    /// once ever, not once per launch.
    private var detailsCache: [String: WorkDetails] = [:]
    private var detailsCacheLoaded = false
    private var lastCacheSave = Date.distantPast
    private var indexTask: Task<Void, Never>?

    private nonisolated static var detailsCacheFile: URL {
        // A test library gets its own cache: the final save prunes entries
        // for files not in the library, which would empty the real one's.
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(testLibrary == nil
                ? "parade-details-cache.json" : "parade-details-cache-testlibrary.json")
    }

    private nonisolated static func cacheKey(_ item: LibraryItem) -> String {
        item.url.path + "|" + String(item.date.timeIntervalSince1970)
    }

    private func didUpdateDetails() {
        invalidateDerived(detailsOnly: true)
    }

    /// Rich metadata for one fic, read from inside its EPUB (summary, tags,
    /// series, stats…). Cached per file version.
    func details(for item: LibraryItem) async -> WorkDetails? {
        let key = Self.cacheKey(item)
        if let hit = detailsCache[key] {
            guard hit != WorkDetails() else { return nil }  // known unparseable
            // Only publish a change: a no-op write still redraws every
            // observer, which made the pager stutter mid-swipe.
            if detailsIndex[item.id] != hit { detailsIndex[item.id] = hit }
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

    /// Details already parsed for this version of the file, if any — lets a
    /// page draw complete on its first frame instead of flashing a spinner.
    func cachedDetails(for item: LibraryItem) -> WorkDetails? {
        guard let hit = detailsCache[Self.cacheKey(item)], hit != WorkDetails() else { return nil }
        return hit
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
        let items = (library.flatMap(\.items) + toRead).filter(\.isDownloaded)

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

    /// Fics grouped by one kind of metadata — fandom, series, tag… (a fic
    /// with several values appears under each). Series list in part order;
    /// the rest by author, then title. Only as complete as the details
    /// index; cached between changes.
    func tagGroups(_ kind: TagKind) -> [(name: String, items: [LibraryItem])] {
        if let cached = tagCache[kind] { return cached }
        var byValue: [String: [LibraryItem]] = [:]
        for item in library.flatMap(\.items) {
            guard let details = detailsIndex[item.id] else { continue }
            for value in kind.values(in: details) {
                byValue[value, default: []].append(item)
            }
        }
        let groups = byValue
            .map { name, items in (name: name, items: sortedForGroup(items, kind: kind)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        tagCache[kind] = groups
        return groups
    }

    /// Series in part order; everything else by author, then title.
    private func sortedForGroup(_ items: [LibraryItem], kind: TagKind) -> [LibraryItem] {
        if kind == .series {
            let keyed: [(part: Int, title: String, item: LibraryItem)] = items.map {
                (detailsIndex[$0.id]?.seriesPart ?? Int.max, $0.title.lowercased(), $0)
            }
            return keyed.sorted { ($0.part, $0.title) < ($1.part, $1.title) }.map(\.item)
        }
        let keyed: [(author: String, title: String, item: LibraryItem)] = items.map {
            ($0.author.lowercased(), $0.title.lowercased(), $0)
        }
        return keyed.sorted { ($0.author, $0.title) < ($1.author, $1.title) }.map(\.item)
    }

    /// Search across title, author, and (once indexed) series, fandoms,
    /// tags, relationships, characters and summary. Allocation-free per item —
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
        // Longest, so last.
        if let summary = d.summary, summary.localizedCaseInsensitiveContains(query) { return true }
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
        if !collections.collections(containing: item.id).isEmpty {
            collections.removeEverywhere(item.id)
            saveCollections()
        }
        if updatesAvailable.remove(item.id) != nil { saveUpdatesAvailable() }
        // Drop it from the visible list immediately; the background rescan
        // confirms.
        library = library.compactMap { group in
            let items = group.items.filter { $0.id != item.id }
            return items.isEmpty ? nil : (author: group.author, items: items)
        }
        invalidateDerived()
        refreshLibrary()
    }

    // MARK: - search history

    /// Searches typed in any library filter, newest first.
    @Published private(set) var recentSearches: [String] = []

    /// Remembers a search. One that extends (or was cut down from) a recent
    /// one replaces it, so typing "hea…heated rivalry" leaves one entry.
    func rememberSearch(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        let lower = q.lowercased()
        var list = recentSearches.filter { old in
            let o = old.lowercased()
            return !lower.hasPrefix(o) && !o.hasPrefix(lower)
        }
        list.insert(q, at: 0)
        recentSearches = Array(list.prefix(12))
        defaults.set(recentSearches, forKey: Keys.recentSearches)
    }

    func forgetSearch(_ query: String) {
        recentSearches.removeAll { $0 == query }
        defaults.set(recentSearches, forKey: Keys.recentSearches)
    }

    func clearSearchHistory() {
        recentSearches = []
        defaults.set(recentSearches, forKey: Keys.recentSearches)
    }

    private var vocabularyCache: [String]?

    /// Every fandom, ship, character, tag and series in the library, most
    /// used first — what search suggests as you type.
    var searchVocabulary: [String] {
        if let vocabularyCache { return vocabularyCache }
        var counts: [String: Int] = [:]
        for d in detailsIndex.values {
            for value in d.fandoms + d.relationships + d.characters + d.additionalTags + [d.seriesName].compactMap({ $0 }) {
                counts[value, default: 0] += 1
            }
        }
        let words = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        vocabularyCache = words
        return words
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
        localEditStamp += 1
        let text = favorites.sorted().joined(separator: "\n") + "\n"
        try? text.write(to: favoritesFile, atomically: true, encoding: .utf8)
    }

    // MARK: - reading positions

    /// Where each fic was left off. Backed by Reading.json in the library
    /// folder, so a fic opened on the phone picks up where the Mac stopped.
    /// Read fresh on every open and merged on every save, so two devices
    /// only ever overwrite each other's entry for the same fic.
    private var readingFile: URL { destinationRoot.appendingPathComponent("Reading.json") }

    private func readingPositions() -> [String: ReadingPosition] {
        guard let data = try? Data(contentsOf: readingFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ReadingPosition].self, from: data)) ?? [:]
    }

    func readingPosition(for item: LibraryItem) -> ReadingPosition? {
        readingPositions()[item.id]
    }

    func saveReadingPosition(_ position: ReadingPosition, for item: LibraryItem) {
        var all = readingPositions()
        var position = position
        position.date = Date()
        lastReadID = item.id
        lastReadDate = position.date
        // Opening a fic counts as reading it, even without turning a page.
        if position.samePlace(as: all[item.id]),
           let saved = all[item.id]?.date, position.date!.timeIntervalSince(saved) < 60 { return }
        all[item.id] = position
        writeReadingPositions(all)
    }

    private func writeReadingPositions(_ all: [String: ReadingPosition]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(all) {
            try? data.write(to: readingFile, options: .atomic)
        }
    }

    /// The fic read most recently, on any device — for Continue reading.
    @Published private(set) var lastReadID: String?
    @Published private(set) var lastReadDate: Date?

    /// Re-reads Reading.json for the latest fic (another device may have
    /// read since).
    func refreshLastRead() {
        let latest = readingPositions()
            .compactMap { id, p in p.date.map { (id, $0) } }
            .max { $0.1 < $1.1 }
        if latest?.0 != lastReadID { lastReadID = latest?.0 }
        if latest?.1 != lastReadDate { lastReadDate = latest?.1 }
    }

    var lastReadItem: LibraryItem? { lastReadID.flatMap(item(withID:)) }

    // MARK: - collections (user-made, separate from AO3 tags)

    /// Backed by Collections.txt in the library folder — see FicCollections.
    @Published private(set) var collections = FicCollections()

    private nonisolated static let collectionsFileName = "Collections.txt"
    private var collectionsFile: URL { destinationRoot.appendingPathComponent(Self.collectionsFileName) }

    /// A collection's fics, most recently added first. Ids whose file is gone
    /// (or still arriving through iCloud) are skipped, not dropped.
    func items(inCollection collection: String) -> [LibraryItem] {
        collections.items(in: collection).reversed().compactMap { item(withID: $0) }
    }

    func isInCollection(_ item: LibraryItem, _ collection: String) -> Bool {
        collections.contains(item.id, in: collection)
    }

    func toggle(_ item: LibraryItem, inCollection collection: String) {
        if collections.contains(item.id, in: collection) {
            collections.remove(item.id, from: collection)
        } else {
            collections.add(item.id, to: collection)
        }
        saveCollections()
    }

    func remove(_ item: LibraryItem, fromCollection collection: String) {
        collections.remove(item.id, from: collection)
        saveCollections()
    }

    /// Returns the created collection's name, or nil if blank or taken.
    @discardableResult
    func createCollection(_ name: String) -> String? {
        guard let created = collections.create(name) else { return nil }
        saveCollections()
        return created
    }

    @discardableResult
    func renameCollection(_ old: String, to new: String) -> Bool {
        guard collections.rename(old, to: new) else { return false }
        saveCollections()
        return true
    }

    func deleteCollection(_ name: String) {
        collections.delete(name)
        saveCollections()
    }

    private func saveCollections() {
        localEditStamp += 1
        try? collections.text.write(to: collectionsFile, atomically: true, encoding: .utf8)
    }

    // MARK: - download pipeline

    /// Downloads every AO3 work and series link in `text` — one link, or a
    /// whole batch pasted at once — one after another.
    func handle(_ text: String, toRead: Bool = false) async {
        guard !isWorking else { return }
        let links = AO3Link.all(in: text)
        guard !links.isEmpty else {
            status("⚠️ \(AO3Error.notAnAO3Link.localizedDescription)")
            return
        }
        isWorking = true
        statusLines = []
        defer { isWorking = false }

        if links.count > 1 {
            status("\(links.count) links…")
        }
        var saved = 0, failed = 0
        var requested = false
        for link in links {
            do {
                if requested {
                    // Be polite to AO3 between links.
                    try? await Task.sleep(for: .seconds(1.5))
                }
                requested = true
                let ids = try await client.workIDs(for: link)
                if case .series = link {
                    status("Series with \(ids.count) work\(ids.count == 1 ? "" : "s")…")
                }
                for (index, id) in ids.enumerated() {
                    if index > 0 {
                        // …and between a series' works.
                        try? await Task.sleep(for: .seconds(1.5))
                    }
                    do {
                        try await downloadWork(id: id, toRead: toRead)
                        saved += 1
                    } catch AO3Error.rateLimited(let retry) {
                        throw AO3Error.rateLimited(retryAfter: retry)
                    } catch {
                        failed += 1
                        status("⚠️ Work \(id): \(error.localizedDescription)")
                    }
                }
            } catch AO3Error.rateLimited(let retry) {
                // Hammering on would only make it worse — stop the batch.
                status("⚠️ \(AO3Error.rateLimited(retryAfter: retry).localizedDescription) Stopped after \(saved) fic\(saved == 1 ? "" : "s").")
                failed += 1
                break
            } catch {
                failed += 1
                status("⚠️ \(error.localizedDescription)")
            }
        }
        if saved + failed > 1 {
            status(failed == 0
                ? "✓ Saved all \(saved) fics"
                : "Saved \(saved) fic\(saved == 1 ? "" : "s"), \(failed) failed")
        }
        await refreshLibraryNow()
        #if os(macOS)
        await scanNow()
        #endif
    }

    private func downloadWork(id: Int, toRead: Bool = false) async throws {
        status("Fetching work \(id)…")
        try await save(client.fetchWork(id: id), toRead: toRead)
    }

    private func save(_ work: WorkInfo, toRead: Bool = false) async throws {
        status("Downloading \(work.title.quoted) by \(work.authorLabel)…")
        let temp = try await client.downloadEPUB(work)
        let dest = try Organizer(root: toRead ? toReadRoot : destinationRoot).place(temp, for: work)
        status("✓ Saved \(relativePath(of: dest))")
    }

    // MARK: - linking fics to AO3

    /// Fics whose EPUB carries no AO3 link — downloaded outside Parade, or
    /// from somewhere else — among those indexed so far.
    var unlinkedItems: [LibraryItem] {
        (library.flatMap(\.items) + toRead).filter { item in
            guard let d = detailsIndex[item.id] else { return false }
            return d.workID == nil
        }
    }

    @Published private(set) var isLinking = false

    /// AO3 works that might be this fic, likeliest first: a title-and-
    /// creator search, then title alone if that finds nothing.
    func ao3Candidates(for item: LibraryItem) async throws -> [WorkBlurb] {
        let author = item.author.components(separatedBy: " & ").first ?? item.author
        let creator = ["anonymous", "unknown", "orphan_account"].contains(author.lowercased()) ? "" : author
        let plain = AO3WorkQuery.plainTerms(item.title)
        // Before a " - " or ": " subtitle other tools add, or AO3 drops.
        let head = item.title.components(separatedBy: " - ").first?
            .components(separatedBy: ": ").first.map(AO3WorkQuery.plainTerms) ?? plain
        // Each a little looser than the last, until one finds something.
        var tries: [(String, String)] = [(item.title, creator), (plain, creator), (plain, ""), (head, creator)]
        tries = tries.filter { !$0.0.isEmpty }
        var seen = Set<String>(), works: [WorkBlurb] = []
        for (title, creator) in tries where seen.insert(title + "|" + creator).inserted {
            if seen.count > 1 { try? await Task.sleep(for: .seconds(1.5)) }
            works = try await client.works(AO3WorkQuery(source: .titleAuthor(title: title, author: creator))).works
            if !works.isEmpty { break }
        }
        let likely = works.filter { $0.matches(title: item.title, author: item.author) }
        return likely + works.filter { w in !likely.contains { $0.id == w.id } }
    }

    /// Replaces a fic's EPUB with AO3's own export of `workID` — which
    /// carries the work's link, tags, summary and series — keeping the old
    /// file in Backups. Favorites, collections and the reading place follow
    /// it if AO3 files it under another name.
    @discardableResult
    func link(_ item: LibraryItem, toWork workID: Int) async -> Bool {
        guard !isWorking else {
            showToast("Busy — try again when the current download finishes")
            return false
        }
        isWorking = true
        defer { isWorking = false }
        let linked = await relink(item, toWork: workID)
        await refreshLibraryNow()
        buildDetailsIndex()
        if linked { showToast("Linked \(item.title.quoted) to AO3") }
        return linked
    }

    private func relink(_ item: LibraryItem, toWork workID: Int) async -> Bool {
        do {
            status("Linking \(item.title.quoted) to AO3 work \(workID)…")
            let work = try await client.fetchWork(id: workID)
            let temp = try await client.downloadEPUB(work)
            let organizer = Organizer(root: isToRead(item) ? toReadRoot : destinationRoot, provider: item.provider)
            let dest = try organizer.place(temp, for: work)
            if dest.standardizedFileURL.path != item.url.standardizedFileURL.path,
               FileManager.default.fileExists(atPath: item.url.path) {
                try? organizer.backUp(item.url)
                let dir = item.url.deletingLastPathComponent()
                if let left = try? FileManager.default.contentsOfDirectory(atPath: dir.path), left.isEmpty {
                    try? FileManager.default.removeItem(at: dir)
                }
            }
            let newID = item.provider + "/" + dest.deletingLastPathComponent().lastPathComponent
                + "/" + dest.deletingPathExtension().lastPathComponent
            if newID != item.id { carryOver(from: item.id, to: newID) }
            status("✓ Linked \(item.title.quoted) to AO3")
            return true
        } catch {
            status("⚠️ \(item.title.quoted): \(error.localizedDescription)")
            showToast("Couldn't link \(item.title.quoted): \(error.localizedDescription)")
            return false
        }
    }

    /// Moves everything keyed by a fic's id to its new id.
    private func carryOver(from old: String, to new: String) {
        if favorites.remove(old) != nil {
            favorites.insert(new)
            saveFavorites()
        }
        let inCollections = collections.collections(containing: old)
        if !inCollections.isEmpty {
            for name in inCollections {
                collections.remove(old, from: name)
                collections.add(new, to: name)
            }
            saveCollections()
        }
        var positions = readingPositions()
        if let p = positions.removeValue(forKey: old) {
            positions[new] = p
            writeReadingPositions(positions)
            if lastReadID == old { lastReadID = new }
        }
        if updatesAvailable.remove(old) != nil { saveUpdatesAvailable() }
    }

    /// Links every unlinked fic whose AO3 search finds exactly one work with
    /// its title and author — the sure ones. Others are left for the fic's
    /// own page, to choose by hand. One request at a time, spaced.
    func linkAllUnlinked() async {
        guard !isWorking else { return }
        let items = unlinkedItems
        guard !items.isEmpty else { return }
        isWorking = true
        isLinking = true
        statusLines = []
        defer { isWorking = false; isLinking = false }
        var linked = 0, unsure = 0
        for (i, item) in items.enumerated() {
            if i > 0 { try? await Task.sleep(for: .seconds(1.5)) }
            do {
                let sure = try await ao3Candidates(for: item).filter { $0.matches(title: item.title, author: item.author) }
                guard sure.count == 1 else {
                    unsure += 1
                    status("· \(item.title.quoted): \(sure.isEmpty ? "no sure match" : "\(sure.count) possible works") — choose on its page")
                    continue
                }
                try? await Task.sleep(for: .seconds(1.5))
                if await relink(item, toWork: sure[0].id) { linked += 1 }
            } catch AO3Error.rateLimited(let retry) {
                status("⚠️ \(AO3Error.rateLimited(retryAfter: retry).localizedDescription) Stopped after \(linked).")
                break
            } catch {
                status("⚠️ \(item.title.quoted): \(error.localizedDescription)")
            }
        }
        status("Linked \(linked) of \(items.count)\(unsure > 0 ? "; \(unsure) need a choice on their page" : "")")
        showToast("Linked \(linked) fic\(linked == 1 ? "" : "s") to AO3")
        await refreshLibraryNow()
        buildDetailsIndex()
    }

    // MARK: - fic updates (against AO3)

    /// Item ids whose work changed on AO3 since the local EPUB. Filled by
    /// checkForUpdates(); cleared per fic when it's re-downloaded. Kept
    /// across launches — a sweep is slow, its findings shouldn't vanish.
    @Published private(set) var updatesAvailable: Set<String> = []

    private func saveUpdatesAvailable() {
        defaults.set(updatesAvailable.sorted(), forKey: Keys.updatesAvailable)
    }
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
        // Also "working": downloads and single updates wait, so nothing
        // interleaves with the politely spaced sweep.
        isCheckingUpdates = true
        isWorking = true
        defer {
            isCheckingUpdates = false
            isWorking = false
        }
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
                    saveUpdatesAvailable()
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

    /// A one-line result shown briefly over the app, for actions started
    /// from a list row or menu whose outcome would otherwise only reach
    /// the Activity log.
    @Published private(set) var toast: String?

    private func showToast(_ text: String) {
        toast = text
        Task {
            // Long enough to read: a longer message stays up longer.
            try? await Task.sleep(for: .seconds(max(3, Double(text.count) / 15)))
            if toast == text { toast = nil }
        }
    }

    /// Fics being updated individually right now (row spinners).
    @Published private(set) var updating: Set<String> = []

    /// Re-downloads one fic from AO3, whenever the user asks — it never
    /// second-guesses them or runs on its own. The old EPUB is kept in
    /// Backups/.
    func update(_ item: LibraryItem) async {
        guard !isWorking else {
            showToast("Busy — try again when the current download finishes")
            return
        }
        var workID = detailsIndex[item.id]?.workID
        if workID == nil { workID = (await details(for: item))?.workID }
        guard let workID else {
            status("⚠️ \(item.title.quoted) has no AO3 work link inside it")
            showToast("\(item.title.quoted) has no AO3 link inside it")
            return
        }
        isWorking = true
        updating.insert(item.id)
        defer {
            isWorking = false
            updating.remove(item.id)
        }
        do {
            try await downloadWork(id: workID, toRead: isToRead(item))
            updatesAvailable.remove(item.id)
            saveUpdatesAvailable()
            showToast("Updated \(item.title.quoted)")
        } catch {
            status("⚠️ \(error.localizedDescription)")
            showToast("Couldn't update \(item.title.quoted): \(error.localizedDescription)")
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

    /// The path below the library root. Both sides are symlink-resolved —
    /// /tmp vs /private/tmp would otherwise leave the prefix in place.
    private func relativePath(of url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path
        let root = destinationRoot.resolvingSymlinksInPath().path + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }

    // MARK: - Apple Books (macOS)

    #if os(macOS)
    /// Sends one fic to Apple Books (silent import) and remembers it.
    func addToBooks(_ item: LibraryItem) {
        guard sendToBooks([item.url]) else {
            showToast("Couldn't send \(item.title.quoted) to Apple Books")
            return
        }
        markImported(item.url)
        persistImported()
        if Self.testLibrary == nil { status("→ Books: \(item.title)") }
        showToast(Self.testLibrary == nil
            ? "Sent \(item.title.quoted) to Apple Books"
            : "Test library — \(item.title.quoted) not actually sent to Books")
    }

    @discardableResult
    private func sendToBooks(_ urls: [URL]) -> Bool {
        guard Self.testLibrary == nil else {
            // Behave as if sent (so nothing is retried every scan) without
            // touching the real Books library.
            status("Test library — skipped sending \(urls.count) book\(urls.count == 1 ? "" : "s") to Apple Books")
            return true
        }
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
        // "Import All to Apple Books" is the explicit way to do that.
        if defaults.string(forKey: Keys.baselinedFolder) != destinationRoot.path {
            imported = [:]
            downloaded.forEach { markImported($0.url) }
            persistImported()
            defaults.set(destinationRoot.path, forKey: Keys.baselinedFolder)
            if !downloaded.isEmpty {
                status("Found \(downloaded.count) existing book\(downloaded.count == 1 ? "" : "s") — use “Import All to Apple Books” in Settings to send them to Books.")
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
        // Merging the library (or a folder inside it, or one holding it) into
        // itself would refile Author/ folders as authors named "ao3".
        let source = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let root = destinationRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        if source.hasPrefix(root) || root.hasPrefix(source) {
            status("⚠️ That folder is (or contains) the library itself — pick a folder outside it.")
            return
        }
        if Self.testLibrary != nil, source.contains("/Library/Mobile Documents/") {
            status("⚠️ Test library — refusing to move files out of iCloud Drive.")
            return
        }
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

extension String {
    /// The string in curly quotes for messages — unless it already is
    /// quoted (plenty of fic titles are), which would print ““…””.
    var quoted: String {
        let quotes: Set<Character> = ["“", "”", "\"", "‘", "’", "'"]
        if let first = first, let last = last, count > 1, quotes.contains(first), quotes.contains(last) {
            return self
        }
        return "“\(self)”"
    }
}

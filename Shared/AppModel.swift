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
    /// separate settings and caches — so it can
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


    private enum Keys {
        static let folderBookmark = "destinationBookmark.v1"
        /// Apple Books integration, removed; cleared once at launch.
        static let retired = ["autoImport.v1", "importedFiles.v1", "baselinedFolder.v1"]
        static let updatesAvailable = "updatesAvailable.v1"
        static let recentSearches = "recentSearches.v1"
        static let lastUpdateCheck = "lastUpdateCheck.v1"
    }

    init() {
        defaults = Self.settingsStore
        Keys.retired.forEach(defaults.removeObject(forKey:))
        updatesAvailable = Set(defaults.stringArray(forKey: Keys.updatesAvailable) ?? [])
        recentSearches = defaults.stringArray(forKey: Keys.recentSearches) ?? []
        destinationRoot = Self.testLibrary ?? Self.localRoot()
        database = LibraryDatabase.openDefault(testLibrary: Self.testLibrary != nil)
        adoptPendingPositions()
        updateDestinationLabel()
        refreshLibrary()
        Task { await self.connectCloudRoot() }
    }

    /// The device's working store (details, search, reading places).
    private let database: LibraryDatabase

    /// Replaces polling: refreshes when iCloud reports the folder changed.
    private lazy var watcher = LibraryWatcher { [weak self] in self?.libraryChanged() }

    private func libraryChanged() {
        refreshLibrary()
        buildDetailsIndex()
        pullReadingPositions()
    }

    /// The app came forward. iCloud's query catches up on its own; this is
    /// for folders it doesn't watch, and a cheap safety net — at most every
    /// few minutes.
    func appBecameActive() {
        guard Date().timeIntervalSince(lastRefreshEnd) > (inCloud ? 300 : 15) else { return }
        libraryChanged()
    }

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
            pullReadingPositions()
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
            watcher.watchCloud()
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
        pullReadingPositions()
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
        // Only the first scan of an empty library shows as loading; a
        // background refresh mustn't redraw every observer twice a tick.
        let showsScanning = library.isEmpty
        if showsScanning { isScanning = true }
        defer { if showsScanning { isScanning = false } }
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
        if libraryError != nil { libraryError = nil }
        if localEditStamp == editStampAtStart {
            if favorites != scan.favorites { favorites = scan.favorites }
            if collections != scan.collections { collections = scan.collections }
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
        if !hasLoadedOnce { hasLoadedOnce = true }
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
    /// "path|mtime" → details, loaded from the database: a library is
    /// parsed once ever, not once per launch.
    private var detailsCache: [String: WorkDetails] = [:]
    private var detailsCacheLoaded = false
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
            store([.init(key: key, itemID: item.id, details: parsed)])
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
            // Shown only while the index is empty; flipping it on every
            // refresh redrew every observer (the reader too) twice a tick.
            let shows = self?.detailsIndex.isEmpty == true
            if shows { self?.isIndexing = true }
            await self?.runDetailsIndexing()
            if shows { self?.isIndexing = false }
            self?.indexTask = nil
        }
    }

    private func runDetailsIndexing() async {
        if !detailsCacheLoaded {
            detailsCacheLoaded = true
            let database = database
            let file = Self.detailsCacheFile
            let loaded = await Task.detached(priority: .utility) { () -> [String: WorkDetails] in
                // Once: the JSON cache earlier builds kept in Caches moves
                // into the database (it was rewritten whole on every save).
                if database.isEmpty, let data = try? Data(contentsOf: file),
                   let old = try? JSONDecoder().decode([String: WorkDetails].self, from: data) {
                    try? database.upsert(old.map { key, details in
                        .init(key: key, itemID: Self.itemID(fromCacheKey: key), details: details)
                    })
                }
                try? FileManager.default.removeItem(at: file)
                return (try? database.allDetails()) ?? [:]
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
            // One merge per chunk: writing a @Published dictionary key by
            // key copies the whole dictionary each time (O(n²) at 10k).
            var enriched: [String: WorkDetails] = [:]
            for entry in parsed {
                detailsCache[entry.key] = entry.details
                if entry.details != WorkDetails() { enriched[entry.id] = entry.details }
            }
            if !enriched.isEmpty {
                detailsIndex.merge(enriched) { _, new in new }
                didUpdateDetails()
            }
            store(parsed.map { .init(key: $0.key, itemID: $0.id, details: $0.details) })
        }

        // Drop entries for files that no longer exist at that version, so
        // the store can't grow without bound — only when there are any.
        let validKeys = Set(items.map(Self.cacheKey))
        if detailsCache.count != validKeys.count || detailsCache.keys.contains(where: { !validKeys.contains($0) }) {
            detailsCache = detailsCache.filter { validKeys.contains($0.key) }
            let database = database
            Task.detached(priority: .utility) { try? database.prune(keeping: validKeys) }
            searchHits = nil
        }
    }

    /// Writes new entries to the database (rows, not the whole cache).
    private func store(_ rows: [LibraryDatabase.DetailsRow]) {
        guard !rows.isEmpty else { return }
        searchHits = nil
        let database = database
        Task.detached(priority: .utility) { try? database.upsert(rows) }
    }

    /// "…/ao3/Author/Title.epub|123" → "ao3/Author/Title", the item's id.
    private nonisolated static func itemID(fromCacheKey key: String) -> String {
        let path = key.components(separatedBy: "|").first ?? key
        let parts = path.components(separatedBy: "/").suffix(3)
        return parts.joined(separator: "/").replacingOccurrences(of: ".epub", with: "", options: [.anchored, .backwards])
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
    /// tags, relationships, characters and summary. Runs library-size times
    /// per keystroke, so the details side is one database query per query
    /// string (a substring index), not a scan of every fic's text.
    func item(_ item: LibraryItem, matches query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if item.title.localizedCaseInsensitiveContains(query) { return true }
        if item.author.localizedCaseInsensitiveContains(query) { return true }
        return detailsMatches(for: query).contains(item.id)
    }

    /// Ids whose indexed details contain `query`, cached per query until the
    /// details change.
    private var searchHits: (query: String, ids: Set<String>)?

    private func detailsMatches(for query: String) -> Set<String> {
        if let searchHits, searchHits.query == query { return searchHits.ids }
        let ids = (try? database.itemIDs(matching: query)) ?? []
        searchHits = (query, ids)
        return ids
    }

    func delete(_ item: LibraryItem) {
        let fm = FileManager.default
        try? fm.removeItem(at: item.url)
        let dir = item.url.deletingLastPathComponent()
        if let remaining = try? fm.contentsOfDirectory(atPath: dir.path), remaining.isEmpty {
            try? fm.removeItem(at: dir)
        }
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

    private var vocabularyCache: [SearchTerm]?

    /// A word search can suggest: a value from the library and what it is.
    struct SearchTerm: Hashable {
        enum Kind { case author, title, tag }
        let text: String
        let kind: Kind
    }

    /// Every author, title, fandom, ship, character, tag, series, rating,
    /// warning and category in the library, most used first — what search
    /// suggests as you type.
    var searchVocabulary: [SearchTerm] {
        if let vocabularyCache { return vocabularyCache }
        var counts: [SearchTerm: Int] = [:]
        for item in library.flatMap(\.items) + toRead {
            for author in item.author.components(separatedBy: " & ") {
                counts[SearchTerm(text: author, kind: .author), default: 0] += 1
            }
            counts[SearchTerm(text: item.title, kind: .title), default: 0] += 1
        }
        for d in detailsIndex.values {
            let values = d.fandoms + d.relationships + d.characters + d.additionalTags
                + d.rating + d.warnings + d.categories + [d.seriesName].compactMap { $0 }
            for value in values {
                counts[SearchTerm(text: value, kind: .tag), default: 0] += 1
            }
        }
        let terms = counts.sorted { ($0.value, $1.key.text) > ($1.value, $0.key.text) }.map(\.key)
        vocabularyCache = terms
        return terms
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

    /// Where each fic was left off. The device's database holds it; page
    /// turns write only there. Reading.json in the library folder is how
    /// devices share it: written in one batch when the reader closes, the
    /// app leaves the foreground, or every 15 minutes of reading — and read
    /// back when iCloud says another device changed it.
    private var readingFile: URL { destinationRoot.appendingPathComponent("Reading.json") }
    private var readingFileSeen: Date?
    private var positionSync: Task<Void, Never>?

    private func readingPositionsFile() -> [String: ReadingPosition] {
        guard let data = try? Data(contentsOf: readingFile) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ReadingPosition].self, from: data)) ?? [:]
    }

    func readingPosition(for item: LibraryItem) -> ReadingPosition? {
        try? database.readingPosition(for: item.id)
    }

    func saveReadingPosition(_ position: ReadingPosition, for item: LibraryItem) {
        var position = position
        position.date = Date()
        // Continue reading changes fic, not timestamp, per turn: a new date
        // each page would redraw everything observing the model.
        if lastReadID != item.id {
            lastReadID = item.id
            lastReadDate = position.date
        }
        try? database.saveReadingPosition(position, for: item.id)
        guard positionSync == nil else { return }
        positionSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(900))
            guard !Task.isCancelled else { return }
            self?.positionSync = nil
            self?.flushReadingPositions()
        }
    }

    /// Writes this device's new places to Reading.json, merged over what
    /// other devices wrote there (newest place per fic wins).
    func flushReadingPositions() {
        positionSync?.cancel()
        positionSync = nil
        guard database.hasPendingReadingPositions else { return }
        let shared = readingPositionsFile()
        try? database.mergeReadingPositions(shared)
        guard let mine = try? database.readingPositions() else { return }
        var all = shared
        for (id, position) in mine where (position.date ?? .distantPast) > (all[id]?.date ?? .distantPast) {
            all[id] = position
        }
        if let data = try? Self.positionEncoder.encode(all) {
            try? data.write(to: readingFile, options: .atomic)
            try? database.markReadingPositionsSynced()
            readingFileSeen = (try? readingFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        if let date = all[lastReadID ?? ""]?.date, date != lastReadDate { lastReadDate = date }
    }

    /// Takes in places other devices wrote to Reading.json — only when the
    /// file changed since the last look.
    private func pullReadingPositions() {
        let modified = (try? readingFile.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        guard let modified, modified != readingFileSeen else { return }
        readingFileSeen = modified
        try? database.mergeReadingPositions(readingPositionsFile())
        refreshLastRead()
    }

    /// Places the previous build kept in settings between syncs.
    private func adoptPendingPositions() {
        let key = "pendingReading.v1"
        guard let data = defaults.data(forKey: key) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for (id, position) in (try? decoder.decode([String: ReadingPosition].self, from: data)) ?? [:] {
            try? database.saveReadingPosition(position, for: id)
        }
        defaults.removeObject(forKey: key)
    }

    private static let positionEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    /// The fic read most recently, on any device — for Continue reading.
    @Published private(set) var lastReadID: String?
    @Published private(set) var lastReadDate: Date?

    func refreshLastRead() {
        let latest = try? database.latestRead()
        if latest?.itemID != lastReadID { lastReadID = latest?.itemID }
        if latest?.date != lastReadDate { lastReadDate = latest?.date }
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
        // No sleeps here: every request waits its turn in AO3Scheduler.
        for link in links {
            do {
                let ids = try await client.workIDs(for: link)
                if case .series = link {
                    status("Series with \(ids.count) work\(ids.count == 1 ? "" : "s")…")
                }
                for id in ids {
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
    func ao3Candidates(for item: LibraryItem,
                       priority: AO3Scheduler.Priority = .user) async throws -> [WorkBlurb] {
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
            works = try await client.works(AO3WorkQuery(source: .titleAuthor(title: title, author: creator)),
                                           priority: priority).works
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

    private func relink(_ item: LibraryItem, toWork workID: Int,
                        priority: AO3Scheduler.Priority = .user) async -> Bool {
        do {
            status("Linking \(item.title.quoted) to AO3 work \(workID)…")
            let work = try await client.fetchWork(id: workID, priority: priority)
            let temp = try await client.downloadEPUB(work, priority: priority)
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
        if let p = try? database.readingPosition(for: old) {
            // Under the new id; the next sync writes it to Reading.json.
            try? database.saveReadingPosition(p, for: new)
            if lastReadID == old { lastReadID = new }
        }
        if updatesAvailable.remove(old) != nil { saveUpdatesAvailable() }
    }

    /// Links the next 20 unlinked fics whose AO3 search finds exactly one
    /// work with their title and author — the sure ones. Others are left for
    /// the fic's own page, to choose by hand. Twenty at a time, in the
    /// background queue, so a big library never turns into a burst.
    func linkNextUnlinked() async {
        guard !isLinking else { return }
        let items = Array(unlinkedItems.filter { !linkSkipped.contains($0.id) }.prefix(Self.linkBatch))
        guard !items.isEmpty else { return }
        isLinking = true
        statusLines = []
        defer { isLinking = false }
        var linked = 0, unsure = 0
        for item in items {
            if Task.isCancelled { break }
            do {
                let sure = try await ao3Candidates(for: item, priority: .background)
                    .filter { $0.matches(title: item.title, author: item.author) }
                guard sure.count == 1 else {
                    unsure += 1
                    // Not offered again this session; its page still is.
                    linkSkipped.insert(item.id)
                    status("· \(item.title.quoted): \(sure.isEmpty ? "no sure match" : "\(sure.count) possible works") — choose on its page")
                    continue
                }
                if await relink(item, toWork: sure[0].id, priority: .background) { linked += 1 }
            } catch AO3Error.rateLimited(let retry) {
                status("⚠️ \(AO3Error.rateLimited(retryAfter: retry).localizedDescription) Stopped after \(linked).")
                break
            } catch {
                linkSkipped.insert(item.id)
                status("⚠️ \(item.title.quoted): \(error.localizedDescription)")
            }
        }
        status("Linked \(linked) of \(items.count)\(unsure > 0 ? "; \(unsure) need a choice on their page" : "")")
        showToast("Linked \(linked) fic\(linked == 1 ? "" : "s") to AO3")
        await refreshLibraryNow()
        buildDetailsIndex()
    }

    static let linkBatch = 20
    /// Fics a batch couldn't link for sure, skipped by later batches.
    private var linkSkipped: Set<String> = []

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

    /// Asks AO3 which linked fics changed since their EPUB was made — by
    /// searching AO3 for the library's work ids, revised since the last
    /// check, a few hundred ids per request (about 25 requests for 10,000
    /// fics), instead of fetching each work. Background priority: taps go
    /// first, and AO3Scheduler rests between batches and backs off when AO3
    /// asks. Explicit action, never automatic.
    func checkForUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        // What each EPUB says, from the index — no files opened.
        var local: [Int: (id: String, chapters: Int?, updated: Date?)] = [:]
        for item in library.flatMap(\.items) + toRead where item.isDownloaded {
            guard let d = detailsIndex[item.id], let workID = d.workID else { continue }
            local[workID] = (item.id, d.chapters.flatMap(Self.postedChapters), d.latestDate)
        }
        guard !local.isEmpty else {
            status("No fics linked to AO3 to check")
            return
        }
        let since = defaults.object(forKey: Keys.lastUpdateCheck) as? Date
        status("Checking \(local.count) fic\(local.count == 1 ? "" : "s") against AO3…")
        var found = 0
        do {
            for try await page in client.revisedWorks(ids: Array(local.keys), since: since) {
                for blurb in page {
                    guard let mine = local[blurb.id] else { continue }
                    let moreChapters = (blurb.chaptersPosted ?? 0) > (mine.chapters ?? .max)
                    // Day-resolution dates: only a strictly later day counts.
                    let later = zip2(blurb.updated, mine.updated).map { $0.timeIntervalSince($1) >= 86_400 } ?? false
                    if moreChapters || later, updatesAvailable.insert(mine.id).inserted { found += 1 }
                }
            }
            defaults.set(Date(), forKey: Keys.lastUpdateCheck)
        } catch {
            status("⚠️ \(error.localizedDescription) Found \(found) so far; check again later.")
        }
        saveUpdatesAvailable()
        status(found == 0
            ? "✓ Checked \(local.count) fic\(local.count == 1 ? "" : "s") — everything is current"
            : "✓ \(found) update\(found == 1 ? "" : "s") available")
    }

    /// "3/10" or "3/?" → 3.
    private static func postedChapters(_ chapters: String) -> Int? {
        Int(chapters.split(separator: "/").first?.trimmingCharacters(in: .whitespaces) ?? "")
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

    // MARK: - scanning on request (macOS)

    #if os(macOS)
    /// A rescan on request (Scan Now).
    func scan() {
        Task { await self.scanNow() }
    }

    func scanNow() async {
        await refreshLibraryNow()
    }

    /// Merges an existing `[Author]/…/[epub]` tree (e.g. a Calibre library)
    /// INTO the library folder — the folder is the source of truth, so
    /// getting fics into Parade means getting the files into the folder. Files are moved; duplicates
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
                moved += 1
            } catch {
                failed += 1
            }
        }
        var summary = "✓ Merged \(moved) fic\(moved == 1 ? "" : "s") into the library"
        if skipped > 0 { summary += ", \(skipped) already there" }
        if failed > 0 { summary += ", \(failed) failed" }
        status(summary)
        refreshLibrary()
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

private struct AppModelKey: EnvironmentKey {
    static let defaultValue: AppModel? = nil
}

extension EnvironmentValues {
    /// The model as a plain reference, for views that call into it but must
    /// not redraw when it publishes (the reader).
    var appModel: AppModel? {
        get { self[AppModelKey.self] }
        set { self[AppModelKey.self] = newValue }
    }
}

private func zip2<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}

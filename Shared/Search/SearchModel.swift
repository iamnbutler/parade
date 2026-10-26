import SwiftUI
import AO3Kit

/// AO3 search: the sticky profile, and the pages of results it finds.
///
/// Its own object rather than part of AppModel: a page arriving redraws the
/// search screen, not every view watching the library.
@MainActor
final class SearchModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Fetching page 1 — or resolving fandom names before it.
        case loading
        case loaded
        case failed(String)
    }

    /// Saved to Search.json in the library folder whenever it changes.
    @Published var profile = SearchProfile() {
        didSet {
            guard profile != oldValue, loaded else { return }
            save()
            if profile.requestKey != oldValue.requestKey { restart() }
            else { applyLocalFilters() }
        }
    }

    /// Every work fetched so far for the current search, before local filters.
    @Published private(set) var fetched: [WorkBlurb] = []
    /// What the list shows: `fetched` less hidden and (optionally) owned works.
    @Published private(set) var works: [WorkBlurb] = []
    @Published private(set) var total: Int?
    @Published private(set) var phase = Phase.idle
    @Published private(set) var hasMore = false
    /// A later page is on its way.
    @Published private(set) var isLoadingMore = false
    /// AO3 stops at 100,000 results; this search reached that end.
    @Published private(set) var hitResultCap = false
    /// Holding off at AO3's request, until then.
    @Published private(set) var schedulerState = AO3Scheduler.State.idle
    /// Names being looked up on AO3, for "Looking up 3 fandoms…".
    @Published private(set) var resolving: Set<String> = []

    private let client: AO3Client
    private let resolver: TagResolver
    private weak var app: AppModel?
    private var loaded = false
    private var loadedFrom: URL?
    private var nextPage = 1
    private var searchTask: Task<Void, Never>?
    private var moreTask: Task<Void, Never>?

    /// Pages fetched in the last ten minutes, by URL: back from a preview,
    /// or undoing a filter change, costs nothing.
    private var pageCache: [URL: (results: WorkResults, at: Date)] = [:]
    private static let pageCacheLife: TimeInterval = 10 * 60

    /// A test library keeps its own tag cache, as it keeps its own database.
    private nonisolated static var defaultResolver: TagResolver {
        AppModel.testLibrary == nil ? .shared : TagResolver(file: TagResolver.file(named: "ao3-tags-testlibrary.json"))
    }

    init(client: AO3Client = AO3Client(), resolver: TagResolver = SearchModel.defaultResolver) {
        self.client = client
        self.resolver = resolver
        Task { [weak self] in
            for await state in await client.scheduler.stateUpdates() {
                self?.schedulerState = state
            }
        }
    }

    // MARK: - the profile

    private var file: URL? { app.map { $0.destinationRoot.appendingPathComponent("Search.json") } }

    /// Loads the saved profile, or seeds one from the library the first
    /// time; then searches if nothing has been yet. Safe to call on every
    /// appearance: it reloads only when the library folder moved.
    func start(with app: AppModel) {
        self.app = app
        // Still in iCloud, not yet on this device: wait for it rather than
        // seeding a fresh profile over the one that's syncing.
        if let file, Self.isPlaceholder(file) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
            return
        }
        if let file, file != loadedFrom {
            loadedFrom = file
            loaded = false
            if let saved = Self.read(file) { profile = saved }
            loaded = true
        }
        refreshOwned()
        seedIfNeeded()
        if knownTags.isEmpty {
            Task { knownTags.merge(await resolver.all()) { current, _ in current } }
        }
        if profile.seeded, phase == .idle { restart() }
    }

    /// Picks up a profile changed on another device. A no-op when it's the
    /// same as ours (our own save, come back).
    func reloadFromDisk() {
        guard loaded, let file, let saved = Self.read(file), saved != profile else { return }
        profile = saved
    }

    private static func isPlaceholder(_ file: URL) -> Bool {
        let stub = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        return !FileManager.default.fileExists(atPath: file.path)
            && FileManager.default.fileExists(atPath: stub.path)
    }

    private static func read(_ file: URL) -> SearchProfile? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(SearchProfile.self, from: data)
    }

    /// The library's fandoms become the search's — once, and only once the
    /// library has been read: seeding from an index still filling would
    /// miss fandoms for good. An empty library seeds nothing and searches
    /// all of AO3.
    private func seedIfNeeded() {
        guard !profile.seeded, let app, app.hasLoadedOnce, !app.isIndexing else { return }
        let libraryEmpty = app.library.isEmpty && app.toRead.isEmpty
        guard !app.detailsIndex.isEmpty || libraryEmpty else { return }
        profile.seedIfNeeded(fandomLists: libraryFandomLists)
    }

    var libraryFandomLists: [[String]] {
        app?.detailsIndex.values.map(\.fandoms) ?? []
    }

    /// Library fandoms the search leaves out, most fics first.
    /// A synonym the search already covers ("MDZS" when searching its
    /// canonical tag) isn't offered: names are compared as AO3 resolves them.
    var unsearchedLibraryFandoms: [(name: String, count: Int)] { unsearchedLibraryFandoms(in: profile) }

    /// The same, for a search being edited.
    func unsearchedLibraryFandoms(in profile: SearchProfile) -> [(name: String, count: Int)] {
        let counts = Dictionary(libraryFandomLists.flatMap { Set($0) }.map { ($0, 1) }, uniquingKeysWith: +)
        return SearchProfile.seedFandoms(from: libraryFandomLists)
            .filter { tag in !(profile.fandoms + profile.excludedFandoms).contains { $0.isSame(as: known(tag.name)) } }
            .map { ($0.name, counts[$0.name] ?? 0) }
    }

    /// Fics in the library per fandom, any of its names counting.
    func libraryCount(of tag: TagRef) -> Int {
        libraryFandomLists.filter { list in list.contains { known($0).isSame(as: tag) } }.count
    }

    /// Tags AO3 has resolved, by lowercased name.
    private var knownTags: [String: TagRef] = [:]

    /// A name as AO3 resolved it, if it has been.
    private func known(_ name: String) -> TagRef {
        knownTags[name.trimmingCharacters(in: .whitespaces).lowercased()] ?? TagRef(name: name)
    }

    private var backgroundResolve: Task<Void, Never>?

    /// Looks up library fandoms the search doesn't name, quietly and once
    /// each ever, so a synonym of a searched fandom stops being offered.
    private func resolveLibraryFandoms() {
        backgroundResolve?.cancel()
        let names = unsearchedLibraryFandoms.map(\.name).filter { knownTags[$0.lowercased()] == nil }
        guard !names.isEmpty else { return }
        backgroundResolve = Task {
            for name in names {
                guard !Task.isCancelled,
                      let tag = try? await resolver.resolve(name, client: client, priority: .background) else { return }
                knownTags[name.lowercased()] = tag
                objectWillChange.send()
            }
        }
    }


    private func save() {
        guard let file, let data = try? JSONEncoder.pretty.encode(profile) else { return }
        try? data.write(to: file, options: .atomic)
    }

    // MARK: - searching

    /// Starts over at page 1 with the current profile.
    func restart() {
        searchTask?.cancel()
        moreTask?.cancel()
        isLoadingMore = false
        searchTask = Task { await runSearch() }
    }

    private func runSearch() async {
        phase = .loading
        hitResultCap = false
        do {
            await resolveTags()
            try Task.checkCancellation()
            let results = try await page(1)
            try Task.checkCancellation()
            fetched = dedupe(results.works)
            total = results.total
            hasMore = results.hasNextPage
            nextPage = 2
            applyLocalFilters()
            phase = .loaded
            resolveLibraryFandoms()
        } catch is CancellationError {
        } catch {
            fetched = []
            applyLocalFilters()
            phase = .failed(Self.message(for: error))
        }
    }

    /// The next page, when the list nears its end. One page at a time and
    /// never ahead of the reader: no crawling.
    func loadMoreIfNeeded(after work: WorkBlurb, force: Bool = false) {
        guard hasMore, !isLoadingMore, phase == .loaded else { return }
        if !force {
            guard let index = works.firstIndex(where: { $0.id == work.id }), index >= works.count - 5 else { return }
        }
        isLoadingMore = true
        let pageNumber = nextPage
        moreTask = Task {
            defer { isLoadingMore = false }
            do {
                let results = try await page(pageNumber)
                try Task.checkCancellation()
                let known = Set(fetched.map(\.id))
                let fresh = results.works.filter { !known.contains($0.id) }
                fetched += fresh
                total = results.total ?? total
                nextPage = pageNumber + 1
                // Past AO3's last page it repeats that page: nothing new means the end.
                hasMore = results.hasNextPage && !fresh.isEmpty && !results.isCapped
                hitResultCap = results.isCapped
                applyLocalFilters()
            } catch is CancellationError {
            } catch {
                // Leave what's shown; scrolling back down tries again.
                hasMore = true
            }
        }
    }

    private func page(_ number: Int) async throws -> WorkResults {
        let url = profile.query(page: number).url
        if let hit = pageCache[url], Date().timeIntervalSince(hit.at) < Self.pageCacheLife {
            return hit.results
        }
        let results = try await client.works(profile.query(page: number))
        pageCache = pageCache.filter { Date().timeIntervalSince($0.value.at) < Self.pageCacheLife }
        pageCache[url] = (results, Date())
        return results
    }

    private func dedupe(_ list: [WorkBlurb]) -> [WorkBlurb] {
        var seen = Set<Int>()
        return list.filter { seen.insert($0.id).inserted }
    }

    // MARK: - resolving tags

    /// Looks up every fandom and tag not yet known to AO3's canonical name
    /// (an EPUB's fandom may be a synonym, which matches almost nothing), and
    /// writes what it learns back into the profile.
    private func resolveTags() async {
        let pending = profile.allTags.filter { $0.canonical == nil }
        guard !pending.isEmpty else { return }
        resolving = Set(pending.map(\.name))
        defer { resolving = [] }
        var learned: [String: TagRef] = [:]
        for tag in pending {
            guard !Task.isCancelled else { return }
            if let resolved = try? await resolver.resolve(tag.name, client: client) {
                learned[tag.name] = resolved
                knownTags[tag.name.lowercased()] = resolved
            }
            resolving.remove(tag.name)
        }
        guard !learned.isEmpty else { return }
        func fill(_ list: [TagRef]) -> [TagRef] {
            var seen: [TagRef] = []
            for tag in list.map({ learned[$0.name] ?? $0 }) where !seen.contains(where: { $0.isSame(as: tag) }) {
                seen.append(tag)
            }
            return seen
        }
        // Not through `profile`'s didSet: resolving shouldn't restart the search it's part of.
        var updated = profile
        updated.updateTags(fill)
        loaded = false
        profile = updated
        loaded = true
        save()
    }

    // MARK: - local filters and the library

    /// AO3 work id → whether it's in To Read (false: in the library).
    @Published private(set) var owned: [Int: Bool] = [:]

    func refreshOwned() {
        guard let app else { return }
        let toRead = Set(app.toRead.map(\.id))
        var map: [Int: Bool] = [:]
        for (id, details) in app.detailsIndex {
            if let work = details.workID { map[work] = toRead.contains(id) }
        }
        if map != owned {
            owned = map
            applyLocalFilters()
        }
    }

    private func applyLocalFilters() {
        let ownedIDs = Set(owned.keys)
        let shown = fetched.filter { profile.shows($0, owned: ownedIDs) }
        if shown != works { works = shown }
    }

    // MARK: - actions

    /// Works being downloaded from here.
    @Published private(set) var saving: Set<Int> = []

    /// Downloads a result into the library or To Read, through the same
    /// pipeline as a pasted link.
    func save(_ work: WorkBlurb, toRead: Bool, model: AppModel) {
        guard !saving.contains(work.id), owned[work.id] == nil else { return }
        saving.insert(work.id)
        Task {
            let saved = await model.download(workID: work.id, title: work.title, toRead: toRead)
            saving.remove(work.id)
            guard saved else { return }
            if model.detailsIndex.values.contains(where: { $0.workID == work.id }) {
                refreshOwned()
            } else {
                // Not indexed yet: mark it now; the index catches up.
                owned[work.id] = toRead
            }
        }
    }

    func hide(author: String) {
        guard !profile.hiddenAuthors.contains(where: { $0.caseInsensitiveCompare(author) == .orderedSame }) else { return }
        profile.hiddenAuthors.append(author)
    }

    /// A tag from a result: fics must have it, or never show it.
    func set(_ name: String, kind: TagField, to inclusion: Inclusion) {
        let tag = TagRef(name: name)
        var rule = profile.rule(kind)
        rule.include.removeAll { $0.isSame(as: tag) }
        rule.exclude.removeAll { $0.isSame(as: tag) }
        if inclusion == .include { rule.include.append(tag) } else { rule.exclude.append(tag) }
        profile.setRule(rule, kind)
    }

    /// Whether the search names this tag, and how.
    func inclusion(of name: String, kind: TagField) -> Inclusion? {
        let tag = TagRef(name: name)
        let rule = profile.rule(kind)
        if rule.include.contains(where: { $0.isSame(as: tag) }) { return .include }
        if rule.exclude.contains(where: { $0.isSame(as: tag) }) { return .exclude }
        return nil
    }

    static func message(for error: Error) -> String {
        switch error {
        case AO3Error.rateLimited:
            "AO3 asked us to slow down. Try again in a few minutes."
        case let urlError as URLError where urlError.code == .notConnectedToInternet:
            "You're offline."
        default:
            (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

private extension SearchProfile {
    /// The parts of a profile that change what AO3 is asked; the rest are
    /// local filters, applied without a request.
    var requestKey: SearchProfile {
        var key = self
        key.hiddenAuthors = []
        key.hideOwned = false
        key.seeded = false
        return key
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

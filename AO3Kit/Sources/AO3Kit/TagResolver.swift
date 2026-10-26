import Foundation

/// Finds AO3's canonical name (and, when the page shows it, the id) for a tag
/// name, once ever per name.
///
/// EPUBs carry tags as the work was tagged, often a synonym: "Hades (Video
/// Game)" rather than "Hades (Supergiant Games Video Games)". AO3's search
/// matches a synonym's name only to works tagged with exactly that synonym —
/// 3 works instead of thousands — so names are resolved before searching.
///
/// The id is what makes "any of these fandoms" possible: AO3's tag fields
/// AND their names, but `filter_ids:(1 OR 2)` in the query ORs them, and a
/// canonical tag's id matches its synonyms' works too.
public actor TagResolver {
    public static let shared = TagResolver(file: TagResolver.file(named: "ao3-tags.json"))

    private let file: URL?
    private var cache: [String: TagRef] = [:]
    private var loaded = false
    private var inFlight: [String: Task<TagRef, Error>] = [:]

    public init(file: URL?) {
        self.file = file
    }

    /// A file in Application Support/Parade, beside the library database.
    public static func file(named name: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Parade", isDirectory: true)
            .appendingPathComponent(name)
    }

    /// Already known, without asking AO3.
    public func cached(_ name: String) -> TagRef? {
        loadIfNeeded()
        return cache[Self.key(name)]
    }

    /// Everything resolved so far, by lowercased name.
    public func all() -> [String: TagRef] {
        loadIfNeeded()
        return cache
    }

    /// `name` resolved: from the cache, or one request through `client`.
    /// A tag AO3 doesn't know comes back as itself, canonical, so it isn't
    /// asked about again.
    public func resolve(_ name: String, client: AO3Client,
                        priority: AO3Scheduler.Priority = .user) async throws -> TagRef {
        loadIfNeeded()
        let key = Self.key(name)
        if let hit = cache[key] { return hit }
        if let running = inFlight[key] { return try await running.value }
        let task = Task {
            do {
                return try await client.resolveTag(name, priority: priority)
            } catch AO3Error.notFound {
                return TagRef(name: name, canonical: name)
            }
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let resolved = try await task.value
        cache[key] = resolved
        if let canonical = resolved.canonical { cache[Self.key(canonical)] = TagRef(name: canonical, canonical: canonical, id: resolved.id) }
        save()
        return resolved
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let file, let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([String: TagRef].self, from: data) else { return }
        cache.merge(saved) { current, _ in current }
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

/// Reading a tag's canonical name and id out of AO3's answers.
enum TagExtract {
    /// The tag a `/tags/<name>/works` path names, AO3's spelled-out
    /// characters restored: "/tags/Hurt*s*Comfort/works" → "Hurt/Comfort".
    static func tagName(fromWorksPath path: String) -> String? {
        guard let range = path.range(of: #"/tags/([^/?#]+)/works"#, options: .regularExpression) else { return nil }
        let encoded = path[range].dropFirst("/tags/".count).dropLast("/works".count)
        let decoded = String(encoded).removingPercentEncoding ?? String(encoded)
        return decoded
            .replacingOccurrences(of: "*s*", with: "/")
            .replacingOccurrences(of: "*a*", with: "&")
            .replacingOccurrences(of: "*d*", with: ".")
            .replacingOccurrences(of: "*q*", with: "?")
            .replacingOccurrences(of: "*h*", with: "#")
            .replacingOccurrences(of: "*x*", with: "*")  // last: the others add asterisks
    }

    /// From a tag's works listing: the tag it lists (the heading's link) and
    /// its id (the RSS feed link, `/tags/123/feed.atom`, if shown).
    static func listing(_ html: String) -> (name: String?, id: Int?) {
        let name = HTMLExtract.firstMatch(in: html, pattern: #"Works?\s+in\s+<a class="tag" href="[^"]*">([^<]*)</a>"#)
            .map(HTMLExtract.decodeEntities)
        let id = HTMLExtract.firstMatch(in: html, pattern: #"/tags/(\d+)/feed\.atom"#).flatMap { Int($0) }
        return (name, id)
    }
}

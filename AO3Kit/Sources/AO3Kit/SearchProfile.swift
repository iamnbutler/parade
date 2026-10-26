import Foundation

/// An AO3 tag as the person picked it, and what AO3 calls it once looked up.
public struct TagRef: Codable, Hashable, Sendable {
    /// As picked, or as an EPUB spelled it — possibly a synonym.
    public var name: String
    /// AO3's canonical name, once resolved.
    public var canonical: String?
    /// AO3's tag id, once resolved. Searching by id matches the canonical
    /// tag's synonyms and sub-tags too; searching by a synonym's name doesn't.
    public var id: Int?

    public init(name: String, canonical: String? = nil, id: Int? = nil) {
        self.name = name
        self.canonical = canonical
        self.id = id
    }

    /// The name to show and to send: canonical when known.
    public var displayName: String { canonical ?? name }

    /// Same tag, by any of its names.
    public func isSame(as other: TagRef) -> Bool {
        if let id, let otherID = other.id { return id == otherID }
        let mine = [name, canonical].compactMap { $0?.lowercased() }
        let theirs = [other.name, other.canonical].compactMap { $0?.lowercased() }
        return mine.contains { theirs.contains($0) }
    }
}

/// Everything an AO3 search is built from. Sticky: saved as is and changed
/// only by the person, never reset by a search.
public struct SearchProfile: Codable, Hashable, Sendable {
    /// Fics in any of these. Empty searches all of AO3.
    public var fandoms: [TagRef] = []
    /// Free text: title, summary, tags, creator. AO3 query syntax passes through.
    public var words = ""
    /// Ships, characters and freeforms. A fic must have all of them.
    public var includeTags: [TagRef] = []
    /// Never shown. Sent to AO3 and filtered locally too.
    public var hiddenTags: [TagRef] = []
    /// Filtered locally: AO3 can't exclude a creator.
    public var hiddenAuthors: [String] = []
    public var explicitOnly = false
    public var completeOnly = false
    /// Drop works already in the library or To Read. Local.
    public var hideOwned = false
    public var sort: AO3WorkQuery.Sort = .updated
    /// True once filled from the library; seeding never happens again.
    public var seeded = false

    public init() {}

    /// AO3's rating id for Explicit.
    static let explicitRatingID = 13

    /// The sort a search actually uses: best match means nothing without words.
    public var effectiveSort: AO3WorkQuery.Sort {
        sort == .relevance && trimmedWords.isEmpty ? .updated : sort
    }

    var trimmedWords: String { words.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: - seeding

    /// The library's fandoms, most fics first (ties by name): what a first
    /// search covers.
    public static func seedFandoms(from fandomLists: [[String]]) -> [TagRef] {
        var counts: [String: Int] = [:]
        for fandoms in fandomLists {
            for fandom in Set(fandoms) { counts[fandom, default: 0] += 1 }
        }
        return counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map { TagRef(name: $0.key) }
    }

    /// Fills the fandoms from the library, once. Returns whether it did.
    @discardableResult
    public mutating func seedIfNeeded(fandomLists: [[String]]) -> Bool {
        guard !seeded else { return false }
        fandoms = Self.seedFandoms(from: fandomLists)
        seeded = true
        return true
    }

    /// Back to the library's fandoms; words and include tags cleared,
    /// hidden tags and authors kept.
    public mutating func reset(fandomLists: [[String]]) {
        fandoms = Self.seedFandoms(from: fandomLists)
        words = ""
        includeTags = []
        seeded = true
    }

    /// Everything cleared but what's hidden.
    public mutating func clear() {
        fandoms = []
        words = ""
        includeTags = []
    }

    // MARK: - the request

    /// One page of this search.
    public func query(page: Int = 1) -> AO3WorkQuery {
        AO3WorkQuery(source: .profile(self), sort: effectiveSort, completeOnly: completeOnly, page: page)
    }

    /// `work_search[query]`: the words, ANDed with any of the fandoms.
    var queryText: String {
        var clauses: [String] = []
        if !trimmedWords.isEmpty { clauses.append(fandoms.isEmpty ? trimmedWords : "(\(trimmedWords))") }
        if let fandomClause = Self.anyOf(fandoms) { clauses.append(fandomClause) }
        return clauses.joined(separator: " AND ")
    }

    /// Matches works with any of these tags. By id where known (`filter_ids`
    /// holds a work's tags and their canonical and meta tags), by name in
    /// the text-indexed `tag` field otherwise.
    static func anyOf(_ tags: [TagRef]) -> String? {
        let terms = tags.map { tag in
            tag.id.map { "filter_ids:\($0)" } ?? "tag:\"\(phrase(tag.displayName))\""
        }
        switch terms.count {
        case 0: return nil
        case 1: return terms[0]
        default: return "(" + terms.joined(separator: " OR ") + ")"
        }
    }

    /// A tag name safe inside a quoted query phrase.
    static func phrase(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A list of tag names for a comma-separated field. AO3 splits on
    /// commas, and tag names can't contain one.
    static func names(_ tags: [TagRef]) -> String? {
        tags.isEmpty ? nil : tags.map(\.displayName).joined(separator: ",")
    }

    // MARK: - local filtering

    /// Whether a result should show: not hidden, and not owned when owned
    /// fics are hidden. `owned` is the library's AO3 work ids.
    public func shows(_ work: WorkBlurb, owned: Set<Int> = []) -> Bool {
        if hideOwned, owned.contains(work.id) { return false }
        let authors = Set(work.authors.map { $0.lowercased() })
        if hiddenAuthors.contains(where: { authors.contains($0.lowercased()) }) { return false }
        let tags = Set((work.fandoms + work.relationships + work.characters + work.freeforms).map { $0.lowercased() })
        return !hiddenTags.contains { hidden in
            [hidden.name, hidden.canonical].compactMap { $0?.lowercased() }.contains(where: tags.contains)
        }
    }
}

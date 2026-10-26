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

/// AO3's fixed tags: the archive warnings and categories every work carries,
/// with the ids AO3's own search form uses for them.
public struct FixedTag: Hashable, Sendable, Identifiable {
    public let id: Int
    public let name: String

    public static let warnings: [FixedTag] = [
        .init(id: 14, name: "Creator Chose Not To Use Archive Warnings"),
        .init(id: 16, name: "No Archive Warnings Apply"),
        .init(id: 17, name: "Graphic Depictions Of Violence"),
        .init(id: 18, name: "Major Character Death"),
        .init(id: 19, name: "Rape/Non-Con"),
        .init(id: 20, name: "Underage Sex"),
    ]

    public static let categories: [FixedTag] = [
        .init(id: 116, name: "F/F"),
        .init(id: 22, name: "F/M"),
        .init(id: 21, name: "Gen"),
        .init(id: 23, name: "M/M"),
        .init(id: 2246, name: "Multi"),
        .init(id: 24, name: "Other"),
    ]

    static let all = warnings + categories
}

/// Whether a search wants a tag, or won't have it.
public enum Inclusion: String, Codable, Hashable, Sendable {
    case include, exclude
}

/// A run of tags of one kind: works must have all of `include`, and none of
/// `exclude`.
public struct TagRule: Codable, Hashable, Sendable {
    public var include: [TagRef] = []
    public var exclude: [TagRef] = []

    public init(include: [TagRef] = [], exclude: [TagRef] = []) {
        self.include = include
        self.exclude = exclude
    }

    public var isEmpty: Bool { include.isEmpty && exclude.isEmpty }
}

/// Everything an AO3 search is built from. Sticky: saved as is and changed
/// only by the person, never reset by a search.
public struct SearchProfile: Codable, Hashable, Sendable {
    public enum Completion: String, Codable, Hashable, Sendable, CaseIterable {
        case any, complete, inProgress
    }

    public enum Crossovers: String, Codable, Hashable, Sendable, CaseIterable {
        case include, exclude, only
    }

    public enum UpdatedWithin: String, Codable, Hashable, Sendable, CaseIterable {
        case any, week, month, halfYear, year

        /// AO3's `revised_at` value.
        var revisedAt: String? {
            switch self {
            case .any: nil
            case .week: "< 1 week"
            case .month: "< 1 month"
            case .halfYear: "< 6 months"
            case .year: "< 1 year"
            }
        }
    }

    // Words
    /// Any field: title, summary, tags, creator. AO3 query syntax passes through.
    public var words = ""
    public var title = ""
    public var creator = ""

    // Fandoms
    /// Fics in any of these. Empty searches all of AO3.
    public var fandoms: [TagRef] = []
    /// Fics in none of these.
    public var excludedFandoms: [TagRef] = []
    public var crossovers = Crossovers.include

    // Rating, warnings, categories
    public var explicitOnly = false
    /// By AO3 tag id. Included ones: any of them. Excluded: none of them.
    public var warnings: [Int: Inclusion] = [:]
    public var categories: [Int: Inclusion] = [:]

    // Tags
    public var relationships = TagRule()
    public var characters = TagRule()
    public var freeforms = TagRule()
    /// Filtered locally: AO3 can't exclude a creator.
    public var hiddenAuthors: [String] = []

    // The work
    public var completion = Completion.any
    public var singleChapter = false
    public var updatedWithin = UpdatedWithin.any

    // Order
    public var sort: AO3WorkQuery.Sort = .updated
    /// AO3's default is descending for everything but title and creator.
    public var ascending = false

    // Your library
    /// Drop works already in the library or To Read. Local.
    public var hideOwned = false
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

    /// Every tag the search names, for looking them up on AO3.
    public var allTags: [TagRef] {
        fandoms + excludedFandoms + [relationships, characters, freeforms].flatMap { $0.include + $0.exclude }
    }

    /// Applies `transform` to every tag the search names.
    public mutating func updateTags(_ transform: ([TagRef]) -> [TagRef]) {
        fandoms = transform(fandoms)
        excludedFandoms = transform(excludedFandoms)
        for path in [\SearchProfile.relationships, \.characters, \.freeforms] {
            self[keyPath: path].include = transform(self[keyPath: path].include)
            self[keyPath: path].exclude = transform(self[keyPath: path].exclude)
        }
    }

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

    /// Back to a fresh search over the library's fandoms. What's hidden —
    /// excluded warnings, categories, tags and authors — stays hidden.
    public mutating func reset(fandomLists: [[String]]) {
        clear()
        fandoms = Self.seedFandoms(from: fandomLists)
        seeded = true
    }

    /// Everything cleared but what's hidden.
    public mutating func clear() {
        var fresh = SearchProfile()
        fresh.seeded = seeded
        fresh.excludedFandoms = excludedFandoms
        fresh.warnings = warnings.filter { $0.value == .exclude }
        fresh.categories = categories.filter { $0.value == .exclude }
        fresh.relationships.exclude = relationships.exclude
        fresh.characters.exclude = characters.exclude
        fresh.freeforms.exclude = freeforms.exclude
        fresh.hiddenAuthors = hiddenAuthors
        fresh.hideOwned = hideOwned
        self = fresh
    }

    // MARK: - the request

    /// One page of this search.
    public func query(page: Int = 1) -> AO3WorkQuery {
        AO3WorkQuery(source: .profile(self), sort: effectiveSort, page: page)
    }

    /// `work_search[query]`: the words, ANDed with any of the fandoms, any
    /// of the included warnings and categories, and none of the excluded
    /// tags AO3 has an id for.
    ///
    /// AO3's own fields AND every tag they name, so "any of" goes here as
    /// `filter_ids:(1 OR 2)`: `filter_ids` holds a work's tags and their
    /// canonical and meta tags.
    var queryText: String {
        var clauses: [String] = []
        if !trimmedWords.isEmpty { clauses.append("(\(trimmedWords))") }
        if let fandomClause = Self.anyOf(fandoms) { clauses.append(fandomClause) }
        for fixed in [warnings, categories] {
            let wanted = FixedTag.all.filter { fixed[$0.id] == .include }.map { TagRef(name: $0.name, id: $0.id) }
            if let clause = Self.anyOf(wanted) { clauses.append(clause) }
        }
        var excluded = FixedTag.all.filter { warnings[$0.id] == .exclude || categories[$0.id] == .exclude }.map(\.id)
        excluded += excludedTags.compactMap(\.id)
        var text = clauses.joined(separator: " AND ")
        for id in excluded {
            text += text.isEmpty ? "NOT filter_ids:\(id)" : " NOT filter_ids:\(id)"
        }
        // A lone word needs no parentheses.
        if clauses == ["(\(trimmedWords))"], excluded.isEmpty { return trimmedWords }
        return text
    }

    /// Tags never to show, of every kind.
    var excludedTags: [TagRef] {
        excludedFandoms + relationships.exclude + characters.exclude + freeforms.exclude
    }

    /// The search form's fields besides the query.
    var formItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        func add(_ name: String, _ value: String?) {
            if let value, !value.isEmpty { items.append(.init(name: "work_search[\(name)]", value: value)) }
        }
        add("title", title.trimmingCharacters(in: .whitespaces))
        add("creators", creator.trimmingCharacters(in: .whitespaces))
        add("relationship_names", Self.names(relationships.include))
        add("character_names", Self.names(characters.include))
        add("freeform_names", Self.names(freeforms.include))
        // Excluded tags AO3 has no id for go by name.
        add("excluded_tag_names", Self.names(excludedTags.filter { $0.id == nil }))
        if explicitOnly { add("rating_ids", String(Self.explicitRatingID)) }
        switch completion {
        case .any: break
        case .complete: add("complete", "T")
        case .inProgress: add("complete", "F")
        }
        switch crossovers {
        case .include: break
        case .exclude: add("crossover", "F")
        case .only: add("crossover", "T")
        }
        if singleChapter { add("single_chapter", "1") }
        add("revised_at", updatedWithin.revisedAt)
        add("sort_direction", ascending ? "asc" : "desc")
        add("language_id", "en")
        return items
    }

    /// Matches works with any of these tags. By id where known, by name in
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
    /// fics are hidden. `owned` is the library's AO3 work ids. AO3 already
    /// leaves hidden tags out; this catches what it can't (authors) and
    /// what arrives before a tag is looked up.
    public func shows(_ work: WorkBlurb, owned: Set<Int> = []) -> Bool {
        if hideOwned, owned.contains(work.id) { return false }
        let authors = Set(work.authors.map { $0.lowercased() })
        if hiddenAuthors.contains(where: { authors.contains($0.lowercased()) }) { return false }
        let tags = Set((work.fandoms + work.relationships + work.characters + work.freeforms
                        + work.warnings + work.categories).map { $0.lowercased() })
        let hiddenFixed = FixedTag.all
            .filter { warnings[$0.id] == .exclude || categories[$0.id] == .exclude }
            .map { TagRef(name: $0.name) }
        return !(excludedTags + hiddenFixed).contains { hidden in
            [hidden.name, hidden.canonical].compactMap { $0?.lowercased() }.contains(where: tags.contains)
        }
    }

    // MARK: - reading older profiles

    private enum CodingKeys: String, CodingKey {
        case words, title, creator, fandoms, excludedFandoms, crossovers, explicitOnly, warnings, categories
        case relationships, characters, freeforms, hiddenAuthors, completion, singleChapter, updatedWithin
        case sort, ascending, hideOwned, seeded
        // The first version's: tags to include and hide, of any kind.
        case includeTags, hiddenTags, completeOnly
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        words = value(.words, "")
        title = value(.title, "")
        creator = value(.creator, "")
        fandoms = value(.fandoms, [])
        excludedFandoms = value(.excludedFandoms, [])
        crossovers = value(.crossovers, .include)
        explicitOnly = value(.explicitOnly, false)
        warnings = value(.warnings, [:])
        categories = value(.categories, [:])
        relationships = value(.relationships, TagRule())
        characters = value(.characters, TagRule())
        freeforms = value(.freeforms, TagRule(include: value(.includeTags, []), exclude: value(.hiddenTags, [])))
        hiddenAuthors = value(.hiddenAuthors, [])
        completion = value(.completion, value(.completeOnly, false) ? .complete : .any)
        singleChapter = value(.singleChapter, false)
        updatedWithin = value(.updatedWithin, .any)
        sort = value(.sort, .updated)
        ascending = value(.ascending, false)
        hideOwned = value(.hideOwned, false)
        seeded = value(.seeded, false)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(words, forKey: .words)
        try c.encode(title, forKey: .title)
        try c.encode(creator, forKey: .creator)
        try c.encode(fandoms, forKey: .fandoms)
        try c.encode(excludedFandoms, forKey: .excludedFandoms)
        try c.encode(crossovers, forKey: .crossovers)
        try c.encode(explicitOnly, forKey: .explicitOnly)
        try c.encode(warnings, forKey: .warnings)
        try c.encode(categories, forKey: .categories)
        try c.encode(relationships, forKey: .relationships)
        try c.encode(characters, forKey: .characters)
        try c.encode(freeforms, forKey: .freeforms)
        try c.encode(hiddenAuthors, forKey: .hiddenAuthors)
        try c.encode(completion, forKey: .completion)
        try c.encode(singleChapter, forKey: .singleChapter)
        try c.encode(updatedWithin, forKey: .updatedWithin)
        try c.encode(sort, forKey: .sort)
        try c.encode(ascending, forKey: .ascending)
        try c.encode(hideOwned, forKey: .hideOwned)
        try c.encode(seeded, forKey: .seeded)
    }
}

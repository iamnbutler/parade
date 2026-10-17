import Foundation

/// User-made collections of fics, separate from AO3's own tags. Stored like
/// Favorites.txt: a plain text file in the library folder, so collections sync
/// through iCloud with the fics and can be edited by hand —
///
///     # Comfort Reads
///     ao3/Author/Title
///     ao3/Other Author/Another Title
///
///     # To Reread
///
/// A "# " line starts a collection; the lines under it are fic ids. Collections keep
/// file order (oldest first); a collection with no fics is still a collection.
public struct FicCollections: Equatable, Sendable {
    public private(set) var names: [String] = []
    private var members: [String: [String]] = [:]

    public init() {}

    public init(text: String) {
        var current: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") {
                let name = Self.clean(String(line.dropFirst()))
                guard !name.isEmpty else { current = nil; continue }
                create(name)
                current = name
            } else if !line.isEmpty, let current {
                add(line, to: current)
            }
        }
    }

    public var text: String {
        names.map { name in
            (["# " + name] + (members[name] ?? [])).joined(separator: "\n")
        }
        .joined(separator: "\n\n") + "\n"
    }

    public func items(in collection: String) -> [String] { members[collection] ?? [] }

    public func contains(_ id: String, in collection: String) -> Bool {
        members[collection]?.contains(id) ?? false
    }

    /// Collections holding `id`, in collection order.
    public func collections(containing id: String) -> [String] {
        names.filter { contains(id, in: $0) }
    }

    /// Whether `name` can be used for a new collection (or for renaming
    /// `existing`): not blank, and not taken — ignoring case, so "Cozy" and
    /// "cozy" can't both exist.
    public func isAvailable(_ name: String, renaming existing: String? = nil) -> Bool {
        let name = Self.clean(name)
        guard !name.isEmpty else { return false }
        return !names.contains {
            $0 != existing && $0.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    /// Adds an empty collection. Returns the name actually used (trimmed), or nil
    /// when it's blank or already taken.
    @discardableResult
    public mutating func create(_ name: String) -> String? {
        let name = Self.clean(name)
        guard isAvailable(name) else { return nil }
        names.append(name)
        members[name] = []
        return name
    }

    @discardableResult
    public mutating func rename(_ old: String, to new: String) -> Bool {
        let new = Self.clean(new)
        guard let i = names.firstIndex(of: old), isAvailable(new, renaming: old) else { return false }
        names[i] = new
        members[new] = members.removeValue(forKey: old)
        return true
    }

    public mutating func delete(_ collection: String) {
        names.removeAll { $0 == collection }
        members.removeValue(forKey: collection)
    }

    public mutating func add(_ id: String, to collection: String) {
        guard members[collection] != nil, !contains(id, in: collection) else { return }
        members[collection]?.append(id)
    }

    public mutating func remove(_ id: String, from collection: String) {
        members[collection]?.removeAll { $0 == id }
    }

    /// Removes a fic from every collection (it was deleted).
    public mutating func removeEverywhere(_ id: String) {
        for name in names { remove(id, from: name) }
    }

    /// Collection names are single lines without the "#" marker.
    private static func clean(_ name: String) -> String {
        name.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

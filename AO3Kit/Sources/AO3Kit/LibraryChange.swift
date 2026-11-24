import Foundation

/// What a batch of changed paths in the library folder asks the app to
/// redo. iCloud's metadata query reports every file that changed, Parade's
/// own writes included; only some of them need the whole folder walked.
public struct LibraryChange: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// A fic arrived, changed, downloaded or left: walk the library.
    public static let library = LibraryChange(rawValue: 1 << 0)
    /// Favorites.txt, Collections.txt, Reading.json or Search.json: re-read
    /// that small file, no walk.
    public static let state = LibraryChange(rawValue: 1 << 1)
    /// Something in Backups or Trash (the library scan skips both).
    public static let keptCopies = LibraryChange(rawValue: 1 << 2)

    /// Everything: when what changed isn't known.
    public static let all: LibraryChange = [.library, .state, .keptCopies]

    /// The state files Parade keeps at the library root.
    public static let stateFiles: Set<String> = ["Favorites.txt", "Collections.txt", "Reading.json", "Search.json"]

    /// What `paths` (absolute) under `root` need. A path outside `root`, or
    /// none at all, asks for everything: a missed change is worse than a
    /// spare walk.
    public static func classify(paths: [String], root: URL) -> LibraryChange {
        guard !paths.isEmpty else { return .all }
        var prefix = comparable(root.path)
        if !prefix.hasSuffix("/") { prefix += "/" }
        var change: LibraryChange = []
        for path in paths {
            let standard = comparable(path)
            guard standard.hasPrefix(prefix) else { return .all }
            change.formUnion(classify(relative: standard.dropFirst(prefix.count).split(separator: "/").map(String.init)))
        }
        return change
    }

    /// A path as both sides can be compared: standardized, and without the
    /// "/private" that /var and /tmp resolve to (iCloud's index may report
    /// either form). Opens nothing.
    private static func comparable(_ path: String) -> String {
        let standard = URL(fileURLWithPath: path).standardizedFileURL.path
        for alias in ["/private/var/", "/private/tmp/", "/private/etc/"] where standard.hasPrefix(alias) {
            return String(standard.dropFirst("/private".count))
        }
        return standard
    }

    /// One path, as its components below the root.
    static func classify(relative parts: [String]) -> LibraryChange {
        guard let first = parts.first else { return .library }
        if parts.last == ".DS_Store" { return [] }
        if parts.count == 1 {
            let name = placeholderName(first) ?? first
            if stateFiles.contains(name) { return .state }
            // A folder at the root (a provider, To Read) changing as a whole.
            return .library
        }
        if first == Organizer.backupsFolder || first == Organizer.trashFolder { return .keptCopies }
        if first == Organizer.toReadFolder, parts.count > 2,
           parts[1] == Organizer.backupsFolder || parts[1] == Organizer.trashFolder {
            return .keptCopies
        }
        return .library
    }

    /// "Favorites.txt" for an iCloud placeholder ".Favorites.txt.icloud".
    private static func placeholderName(_ name: String) -> String? {
        guard name.hasPrefix("."), name.hasSuffix(".icloud") else { return nil }
        return String(name.dropFirst().dropLast(".icloud".count))
    }
}

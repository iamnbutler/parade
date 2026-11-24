import Foundation

/// Compiled regular expressions by pattern. Compiling one costs more than
/// running it over a blurb or a tag list, and the same few dozen patterns
/// run for every blurb on a search page and every EPUB in the library.
/// NSRegularExpression is immutable, so one instance serves every thread.
enum RegexCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var compiled: [String: NSRegularExpression] = [:]
    /// The patterns are the package's own (a few built from a fixed list of
    /// names); the cap only guards against that ever changing.
    static let limit = 512

    static func regex(_ pattern: String) -> NSRegularExpression? {
        if let hit = lock.withLock({ compiled[pattern] }) { return hit }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        lock.withLock {
            if compiled.count >= limit { compiled.removeAll() }
            compiled[pattern] = regex
        }
        return regex
    }
}

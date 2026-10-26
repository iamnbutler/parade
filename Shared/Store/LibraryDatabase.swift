import Foundation
import GRDB
import AO3Kit

/// The device's own store: what Parade has learned about each fic (parsed
/// EPUB details, a search index over them) and where each was read. It's
/// the working copy — the library folder in iCloud holds the EPUBs and gets
/// state written back in batches (StateSync), not on every change.
///
/// Lives in Application Support, never in iCloud. Safe to call from any
/// thread; heavy reads belong off the main actor.
final class LibraryDatabase: Sendable {
    private let pool: any DatabaseWriter

    init(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        pool = try DatabasePool(path: url.path)
        try Self.migrator.migrate(pool)
    }

    /// A throwaway database, for when the file can't be opened: the app
    /// still works, it just re-learns details next launch.
    init() {
        pool = try! DatabaseQueue()
        try! Self.migrator.migrate(pool)
    }

    /// The app's database (a test library gets its own).
    static func openDefault(testLibrary: Bool) -> LibraryDatabase {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parade", isDirectory: true)
        let url = support.appendingPathComponent(testLibrary ? "library-testlibrary.sqlite" : "library.sqlite")
        return (try? LibraryDatabase(at: url)) ?? LibraryDatabase()
    }

    var isEmpty: Bool {
        (try? pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM details") ?? 0 }) == 0
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            // "path|mtime" → details, so a file is parsed once per version.
            try db.create(table: "details") { t in
                t.primaryKey("key", .text)
                t.column("itemID", .text).notNull().indexed()
                t.column("json", .blob).notNull()
            }
            // Substring search (like localizedCaseInsensitiveContains) over
            // tags, series and summary: trigram tokens index any 3+ letters.
            try db.execute(sql: """
                CREATE VIRTUAL TABLE search USING fts5(itemID UNINDEXED, text, tokenize = 'trigram')
                """)
            try db.create(table: "reading") { t in
                t.primaryKey("itemID", .text)
                t.column("section", .integer).notNull()
                t.column("block", .integer).notNull()
                t.column("date", .double).notNull()
                // Read here since the last write to Reading.json.
                t.column("pending", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    // MARK: - details

    struct DetailsRow: Sendable {
        var key: String
        var itemID: String
        var details: WorkDetails
    }

    /// Every cached entry, key → details.
    func allDetails() throws -> [String: WorkDetails] {
        let decoder = JSONDecoder()
        return try pool.read { db in
            var out: [String: WorkDetails] = [:]
            let rows = try Row.fetchCursor(db, sql: "SELECT key, json FROM details")
            while let row = try rows.next() {
                let data: Data = row["json"]
                if let details = try? decoder.decode(WorkDetails.self, from: data) {
                    out[row["key"]] = details
                }
            }
            return out
        }
    }

    /// Adds or replaces entries, and their search text. An empty WorkDetails
    /// is the "known unparseable" sentinel: stored, never indexed.
    func upsert(_ rows: [DetailsRow]) throws {
        guard !rows.isEmpty else { return }
        let encoder = JSONEncoder()
        try pool.write { db in
            for row in rows {
                try db.execute(sql: "DELETE FROM search WHERE itemID = ?", arguments: [row.itemID])
                try db.execute(
                    sql: "INSERT OR REPLACE INTO details (key, itemID, json) VALUES (?, ?, ?)",
                    arguments: [row.key, row.itemID, try encoder.encode(row.details)])
                let text = Self.searchText(row.details)
                if !text.isEmpty {
                    try db.execute(sql: "INSERT INTO search (itemID, text) VALUES (?, ?)",
                                   arguments: [row.itemID, text])
                }
            }
        }
    }

    /// Drops entries for files that are gone or have changed since.
    func prune(keeping keys: Set<String>) throws {
        try pool.write { db in
            let stale = try String.fetchAll(db, sql: "SELECT key FROM details").filter { !keys.contains($0) }
            for key in stale {
                if let itemID = try String.fetchOne(db, sql: "SELECT itemID FROM details WHERE key = ?", arguments: [key]) {
                    try db.execute(sql: "DELETE FROM details WHERE key = ?", arguments: [key])
                    // Another version of the same fic may still be indexed.
                    if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM details WHERE itemID = ?", arguments: [itemID]) == 0 {
                        try db.execute(sql: "DELETE FROM search WHERE itemID = ?", arguments: [itemID])
                    }
                }
            }
        }
    }

    /// Fics whose tags, series or summary contain `query`, ignoring case.
    func itemIDs(matching query: String) throws -> Set<String> {
        let pattern = "%" + query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        return try pool.read { db in
            Set(try String.fetchAll(db, sql: "SELECT itemID FROM search WHERE text LIKE ? ESCAPE '\\'",
                                    arguments: [pattern]))
        }
    }

    private static func searchText(_ d: WorkDetails) -> String {
        var parts: [String] = []
        if let series = d.seriesName { parts.append(series) }
        parts += d.fandoms + d.additionalTags + d.relationships + d.characters + d.categories + d.rating + d.warnings
        if let summary = d.summary { parts.append(summary) }
        return parts.joined(separator: "\n")
    }

    // MARK: - reading places

    func readingPositions() throws -> [String: ReadingPosition] {
        try pool.read { db in
            var out: [String: ReadingPosition] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT itemID, section, block, date FROM reading") {
                var position = ReadingPosition(section: row["section"], block: row["block"])
                position.date = Date(timeIntervalSince1970: row["date"])
                out[row["itemID"]] = position
            }
            return out
        }
    }

    func readingPosition(for itemID: String) throws -> ReadingPosition? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT section, block, date FROM reading WHERE itemID = ?",
                                             arguments: [itemID]) else { return nil }
            var position = ReadingPosition(section: row["section"], block: row["block"])
            position.date = Date(timeIntervalSince1970: row["date"])
            return position
        }
    }

    /// This device read to here: kept, and marked to go out in the next sync.
    func saveReadingPosition(_ position: ReadingPosition, for itemID: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO reading (itemID, section, block, date, pending) VALUES (?, ?, ?, ?, 1)",
                arguments: [itemID, position.section, position.block, (position.date ?? Date()).timeIntervalSince1970])
        }
    }

    /// Places from another device (Reading.json): each kept only if newer
    /// than what's here.
    func mergeReadingPositions(_ incoming: [String: ReadingPosition]) throws {
        try pool.write { db in
            for (itemID, position) in incoming {
                let date = (position.date ?? .distantPast).timeIntervalSince1970
                try db.execute(sql: """
                    INSERT INTO reading (itemID, section, block, date, pending) VALUES (?, ?, ?, ?, 0)
                    ON CONFLICT(itemID) DO UPDATE SET section = excluded.section, block = excluded.block,
                        date = excluded.date, pending = 0
                    WHERE excluded.date > reading.date
                    """, arguments: [itemID, position.section, position.block, date])
            }
        }
    }

    var hasPendingReadingPositions: Bool {
        (try? pool.read { try Bool.fetchOne($0, sql: "SELECT EXISTS(SELECT 1 FROM reading WHERE pending)") ?? false }) ?? false
    }

    func markReadingPositionsSynced() throws {
        try pool.write { try $0.execute(sql: "UPDATE reading SET pending = 0 WHERE pending") }
    }

    /// The most recently read fic, on any device.
    func latestRead() throws -> (itemID: String, date: Date)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT itemID, date FROM reading ORDER BY date DESC LIMIT 1")
            else { return nil }
            return (row["itemID"], Date(timeIntervalSince1970: row["date"]))
        }
    }
}

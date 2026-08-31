import XCTest
@testable import AO3Kit

final class LibraryMigratorTests: XCTestCase {
    var root: URL!
    var store: URL!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("root")
        store = base.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func write(_ text: String, at relative: String, under base: URL? = nil) throws {
        let url = (base ?? store!).appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func exists(_ relative: String, under base: URL? = nil) -> Bool {
        FileManager.default.fileExists(atPath: (base ?? root!).appendingPathComponent(relative).path)
    }

    func testMergesLegacyFlatStore() throws {
        try write("one", at: "Author A/Fic One.epub")
        try write("two", at: "Author B/Fic Two.epub")
        try write("old", at: "Backups/Author A/Fic One (2026-01-01 120000).epub")
        try write("Author A/Fic One\n", at: "Favorites.txt")

        let result = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertEqual(result.movedEPUBs, 2)
        XCTAssertTrue(exists("ao3/Author A/Fic One.epub"))
        XCTAssertTrue(exists("ao3/Author B/Fic Two.epub"))
        // Legacy author-level backups are refiled under the ao3 provider.
        XCTAssertTrue(exists("Backups/ao3/Author A/Fic One (2026-01-01 120000).epub"))
        XCTAssertEqual(result.favoriteLines, ["Author A/Fic One"])
        // The favorites file is retired to Backups, not deleted.
        XCTAssertTrue(exists("Backups/Favorites (migrated).txt"))
        XCTAssertTrue(LibraryMigrator.isEffectivelyEmpty(store))
    }

    func testMergesProviderLayoutStore() throws {
        try write("x", at: "ao3/Writer/Fic.epub")
        try write("b", at: "Backups/ao3/Writer/Fic (2026-01-01 120000).epub")

        let result = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertEqual(result.movedEPUBs, 1)
        XCTAssertTrue(exists("ao3/Writer/Fic.epub"))
        XCTAssertTrue(exists("Backups/ao3/Writer/Fic (2026-01-01 120000).epub"))
    }

    func testMergesNestedWrapperStore() throws {
        // The old iOS layout: Documents/Fan Fiction/<Author>/<Title>.epub.
        try write("x", at: "Fan Fiction/Writer/Fic.epub")

        let result = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertEqual(result.movedEPUBs, 1)
        XCTAssertTrue(exists("ao3/Writer/Fic.epub"))
        XCTAssertFalse(exists("Fan Fiction", under: root))
    }

    func testDuplicateGoesToBackupsNotDeleted() throws {
        try write("newer", at: "ao3/Writer/Fic.epub", under: root)
        try write("older", at: "Writer/Fic.epub")

        let result = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertEqual(result.movedEPUBs, 0)
        // Destination copy untouched; source copy preserved in Backups.
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("ao3/Writer/Fic.epub"), encoding: .utf8),
            "newer")
        XCTAssertTrue(exists("Backups/ao3/Writer/Fic (migrated).epub"))
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("Backups/ao3/Writer/Fic (migrated).epub"), encoding: .utf8),
            "older")
    }

    func testSecondRunIsANoOp() throws {
        try write("x", at: "Writer/Fic.epub")
        _ = try LibraryMigrator.merge(store: store, into: root)
        let second = try LibraryMigrator.merge(store: store, into: root)
        XCTAssertEqual(second.movedEPUBs, 0)
        XCTAssertTrue(second.favoriteLines.isEmpty)
        XCTAssertTrue(exists("ao3/Writer/Fic.epub"))
    }

    func testPlaceholdersAreReportedNotMoved() throws {
        try write("", at: "Writer/.Fic.epub.icloud")

        let result = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertEqual(result.movedEPUBs, 0)
        XCTAssertEqual(result.pendingDownloads.map(\.lastPathComponent), ["Fic.epub"])
        // Placeholder stays put for a later pass; the store is not "empty".
        XCTAssertTrue(exists("Writer/.Fic.epub.icloud", under: store))
        XCTAssertFalse(LibraryMigrator.isEffectivelyEmpty(store))
    }

    func testMergeIntoItselfIsRefused() throws {
        try write("x", at: "Writer/Fic.epub", under: root)
        let result = try LibraryMigrator.merge(store: root, into: root)
        XCTAssertEqual(result.movedEPUBs, 0)
        XCTAssertTrue(exists("Writer/Fic.epub"))
    }

    func testNormalizeLayoutFilesRootAuthorDirs() throws {
        // A hand-dropped author folder at the library root.
        try write("x", at: "Writer/Fic.epub", under: root)
        try write("keep", at: "ao3/Other/Kept.epub", under: root)

        LibraryMigrator.normalizeLayout(root: root)

        XCTAssertTrue(exists("ao3/Writer/Fic.epub"))
        XCTAssertFalse(exists("Writer"))
        XCTAssertTrue(exists("ao3/Other/Kept.epub"))
    }

    func testBackupNameCollisionsGetSuffixes() throws {
        try write("a", at: "Backups/ao3/W/Fic.epub", under: root)
        try write("b", at: "Backups/W/Fic.epub")

        _ = try LibraryMigrator.merge(store: store, into: root)

        XCTAssertTrue(exists("Backups/ao3/W/Fic.epub"))
        XCTAssertTrue(exists("Backups/ao3/W/Fic (2).epub"))
    }
}

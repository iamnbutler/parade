import XCTest
@testable import AO3Kit

final class LibraryChangeTests: XCTestCase {
    let root = URL(fileURLWithPath: "/lib/Documents", isDirectory: true)

    func classify(_ relative: String...) -> LibraryChange {
        LibraryChange.classify(paths: relative.map { root.path + "/" + $0 }, root: root)
    }

    func testStateFilesDontNeedAWalk() {
        XCTAssertEqual(classify("Favorites.txt"), .state)
        XCTAssertEqual(classify("Reading.json", "Collections.txt", "Search.json"), .state)
        XCTAssertEqual(classify(".Reading.json.icloud"), .state)
    }

    func testKeptCopiesDontNeedAWalk() {
        XCTAssertEqual(classify("Backups/ao3/A/T (2026-01-01 000000).epub"), .keptCopies)
        XCTAssertEqual(classify("Trash/ao3/A/T (2026-01-01 000000).epub"), .keptCopies)
        XCTAssertEqual(classify("To Read/Trash/ao3/A/T (2026-01-01 000000).epub"), .keptCopies)
    }

    func testFicsNeedAWalk() {
        XCTAssertEqual(classify("ao3/Author/Title.epub"), .library)
        XCTAssertEqual(classify("ao3/Author/.Title.epub.icloud"), .library)
        XCTAssertEqual(classify("To Read/ao3/Author/Title.epub"), .library)
        XCTAssertEqual(classify("ao3"), .library)
        // A stray file at the root might be a hand-dropped fic.
        XCTAssertEqual(classify("Title.epub"), .library)
    }

    func testMixedBatchesUnion() {
        XCTAssertEqual(classify("Favorites.txt", "Trash/ao3/A/T (2026-01-01 000000).epub"), [.state, .keptCopies])
        XCTAssertEqual(classify("Favorites.txt", "ao3/A/T.epub"), [.state, .library])
    }

    func testDSStoreIsIgnored() {
        XCTAssertEqual(classify("ao3/Author/.DS_Store"), [])
    }

    func testUnknownMeansEverything() {
        XCTAssertEqual(LibraryChange.classify(paths: [], root: root), .all)
        XCTAssertEqual(LibraryChange.classify(paths: ["/elsewhere/Favorites.txt"], root: root), .all)
    }

    func testRootMatchesThroughSymlinks() {
        // /tmp is /private/tmp: a path reported either way still classifies.
        let tmpRoot = URL(fileURLWithPath: "/tmp", isDirectory: true)
        XCTAssertEqual(LibraryChange.classify(paths: ["/private/tmp/Favorites.txt"], root: tmpRoot), .state)
        XCTAssertEqual(LibraryChange.classify(paths: ["/tmp/Favorites.txt"], root: tmpRoot), .state)
    }
}

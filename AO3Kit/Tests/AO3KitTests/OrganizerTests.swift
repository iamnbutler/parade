import XCTest
@testable import AO3Kit

final class OrganizerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeWork(title: String, authors: [String]) -> WorkInfo {
        WorkInfo(id: 1, title: title, authors: authors,
                 epubURL: URL(string: "https://archiveofourown.org/downloads/1/x.epub")!,
                 updatedAt: nil)
    }

    private func makeTempEPUB() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try Data("fake epub".utf8).write(to: url)
        return url
    }

    func testPlacesIntoProviderAuthorTitle() throws {
        let dest = try Organizer(root: root).place(makeTempEPUB(), for: makeWork(title: "Some Fic", authors: ["writer"]))
        XCTAssertEqual(dest.path, root.appendingPathComponent("ao3/writer/Some Fic.epub").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testReplacingBacksUpPreviousVersion() throws {
        let organizer = Organizer(root: root)
        let work = makeWork(title: "Fic", authors: ["a"])
        let old = try makeTempEPUB()
        try Data("old text".utf8).write(to: old)
        try organizer.place(old, for: work)
        let dest = try organizer.place(makeTempEPUB(), for: work)

        // New version in place, old one preserved under Backups/ao3/a/.
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "fake epub")
        let contents = try FileManager.default.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path)
        XCTAssertEqual(contents, ["Fic.epub"])
        let backupDir = root.appendingPathComponent("Backups/ao3/a")
        let backups = try FileManager.default.contentsOfDirectory(atPath: backupDir.path)
        XCTAssertEqual(backups.count, 1)
        XCTAssertTrue(backups[0].hasPrefix("Fic ("), "\(backups)")
        XCTAssertTrue(backups[0].hasSuffix(".epub"))
        let backedUp = try String(contentsOf: backupDir.appendingPathComponent(backups[0]), encoding: .utf8)
        XCTAssertEqual(backedUp, "old text")
    }

    func testBackupNamesDoNotCollide() throws {
        let organizer = Organizer(root: root)
        let work = makeWork(title: "Fic", authors: ["a"])
        try organizer.place(makeTempEPUB(), for: work)
        try organizer.place(makeTempEPUB(), for: work)
        try organizer.place(makeTempEPUB(), for: work)
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Backups/ao3/a").path)
        XCTAssertEqual(backups.count, 2)
        XCTAssertEqual(Set(backups).count, 2)
    }

    func testMultipleAuthorsJoined() throws {
        let dest = try Organizer(root: root).place(makeTempEPUB(), for: makeWork(title: "T", authors: ["a", "b"]))
        XCTAssertEqual(dest.deletingLastPathComponent().lastPathComponent, "a & b")
    }

    func testSanitize() {
        XCTAssertEqual(Organizer.sanitize("A/B: C\\D"), "A-B- C-D")
        XCTAssertEqual(Organizer.sanitize("  spaced   out  "), "spaced out")
        XCTAssertEqual(Organizer.sanitize("...hidden"), "hidden")
        XCTAssertEqual(Organizer.sanitize(""), "Untitled")
        XCTAssertEqual(Organizer.sanitize("///"), "- - -".replacingOccurrences(of: " ", with: "")) // "---"
        XCTAssertLessThanOrEqual(Organizer.sanitize(String(repeating: "x", count: 500)).count, 120)
    }
}

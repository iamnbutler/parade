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

    func testPlacesIntoAuthorTitle() throws {
        let dest = try Organizer(root: root).place(makeTempEPUB(), for: makeWork(title: "Some Fic", authors: ["writer"]))
        XCTAssertEqual(dest.path, root.appendingPathComponent("writer/Some Fic.epub").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
    }

    func testOverwritesExistingVersion() throws {
        let organizer = Organizer(root: root)
        let work = makeWork(title: "Fic", authors: ["a"])
        try organizer.place(makeTempEPUB(), for: work)
        let dest = try organizer.place(makeTempEPUB(), for: work)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: dest.deletingLastPathComponent().path)
        XCTAssertEqual(contents, ["Fic.epub"])
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

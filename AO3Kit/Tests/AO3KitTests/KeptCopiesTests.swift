import XCTest
@testable import AO3Kit

final class KeptCopiesTests: XCTestCase {
    var root: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func work(_ title: String = "Fic", author: String = "a") -> WorkInfo {
        WorkInfo(id: 1, title: title, authors: [author],
                 epubURL: URL(string: "https://archiveofourown.org/downloads/1/x.epub")!,
                 updatedAt: nil)
    }

    private func epub(_ text: String) throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
        try Data(text.utf8).write(to: url)
        return url
    }

    @discardableResult
    private func write(_ text: String, at path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    private static func stamp(daysAgo days: Double) -> String {
        KeptCopies.stampFormatter().string(from: Date().addingTimeInterval(-days * 86_400))
    }

    private var toRead: URL { root.appendingPathComponent(Organizer.toReadFolder) }

    // MARK: - backup on update

    func testUpdateKeepsThePreviousCopyAsABackupOfThatFic() throws {
        let organizer = Organizer(root: root)
        let dest = try organizer.place(epub("nineteen chapters"), for: work())
        try organizer.place(epub("two"), for: work())

        let backups = KeptCopies.backups(libraryRoot: root, provider: "ao3", author: "a", title: "Fic")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try read(backups[0].url), "nineteen chapters")
        XCTAssertEqual(try read(dest), "two")
        XCTAssertEqual(backups[0].size, "nineteen chapters".utf8.count)
        XCTAssertTrue(backups[0].isDownloaded)
        XCTAssertEqual(backups[0].home.path, dest.path)
        XCTAssertLessThan(abs(backups[0].date.timeIntervalSinceNow), 5, "dated by its stamp: now")
        XCTAssertEqual(KeptCopies.list(.backup, root: root).map(\.url), backups.map(\.url))
    }

    func testNamesOrganizerWritesParse() throws {
        // Guards the stamp format against drifting from Organizer.backUp.
        let organizer = Organizer(root: root)
        try organizer.place(epub("1"), for: work())
        try organizer.place(epub("2"), for: work())
        try organizer.place(epub("3"), for: work())  // same second: "… (stamp) 2.epub"
        let names = try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Backups/ao3/a").path)
        XCTAssertEqual(names.count, 2)
        for name in names { XCTAssertEqual(KeptCopies.parse(name)?.title, "Fic", name) }
    }

    func testListsBackupsOfOneFicNewestFirst() throws {
        let old = Self.stamp(daysAgo: 3), new = Self.stamp(daysAgo: 1)
        try write("x", at: "Backups/ao3/a/Fic (\(old)).epub")
        try write("x", at: "Backups/ao3/a/Fic (\(new)).epub")
        try write("x", at: "Backups/ao3/a/Fic (Part 2) (\(new)).epub")  // another fic
        try write("x", at: "Backups/ao3/a/Fic (migrated).epub")         // unstamped
        try write("x", at: "Backups/ao3/b/Fic (\(new)).epub")            // another author
        let backups = KeptCopies.backups(libraryRoot: root, provider: "ao3", author: "a", title: "Fic")
        XCTAssertEqual(backups.map { $0.url.lastPathComponent },
                       ["Fic (\(new)).epub", "Fic (\(old)).epub"])
        XCTAssertEqual(KeptCopies.backups(libraryRoot: root, provider: "ao3", author: "a", title: "Fic (Part 2)").count, 1)
        XCTAssertEqual(KeptCopies.list(.backup, root: root).count, 4)
    }

    func testListCoversToReadAndKnowsWhereEachCameFrom() throws {
        try write("x", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 2))).epub")
        try write("x", at: "To Read/Backups/ao3/b/Later (\(Self.stamp(daysAgo: 1))).epub")
        let all = KeptCopies.list(.backup, root: root)
        XCTAssertEqual(all.map(\.title), ["Later", "Fic"])
        XCTAssertEqual(all.map(\.isToRead), [true, false])
        XCTAssertEqual(all[0].home.path, root.appendingPathComponent("To Read/ao3/b/Later.epub").path)
        XCTAssertEqual(all[1].author, "a")
    }

    func testICloudPlaceholderListsAsItsFileNotDownloaded() throws {
        let s = Self.stamp(daysAgo: 1)
        try write("", at: "Backups/ao3/a/.Fic (\(s)).epub.icloud")
        let backups = KeptCopies.backups(libraryRoot: root, provider: "ao3", author: "a", title: "Fic")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups[0].url.lastPathComponent, "Fic (\(s)).epub")
        XCTAssertFalse(backups[0].isDownloaded)
        XCTAssertNil(backups[0].size)
        XCTAssertThrowsError(try KeptCopies.restore(backups[0]))
    }

    // MARK: - restore

    func testRestoringABackupKeepsTheCurrentCopySoItCanBeUndone() throws {
        let organizer = Organizer(root: root)
        let dest = try organizer.place(epub("good"), for: work())
        let added = Date(timeIntervalSince1970: 1_700_000_000)
        try fm.setAttributes([.creationDate: added], ofItemAtPath: dest.path)
        try organizer.place(epub("bad"), for: work())

        let backup = try XCTUnwrap(KeptCopies.list(.backup, root: root).first)
        XCTAssertEqual(try KeptCopies.restore(backup).path, dest.path)

        XCTAssertEqual(try read(dest), "good")
        XCTAssertEqual(try dest.resourceValues(forKeys: [.creationDateKey]).creationDate, added)
        let after = KeptCopies.list(.backup, root: root)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(try read(after[0].url), "bad")
    }

    // MARK: - trash

    func testDeletingMovesTheFicToTrashOutOfTheLibrary() throws {
        let dest = try Organizer(root: root).place(epub("text"), for: work())
        let trashed = try KeptCopies.trash(dest, libraryRoot: root, provider: "ao3")
        XCTAssertFalse(fm.fileExists(atPath: dest.path))
        XCTAssertTrue(trashed.path.hasPrefix(root.appendingPathComponent("Trash/ao3/a/").path))
        let deleted = KeptCopies.list(.trash, root: root)
        XCTAssertEqual(deleted.map(\.title), ["Fic"])
        XCTAssertEqual(try read(deleted[0].url), "text")
        XCTAssertTrue(KeptCopies.list(.backup, root: root).isEmpty)
    }

    func testDeletedToReadFicRestoresToToRead() throws {
        let saved = try Organizer(root: toRead).place(epub("later"), for: work("Later"))
        try KeptCopies.trash(saved, libraryRoot: toRead, provider: "ao3")
        XCTAssertFalse(fm.fileExists(atPath: saved.path))

        let copy = try XCTUnwrap(KeptCopies.list(.trash, root: root).first)
        XCTAssertTrue(copy.isToRead)
        XCTAssertEqual(try KeptCopies.restore(copy).path, saved.path)
        XCTAssertEqual(try read(saved), "later")
        XCTAssertTrue(KeptCopies.list(.trash, root: root).isEmpty)
        XCTAssertFalse(exists("To Read/Trash/ao3"), "emptied folders go")
    }

    func testRestoringFromTrashOverAReAddedFicBacksThatUp() throws {
        let organizer = Organizer(root: root)
        let dest = try organizer.place(epub("old"), for: work())
        try KeptCopies.trash(dest, libraryRoot: root, provider: "ao3")
        try organizer.place(epub("re-added"), for: work())
        try KeptCopies.restore(try XCTUnwrap(KeptCopies.list(.trash, root: root).first))
        XCTAssertEqual(try read(dest), "old")
        XCTAssertEqual(try KeptCopies.list(.backup, root: root).map { try read($0.url) }, ["re-added"])
    }

    func testTrashingTwiceInOneSecondKeepsBoth() throws {
        let organizer = Organizer(root: root)
        let now = Date()
        try KeptCopies.trash(organizer.place(epub("1"), for: work()), libraryRoot: root, provider: "ao3", now: now)
        try KeptCopies.trash(organizer.place(epub("2"), for: work()), libraryRoot: root, provider: "ao3", now: now)
        XCTAssertEqual(KeptCopies.list(.trash, root: root).count, 2)
    }

    func testTrashingAnICloudPlaceholderMovesThePlaceholder() throws {
        try write("", at: "ao3/a/.Fic.epub.icloud")
        let real = root.appendingPathComponent("ao3/a/Fic.epub")
        try KeptCopies.trash(real, libraryRoot: root, provider: "ao3")
        XCTAssertFalse(exists("ao3/a/.Fic.epub.icloud"))
        let copy = try XCTUnwrap(KeptCopies.list(.trash, root: root).first)
        XCTAssertFalse(copy.isDownloaded)
        XCTAssertEqual(copy.title, "Fic")
    }

    // MARK: - pruning

    func testPruneDropsCopiesOlderThanThirtyDays() throws {
        try write("x", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 31))).epub")
        try write("x", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 29))).epub")
        try write("x", at: "Backups/ao3/b/Other (\(Self.stamp(daysAgo: 45))) 2.epub")
        try write("x", at: "To Read/Backups/ao3/c/Later (\(Self.stamp(daysAgo: 40))).epub")
        try write("x", at: "Trash/ao3/d/Gone (\(Self.stamp(daysAgo: 31))).epub")
        try write("", at: "Trash/ao3/d/.Evicted (\(Self.stamp(daysAgo: 60))).epub.icloud")
        try write("x", at: "Trash/ao3/d/Recent (\(Self.stamp(daysAgo: 2))).epub")

        XCTAssertEqual(KeptCopies.prune(root: root), 5)

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root.appendingPathComponent("Backups/ao3/a").path),
                       ["Fic (\(Self.stamp(daysAgo: 29))).epub"])
        XCTAssertEqual(KeptCopies.list(.trash, root: root).map(\.title), ["Recent"])
        XCTAssertFalse(exists("Backups/ao3/b"), "folders left empty go too")
        XCTAssertFalse(exists("To Read/Backups/ao3"))
        XCTAssertTrue(exists("Backups"))
    }

    /// The case behind this: an update swapped a 19-chapter fic for a
    /// 2-chapter one. The good copy is the oldest backup and outlives the
    /// window while the fic in the library is smaller than it.
    func testPruneKeepsAnOldBackupBiggerThanTheFicNow() throws {
        try write("2 ch", at: "ao3/a/Fic.epub")
        try write("nineteen chapters", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 90))).epub")
        try write("2 ch", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 89))).epub")
        XCTAssertEqual(KeptCopies.prune(root: root), 1)
        XCTAssertEqual(try KeptCopies.list(.backup, root: root).map { try read($0.url) }, ["nineteen chapters"])

        // Once the fic is whole again, the old copy goes like any other.
        try write("all nineteen chapters", at: "ao3/a/Fic.epub")
        XCTAssertEqual(KeptCopies.prune(root: root), 1)
        XCTAssertTrue(KeptCopies.list(.backup, root: root).isEmpty)
    }

    func testPruneKeepsBackupsItCannotSize() throws {
        // The fic is only an iCloud placeholder here; so is one backup.
        try write("", at: "ao3/a/.Fic.epub.icloud")
        try write("x", at: "Backups/ao3/a/Fic (\(Self.stamp(daysAgo: 40))).epub")
        try write("", at: "Backups/ao3/b/.Other (\(Self.stamp(daysAgo: 40))).epub.icloud")
        try write("x", at: "ao3/b/Other.epub")
        XCTAssertEqual(KeptCopies.prune(root: root), 0)
    }

    func testPruneNeverTouchesFilesItCannotDate() throws {
        try write("x", at: "Backups/ao3/a/Fic (migrated).epub")
        try write("x", at: "Backups/Favorites (migrated).txt")
        try write("x", at: "Trash/ao3/a/notes.txt")
        XCTAssertEqual(KeptCopies.prune(root: root, now: Date().addingTimeInterval(10 * 365 * 86_400)), 0)
        XCTAssertTrue(exists("Backups/ao3/a/Fic (migrated).epub"))
        XCTAssertTrue(exists("Backups/Favorites (migrated).txt"))
        XCTAssertTrue(exists("Trash/ao3/a/notes.txt"))
    }

    func testPruneLeavesTheLibraryAlone() throws {
        // A fic whose title looks like a kept copy's name is still a fic.
        try write("x", at: "ao3/a/Fic (2020-01-01 120000).epub")
        try write("x", at: "To Read/ao3/a/Fic (2020-01-01 120000).epub")
        XCTAssertEqual(KeptCopies.prune(root: root), 0)
        XCTAssertTrue(exists("ao3/a/Fic (2020-01-01 120000).epub"))
        XCTAssertTrue(exists("To Read/ao3/a/Fic (2020-01-01 120000).epub"))
    }

    func testPruneWithNothingKept() {
        XCTAssertEqual(KeptCopies.prune(root: root), 0)
    }

    // MARK: - the library around them

    func testNormalizingTheLibraryLeavesTrashAlone() throws {
        try write("x", at: "Trash/ao3/a/Fic (\(Self.stamp(daysAgo: 1))).epub")
        LibraryMigrator.normalizeLayout(root: root)
        XCTAssertEqual(KeptCopies.list(.trash, root: root).count, 1)
        XCTAssertFalse(exists("ao3"))
    }

    func testMergingAStoreKeepsItsTrashInTrash() throws {
        let store = root.appendingPathComponent("old store")
        let library = root.appendingPathComponent("library")
        try write("x", at: "old store/Trash/ao3/a/Fic (\(Self.stamp(daysAgo: 1))).epub")
        try LibraryMigrator.merge(store: store, into: library)
        XCTAssertEqual(KeptCopies.list(.trash, root: library).map(\.title), ["Fic"])
        XCTAssertFalse(exists("library/ao3/a/Fic (\(Self.stamp(daysAgo: 1))).epub"),
                       "a deleted fic must not come back as a library fic")
    }
}

@MainActor
final class RefreshCoalescerTests: XCTestCase {
    /// The delete bug: a refresh asked for while a scan was running used to
    /// get that scan's result — read before the delete — so the deleted fic
    /// stayed (To Read showed it until some later scan). Now it gets a scan
    /// that starts after the request.
    func testACallDuringARunGetsAFreshRun() async {
        var folder = ["Fic"]
        var seen: [[String]] = []
        let gate = AsyncGate()
        let coalescer = RefreshCoalescer {
            let snapshot = folder      // the scan reads the folder…
            await gate.wait()          // …then takes a while
            seen.append(snapshot)
        }
        let first = Task { await coalescer.run() }
        await Task.yield()
        XCTAssertTrue(coalescer.isRunning)

        folder = []                    // the delete, mid-scan
        let second = Task { await coalescer.run() }
        await Task.yield()
        gate.open()
        await first.value
        await second.value

        XCTAssertEqual(seen, [["Fic"], []], "the call made after the delete saw it")
        XCTAssertFalse(coalescer.isRunning)
    }

    func testCallsDuringARunShareOneMoreRun() async {
        var runs = 0
        let gate = AsyncGate()
        let coalescer = RefreshCoalescer {
            runs += 1
            await gate.wait()
        }
        let first = Task { await coalescer.run() }
        await Task.yield()
        let others = (0..<5).map { _ in Task { await coalescer.run() } }
        await Task.yield()
        gate.open()
        await first.value
        for task in others { await task.value }
        XCTAssertEqual(runs, 2)
    }

    func testRunsAloneOnce() async {
        var runs = 0
        let coalescer = RefreshCoalescer { runs += 1 }
        await coalescer.run()
        await coalescer.run()
        XCTAssertEqual(runs, 2)
    }
}

/// Holds runs until opened; once open, stays open.
@MainActor
private final class AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

import XCTest
@testable import AO3Kit

final class FicCollectionsTests: XCTestCase {
    func testRoundTrip() {
        var collections = FicCollections()
        collections.create("Comfort Reads")
        collections.create("To Reread")
        collections.add("ao3/a/One", to: "Comfort Reads")
        collections.add("ao3/b/Two", to: "Comfort Reads")
        let parsed = FicCollections(text: collections.text)
        XCTAssertEqual(parsed, collections)
        XCTAssertEqual(parsed.names, ["Comfort Reads", "To Reread"])
        XCTAssertEqual(parsed.items(in: "Comfort Reads"), ["ao3/a/One", "ao3/b/Two"])
        XCTAssertEqual(parsed.items(in: "To Reread"), [])
    }

    func testParsesHandEditedText() {
        let collections = FicCollections(text: """
        stray line before any collection
        #Cozy
          ao3/a/One

        ao3/a/One
        #
        ao3/orphan/Dropped
        # Angst
        ao3/b/Two
        """)
        XCTAssertEqual(collections.names, ["Cozy", "Angst"])
        XCTAssertEqual(collections.items(in: "Cozy"), ["ao3/a/One"])
        XCTAssertEqual(collections.items(in: "Angst"), ["ao3/b/Two"])
    }

    func testCreateRejectsBlankAndDuplicates() {
        var collections = FicCollections()
        XCTAssertEqual(collections.create("  Cozy "), "Cozy")
        XCTAssertNil(collections.create("Cozy"))
        XCTAssertNil(collections.create("   "))
        XCTAssertEqual(collections.names, ["Cozy"])
    }

    func testRenameKeepsMembersAndOrder() {
        var collections = FicCollections()
        collections.create("A")
        collections.create("B")
        collections.add("x", to: "A")
        XCTAssertTrue(collections.rename("A", to: "Alpha"))
        XCTAssertFalse(collections.rename("Alpha", to: "B"))
        XCTAssertEqual(collections.names, ["Alpha", "B"])
        XCTAssertEqual(collections.items(in: "Alpha"), ["x"])
    }

    func testMembership() {
        var collections = FicCollections()
        collections.create("A")
        collections.create("B")
        collections.add("x", to: "A")
        collections.add("x", to: "A")
        collections.add("x", to: "B")
        collections.add("x", to: "Missing")
        XCTAssertEqual(collections.items(in: "A"), ["x"])
        XCTAssertEqual(collections.collections(containing: "x"), ["A", "B"])
        collections.removeEverywhere("x")
        XCTAssertEqual(collections.collections(containing: "x"), [])
        collections.delete("A")
        XCTAssertEqual(collections.names, ["B"])
    }

    func testNamesAreCaseInsensitive() {
        var collections = FicCollections()
        collections.create("Space Stuff")
        XCTAssertNil(collections.create("space stuff"))
        XCTAssertFalse(collections.isAvailable("SPACE STUFF"))
        // Re-casing a collection's own name is a rename, not a clash.
        XCTAssertTrue(collections.rename("Space Stuff", to: "space stuff"))
        XCTAssertEqual(collections.names, ["space stuff"])
    }
}

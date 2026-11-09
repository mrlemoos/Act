import Foundation
import XCTest
@testable import ActCore

final class OutlineTests: XCTestCase {
    func testSynopsisIsBodyOfSceneAndHasItsOwnNavigationRange() throws {
        let source = "INT. CAFÉ - DAY\n\n= Clara watches the door.\n= She recognises the visitor.\n\nAction.\n"
        let script = FountainParser.parse(source)
        let entries = FountainOutline.entries(in: script)
        XCTAssertEqual(entries.map(\.kind), [.scene, .synopsis, .synopsis])
        XCTAssertEqual(entries[1].text, "Clara watches the door.")
        XCTAssertEqual(entries[1].parentID, entries[0].id)
        XCTAssertEqual(entries[2].parentID, entries[0].id)
        XCTAssertNil(entries[1].sceneID)
        XCTAssertEqual(entries[0].sceneID, script.scenes[0].id)
        XCTAssertEqual((source as NSString).substring(with: entries[1].range), "= Clara watches the door.")
        XCTAssertNotEqual(entries[1].range, entries[0].range)
    }

    func testSectionsOwnSynopsisBeforeScenesAndResetPreviousSceneOwner() {
        let source = "= Opening idea\n\n# Act one\n= Establish Clara\n\nINT. CAFÉ - DAY\n\n= A visitor arrives\n\n# Act two\n= Follow the visitor\n"
        let entries = FountainOutline.entries(in: FountainParser.parse(source))
        XCTAssertEqual(entries.map(\.kind), [.synopsis, .section, .synopsis, .scene, .synopsis, .section, .synopsis])
        XCTAssertNil(entries[0].parentID)
        XCTAssertEqual(entries[2].parentID, entries[1].id)
        XCTAssertEqual(entries[3].parentID, entries[1].id)
        XCTAssertEqual(entries[4].parentID, entries[3].id)
        XCTAssertEqual(entries[6].parentID, entries[5].id)
        XCTAssertNil(entries[6].sceneID)
    }

    func testNestedSectionsAndScenesRetainSourceOrder() {
        let source = "# Act one\n\n## Arrival\n= Opening sequence\n\nINT. CAFÉ - DAY\n\n= Waiting\n\n## Departure\n= End sequence\n\nEXT. STREET - DAY\n"
        let entries = FountainOutline.entries(in: FountainParser.parse(source))
        XCTAssertEqual(entries.map(\.text), ["Act one", "Arrival", "Opening sequence", "INT. CAFÉ - DAY", "Waiting", "Departure", "End sequence", "EXT. STREET - DAY"])
        XCTAssertEqual(entries.map(\.depth), [0, 1, 2, 2, 3, 1, 2, 2])
        XCTAssertEqual(entries[5].parentID, entries[0].id)
        XCTAssertEqual(entries[7].parentID, entries[5].id)
    }

    func testUnicodeCRLFNavigationAndCommentsDoNotCreateFalseOutlineEntries() {
        let source = "Action 🎬\r\n\r\n/*\r\n# Hidden section\r\n= Hidden synopsis\r\n*/\r\n\r\n# Première [[private note]]\r\n= Café 🎬\r\n\r\nINT. CAFÉ - DAY\r\n"
        let entries = FountainOutline.entries(in: FountainParser.parse(source))
        XCTAssertEqual(entries.map(\.kind), [.section, .synopsis, .scene])
        XCTAssertEqual(entries[0].text, "Première")
        XCTAssertEqual(entries[1].text, "Café 🎬")
        XCTAssertEqual((source as NSString).substring(with: entries[1].range), "= Café 🎬")
        XCTAssertEqual(entries[1].range.location, (source as NSString).range(of: "= Café 🎬").location)
    }

    func testPageBreakAndOrdinaryActionDoNotBecomeSynopsis() {
        let entries = FountainOutline.entries(in: FountainParser.parse("===\n\nOrdinary action.\n"))
        XCTAssertTrue(entries.isEmpty)
    }
}

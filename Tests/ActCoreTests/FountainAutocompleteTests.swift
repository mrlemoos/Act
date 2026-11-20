import Foundation
import XCTest
@testable import ActCore

final class FountainAutocompleteTests: XCTestCase {
    private func tail(_ source: String) -> NSRange {
        NSRange(location: (source as NSString).length, length: 0)
    }

    func testSessionAfterBlankLineFindsHeadingsCuesAndTransitions() {
        let source = "INT. KITCHEN - DAY\n\nMARA (V.O.)\nHello.\n\nC\n\nCUT TO:\n"
        let screenplay = FountainParser.parse(source)
        XCTAssertNotNil(FountainAutocomplete.session(source: source + "\n\nMAR", selection: tail(source + "\n\nMAR")))
        XCTAssertNotNil(FountainAutocomplete.session(source: source + "\n\nINT", selection: tail(source + "\n\nINT"), libraryNames: []))
        let transition = FountainAutocomplete.session(source: source + "\n\nDI", selection: tail(source + "\n\nDI"), libraryNames: [])
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.category, .transition)
        let items = FountainAutocomplete.suggestions(for: transition!, screenplay: screenplay, libraryNames: [])
        XCTAssertTrue(items.contains { $0.insertText == "DISSOLVE TO:" })
    }

    func testForcedPrefixesAndUnicodeCharacterNames() {
        let source = "INT. CAFÉ - DAY\n\nÉVA\nHello.\n\n@"
        let caret = tail(source + "É")
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source + "É", selection: caret, libraryNames: []))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source + "É"), libraryNames: [])
        XCTAssertTrue(items.contains { $0.displayText == "ÉVA" })
        let dotSource = "INT. ROOM - DAY\n\n."
        let dot = try XCTUnwrap(FountainAutocomplete.session(source: dotSource,
                                                             selection: NSRange(location: (dotSource as NSString).length - 1, length: 1)))
        XCTAssertEqual(dot.category, .sceneHeading)
    }

    func testSceneNumberSuffixPreservedOnAcceptance() {
        let source = "INT. KITCHEN - DAY\n\n.INT #12#\n"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: NSRange(location: 23, length: 0)))
        let suggestion = FountainAutocomplete.Suggestion(insertText: "INT. KITCHEN - DAY", displayText: "INT. KITCHEN - DAY")
        let applied = try XCTUnwrap(FountainAutocomplete.applying(suggestion, to: source, session: session))
        XCTAssertTrue(applied.source.contains("INT. KITCHEN - DAY #12#"))
        XCTAssertFalse(applied.source.contains("\n\n\n"))
    }

    func testTransitionsInsertClassifiableText() {
        let source = "INT. ROOM - DAY\n\n"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source + "CUT", selection: tail(source + "CUT")))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source + "CUT"), libraryNames: [])
        let choice = try XCTUnwrap(items.first { $0.insertText == "CUT TO:" })
        let applied = try XCTUnwrap(FountainAutocomplete.applying(choice, to: source + "CUT", session: session))
        let line = FountainParser.parse(applied.source).elements.first { $0.kind == .transition }
        XCTAssertNotNil(line)
    }

    func testLibraryNamesRequireUppercaseTyping() {
        let source = "INT. ROOM - DAY\n\n"
        let lower = try XCTUnwrap(FountainAutocomplete.session(source: source + "Or", selection: tail(source + "Or"), libraryNames: ["Orleans"]))
        let lowerItems = FountainAutocomplete.suggestions(for: lower, screenplay: FountainParser.parse(source + "Or"), libraryNames: ["Orleans"])
        XCTAssertFalse(lowerItems.contains { $0.displayText == "ORLEANS" })
        let upper = try XCTUnwrap(FountainAutocomplete.session(source: source + "OR", selection: tail(source + "OR"), libraryNames: ["Orleans"]))
        let upperItems = FountainAutocomplete.suggestions(for: upper, screenplay: FountainParser.parse(source + "OR"), libraryNames: ["Orleans"])
        XCTAssertTrue(upperItems.contains { $0.insertText == "ORLEANS" })
    }

    func testBuiltInTimesFollowLocaleAndDocumentPrecedence() {
        XCTAssertEqual(FountainAutocomplete.shippedTimeOfDayKeys(locale: "es-ES"), [
            "Time of day|DAY", "Time of day|NIGHT", "Time of day|DAWN", "Time of day|DUSK",
            "Time of day|MORNING", "Time of day|LATER", "Time of day|CONTINUOUS"
        ])
        let source = "INT. ROOM - NOCHE\n\n"
        let screenplay = FountainParser.parse(source)
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source + ".INT", selection: tail(source + ".INT")))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: screenplay, libraryNames: [], locale: "es-ES")
        XCTAssertTrue(items.contains { $0.displayText == "NOCHE" })
        XCTAssertFalse(items.contains { $0.displayText == "EVENING" })
        XCTAssertEqual(L10n.string("Time of day|DAY", table: "Autocomplete", locale: "fr-FR"), "JOUR")
    }

    func testContinuationExtensionNeverOffered() {
        let source = "INT. ROOM - DAY\n\nMARA (CONT'D)\nHi.\n\nMARA ("
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: tail(source)))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source), libraryNames: [])
        XCTAssertFalse(items.contains { $0.displayText.localizedCaseInsensitiveContains("CONT") })
        XCTAssertTrue(items.contains { $0.displayText.contains("(V.O.)") })
    }

    func testIneligibleContextsStayClosed() {
        let dialogue = "INT. ROOM - DAY\n\nMARA\nDial"
        XCTAssertNil(FountainAutocomplete.session(source: dialogue, selection: tail(dialogue)))
        let action = "INT. ROOM - DAY\n\nShe opens the door.\nAct"
        XCTAssertNil(FountainAutocomplete.session(source: action, selection: tail(action)))
        let parenthetical = "INT. ROOM - DAY\n\nMARA\n(quiet"
        XCTAssertNil(FountainAutocomplete.session(source: parenthetical, selection: tail(parenthetical)))
    }

    func testApplyingLeavesSurroundingSourceUntouched() {
        let source = "INT. KITCHEN - DAY\n\nMARA\nHello.\n\nMA"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: tail(source), libraryNames: []))
        let item = try XCTUnwrap(FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source),
                                                                  libraryNames: []).first)
        let applied = try XCTUnwrap(FountainAutocomplete.applying(item, to: source, session: session))
        XCTAssertTrue(applied.source.hasPrefix("INT. KITCHEN - DAY"))
        XCTAssertTrue(applied.source.contains("Hello."))
    }
}
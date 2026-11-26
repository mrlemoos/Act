import Foundation
import XCTest
@testable import ActCore

final class FountainAutocompleteTests: XCTestCase {
    private func tail(_ source: String) -> NSRange {
        NSRange(location: (source as NSString).length, length: 0)
    }

    func testSessionAfterBlankLineFindsHeadingsCuesAndTransitions() throws {
        let source = "INT. KITCHEN - DAY\n\nMARA (V.O.)\nHello.\n\nC\n\nCUT TO:\n"
        XCTAssertNotNil(FountainAutocomplete.session(source: source + "\n\nMAR", selection: tail(source + "\n\nMAR")))
        XCTAssertNotNil(FountainAutocomplete.session(source: source + "\n\nINT", selection: tail(source + "\n\nINT"), libraryNames: []))
        let transition = FountainAutocomplete.session(source: source + "\n\nDI", selection: tail(source + "\n\nDI"), libraryNames: [])
        XCTAssertNotNil(transition)
        XCTAssertEqual(transition?.category, .transition)
        let items = FountainAutocomplete.suggestions(for: transition!, screenplay: FountainParser.parse(source + "\n\nDI"), libraryNames: [])
        XCTAssertTrue(items.contains { $0.insertText == "DISSOLVE TO:" })
    }

    func testForcedPrefixesAndUnicodeCharacterNames() throws {
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

    func testSceneNumberSuffixPreservedOnAcceptance() throws {
        let source = "INT. KITCHEN - DAY\n\n.INT #12#\n"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: NSRange(location: (source as NSString).range(of: " #12#").location, length: 0)))
        let suggestion = FountainAutocomplete.Suggestion(insertText: "INT. KITCHEN - DAY", displayText: "INT. KITCHEN - DAY")
        let applied = try XCTUnwrap(FountainAutocomplete.applying(suggestion, to: source, session: session))
        XCTAssertTrue(applied.source.contains("INT. KITCHEN - DAY #12#"))
        XCTAssertFalse(applied.source.contains("\n\n\n"))
    }

    func testTransitionsInsertClassifiableText() throws {
        let source = "INT. ROOM - DAY\n\n"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source + "CUT", selection: tail(source + "CUT")))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source + "CUT"), libraryNames: [])
        let choice = try XCTUnwrap(items.first { $0.insertText == "CUT TO:" })
        let applied = try XCTUnwrap(FountainAutocomplete.applying(choice, to: source + "CUT", session: session))
        let line = FountainParser.parse(applied.source).elements.first { $0.kind == .transition }
        XCTAssertNotNil(line)
    }

    func testLibraryNamesRequireUppercaseTyping() throws {
        let source = "INT. ROOM - DAY\n\n"
        XCTAssertNil(FountainAutocomplete.session(source: source + "Or", selection: tail(source + "Or"), libraryNames: ["Orleans"]))
        let upper = try XCTUnwrap(FountainAutocomplete.session(source: source + "OR", selection: tail(source + "OR"), libraryNames: ["Orleans"]))
        let upperItems = FountainAutocomplete.suggestions(for: upper, screenplay: FountainParser.parse(source + "OR"), libraryNames: ["Orleans"])
        XCTAssertTrue(upperItems.contains { $0.insertText == "ORLEANS" })
    }

    func testBuiltInTimesFollowLocaleAndDocumentPrecedence() throws {
        XCTAssertEqual(FountainAutocomplete.shippedTimeOfDayKeys(locale: "es-ES"), [
            "Time of day|DAY", "Time of day|NIGHT", "Time of day|DAWN", "Time of day|DUSK",
            "Time of day|MORNING", "Time of day|LATER", "Time of day|CONTINUOUS"
        ])
        let source = "INT. ROOM - NOCHE\n\n"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source + ".INT ROOM - ", selection: tail(source + ".INT ROOM - ")))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source + ".INT ROOM - "), libraryNames: [], locale: "es-ES")
        XCTAssertTrue(items.contains { $0.displayText == "NOCHE" })
        XCTAssertFalse(items.contains { $0.displayText == "EVENING" })
        XCTAssertEqual(L10n.string("Time of day|DAY", table: "Autocomplete", locale: "fr-FR"), "JOUR")
    }

    func testContinuationExtensionNeverOffered() throws {
        let source = "INT. ROOM - DAY\n\nMARA (CONT'D)\nHi.\n\nMARA ("
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: tail(source)))
        let items = FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source), libraryNames: [])
        XCTAssertFalse(items.contains { $0.displayText.localizedCaseInsensitiveContains("CONT") })
        XCTAssertTrue(items.contains { $0.displayText.contains("(V.O.)") })
    }

    func testIneligibleContextsStayClosed() throws {
        let dialogue = "INT. ROOM - DAY\n\nMARA\nDial"
        XCTAssertNil(FountainAutocomplete.session(source: dialogue, selection: tail(dialogue)))
        let action = "INT. ROOM - DAY\n\nShe opens the door.\nAct"
        XCTAssertNil(FountainAutocomplete.session(source: action, selection: tail(action)))
        let parenthetical = "INT. ROOM - DAY\n\nMARA\n(quiet"
        XCTAssertNil(FountainAutocomplete.session(source: parenthetical, selection: tail(parenthetical)))
    }

    func testApplyingLeavesSurroundingSourceUntouched() throws {
        let source = "INT. KITCHEN - DAY\n\nMARA\nHello.\n\nMA"
        let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: tail(source), libraryNames: []))
        let item = try XCTUnwrap(FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source),
                                                                  libraryNames: []).first)
        let applied = try XCTUnwrap(FountainAutocomplete.applying(item, to: source, session: session))
        XCTAssertTrue(applied.source.hasPrefix("INT. KITCHEN - DAY"))
        XCTAssertTrue(applied.source.contains("Hello."))
    }
    func testTimeAndLocationReplaceOnlyTheirSpanWithUnicodeAndCRLF() throws {
        let prefix = "INT. CAFÉ - NUIT\r\n\r\n"
        for (typed, wanted, expected) in [
            ("EXT. CA", "CAFÉ", "EXT. CAFÉ"),
            ("INT. ROOM - D", "DAY", "INT. ROOM - DAY"),
            (".INT. ROOM - N #é12#", "NUIT", ".INT. ROOM - NUIT #é12#")
        ] {
            let source = prefix + typed + "\r\n"
            let caret = (source as NSString).range(of: " #é12#").location
            let selection = NSRange(location: caret == NSNotFound ? (prefix as NSString).length + (typed as NSString).length : caret, length: 0)
            let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: selection))
            let item = try XCTUnwrap(FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source), libraryNames: [], locale: "en-GB").first { $0.insertText == wanted })
            let applied = try XCTUnwrap(FountainAutocomplete.applying(item, to: source, session: session))
            XCTAssertEqual(applied.source, prefix + expected + "\r\n")
        }
    }

    func testFadeOutPreservesRequiredForcedPrefix() throws {
        for typed in ["FA", ">FA"] {
            let source = "INT. ROOM - DAY\n\n" + typed
            let session = try XCTUnwrap(FountainAutocomplete.session(source: source, selection: tail(source)))
            let item = try XCTUnwrap(FountainAutocomplete.suggestions(for: session, screenplay: FountainParser.parse(source), libraryNames: []).first { $0.displayText == "FADE OUT." })
            XCTAssertEqual(item.insertText, ">FADE OUT.")
            let applied = try XCTUnwrap(FountainAutocomplete.applying(item, to: source, session: session))
            XCTAssertEqual(FountainParser.parse(applied.source).elements.last?.kind, .transition)
        }
    }

    func testInvalidSelectionAndIMEStayClosed() {
        XCTAssertNil(FountainAutocomplete.session(source: "CUT", selection: NSRange(location: 4, length: 0)))
        XCTAssertNil(FountainAutocomplete.session(source: "CUT", selection: tail("CUT"), imeComposing: true))
    }

}
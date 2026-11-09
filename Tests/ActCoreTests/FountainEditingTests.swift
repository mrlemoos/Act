import Foundation
import XCTest
@testable import ActCore

final class FountainEditingTests: XCTestCase {
    private func insertion(_ source: String) -> String {
        FountainEditing.returnInsertion(in: source, selection: NSRange(location: (source as NSString).length, length: 0))
    }

    func testActionHeadingsAndOutlineUseTwoBreaks() {
        for source in ["", "She closes the door.", "INT. ROOM - DAY", "# Act one", "= She leaves.", "!THE ROOM IS EMPTY.", "> CUT TO:"] {
            XCTAssertEqual(insertion(source), "\n\n", source)
        }
    }

    func testCharacterBeingTypedNeedsNoExistingDialogueLookahead() {
        for source in ["MARA", "INT. ROOM - DAY\n\nMARA", "@Mara", "MARA (V.O.)", "MARA ^"] {
            XCTAssertEqual(insertion(source), "\n", source)
        }
    }

    func testDialogueAndParentheticalsContinueWithOneBreak() {
        for source in ["MARA\nPlease stay.", "MARA\n(quietly)", "MARA\nHello.\nI mean it.", "MARA\n", "MARA\nHello.\n"] {
            XCTAssertEqual(insertion(source), "\n", source)
        }
    }

    func testBlankSeparatorLeavesDialogueContext() {
        XCTAssertEqual(insertion("MARA\nHello.\n\n"), "\n\n")
        XCTAssertEqual(insertion("MARA\nHello.\n\nShe turns."), "\n\n")
    }

    func testUnicodeSelectionUsesItsStartingLineWithoutChangingSource() {
        let source = "INT. CAFÉ - DAY\n\nÉVA\nOlá, mundo.\n\nShe leaves."
        let text = source as NSString
        let selection = text.range(of: "Olá, mundo.")
        XCTAssertEqual(FountainEditing.returnInsertion(in: source, selection: selection), "\n")
        XCTAssertEqual(source, "INT. CAFÉ - DAY\n\nÉVA\nOlá, mundo.\n\nShe leaves.")
        let middle = text.range(of: "She leaves.").location + 3
        XCTAssertEqual(FountainEditing.returnInsertion(in: source, selection: NSRange(location: middle, length: 0)), "\n\n")
    }

    func testExistingLocalLineEndingsArePreserved() {
        XCTAssertEqual(insertion("INT. ROOM - DAY\r\n\r\nShe waits."), "\r\n\r\n")
        XCTAssertEqual(insertion("INT. ROOM - DAY\r\n\r\nMARA"), "\r\n")
        XCTAssertEqual(insertion("MARA\r\nHello."), "\r\n")
        XCTAssertEqual(insertion("INT. ROOM - DAY\r\rShe waits."), "\r\r")
        XCTAssertEqual(insertion("First.\r\n\r\nSecond.\n\nThird."), "\n\n")
    }

    func testSelectionAfterAstralCharactersUsesUTF16OffsetsAndLocalCRLF() {
        let source = "INT. CAFÉ - DAY\r\n\r\nA 🐇 crosses the room.\r\n\r\n@Éva\r\nOlá, 👋 mundo.\r\n\r\nShe leaves."
        let text = source as NSString
        let selected = text.range(of: "Olá, 👋 mundo.")
        XCTAssertEqual(FountainEditing.returnInsertion(in: source, selection: selected), "\r\n")
        let replacement = text.replacingCharacters(in: selected, with: "\r\n")
        XCTAssertTrue(replacement.contains("A 🐇 crosses the room."))
        XCTAssertTrue(replacement.hasSuffix("She leaves."))
        let crossBlock = NSRange(location: selected.location, length: text.length - selected.location)
        XCTAssertEqual(FountainEditing.returnInsertion(in: source, selection: crossBlock), "\r\n")
    }

    func testNegativeLengthAndLocationPastEndUseSafeFallback() {
        XCTAssertEqual(FountainEditing.returnInsertion(in: "Éva 👋", selection: NSRange(location: 0, length: -1)), "\n\n")
        XCTAssertEqual(FountainEditing.returnInsertion(in: "Éva 👋", selection: NSRange(location: 100, length: 0)), "\n\n")
    }

    func testInvalidSelectionsDoNotCrash() {
        XCTAssertEqual(FountainEditing.returnInsertion(in: "Hi", selection: NSRange(location: -1, length: 0)), "\n\n")
        XCTAssertEqual(FountainEditing.returnInsertion(in: "Hi", selection: NSRange(location: NSNotFound, length: 0)), "\n\n")
        XCTAssertEqual(FountainEditing.returnInsertion(in: "Hi", selection: NSRange(location: 1, length: 99)), "\n\n")
    }
}

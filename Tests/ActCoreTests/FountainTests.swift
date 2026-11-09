import Foundation
import Testing
@testable import ActCore

struct FountainTests {
    @Test func preservesRawSourceAndUnicodeRanges() {
        let source = "Title: A film\r\nAuthor: Léo\r\n\r\nINT. CAFÉ - NIGHT\r\n\r\nA 🐇 waits.\r\n\r\n@Éva\r\n(quietly)\r\nOlá.\r\n"
        let parsed = FountainParser.parse(source)
        #expect(parsed.source == source)
        let ns = source as NSString
        for element in parsed.elements { #expect(ns.substring(with: element.range) == element.text) }
        #expect(parsed.scenes.count == 1)
        #expect(parsed.elements.contains { $0.kind == .character && $0.text == "@Éva" })
        #expect(parsed.elements.contains { $0.kind == .parenthetical })
        #expect(parsed.elements.contains { $0.kind == .dialogue && $0.text == "Olá." })
        #expect(parsed.scenes[0].text.hasSuffix("Olá.\r\n"))
    }

    @Test func recognisesFountainControls() {
        let source = "Title: TEST\n    Continued title\n\n# ACT ONE\n= Opening\n\n.INTRODUCTION\n\n!LOUD ACTION\n\nALICE\nHello.\n\nBOB ^\nHi.\n\n> CUT TO:\n\n> THE END <\n\n[[A note\ncontinued]]\n\n/* Hidden\nINT. FALSE - DAY\n*/\n\n===\n\nEXT. PARK - DAY #2#\n"
        let parsed = FountainParser.parse(source)
        #expect(parsed.scenes.count == 2)
        #expect(parsed.scenes[0].heading == "INTRODUCTION")
        #expect(parsed.elements.filter { $0.kind == .titlePage }.count == 2)
        #expect(parsed.elements.contains { $0.kind == .character && $0.isDualDialogue })
        #expect(parsed.elements.contains { $0.kind == .transition })
        #expect(parsed.elements.contains { $0.kind == .centred })
        #expect(parsed.elements.filter { $0.kind == .note }.count == 2)
        #expect(parsed.elements.filter { $0.kind == .boneyard }.count == 3)
        #expect(parsed.elements.contains { $0.kind == .pageBreak })
    }

    @Test func sceneIDsSurviveOutsideEdits() {
        let original = "INT. ROOM - DAY\n\nOne.\n\nEXT. ROAD - NIGHT\n\nTwo.\n"
        let first = FountainParser.parse(original)
        let edited = FountainParser.parse("Title: Changed\n\n" + original.replacingOccurrences(of: "One.", with: "A much longer opening."))
        #expect(first.scenes.map(\.id) == edited.scenes.map(\.id))
        #expect(first.scenes[1].range.location != edited.scenes[1].range.location)
    }

    @Test func repeatedHeadingsRemainDistinct() {
        let parsed = FountainParser.parse("INT. ROOM - DAY\n\nA.\n\nINT. ROOM - DAY\n\nB.")
        #expect(Set(parsed.scenes.map(\.id)).count == 2)
        #expect(parsed.scenes.map(\.text).joined() == parsed.source)
    }

    @Test func explicitSceneNumberSurvivesHeadingRename() {
        let a = FountainParser.parse("INT. ROOM - DAY #12#\n\nA.")
        let b = FountainParser.parse("EXT. PARK - NIGHT #12#\n\nA.")
        #expect(a.scenes[0].id == b.scenes[0].id)
    }

    @Test func recognisesSpaceHeadingsAndMixedCaseExtensions() {
        let parsed = FountainParser.parse("INT ROOM - DAY\n\nHANS (on the radio)\nHello.\n\n...an ellipsis.")
        #expect(parsed.scenes.count == 1)
        #expect(parsed.elements.contains { $0.kind == .character && $0.text == "HANS (on the radio)" })
        #expect(parsed.elements.last?.kind == .action)
    }

    @Test func inlineMultilineCommentsNeverCreateScenes() {
        let source = "INT. REAL - DAY\n\nÉva waits. /* hidden\n\nINT. FAKE - NIGHT\n\nmore hidden */ She leaves.\n\nA [[private\n\nEXT. FALSE - DAY\n\nnote]] visible ending."
        let parsed = FountainParser.parse(source)
        #expect(parsed.source == source)
        #expect(parsed.scenes.count == 1)
        #expect(parsed.scenes[0].heading == "INT. REAL - DAY")
        let visible = parsed.elements.map(FountainParser.displayText).joined(separator: "\n")
        #expect(visible.contains("Éva waits."))
        #expect(visible.contains("She leaves."))
        #expect(visible.contains("visible ending."))
        #expect(!visible.contains("FAKE"))
        #expect(!visible.contains("FALSE"))
        #expect(!visible.contains("private"))
        let ns = source as NSString
        for element in parsed.elements { #expect(ns.substring(with: element.range) == element.text) }
    }

    @Test func inlineClosedAndUnclosedCommentsPreserveVisibleAction() {
        let parsed = FountainParser.parse("Éva [[private]] walks /* hidden */ away.\n\nA final action [[unclosed\nINT. HIDDEN - DAY")
        #expect(parsed.elements.first?.kind == .action)
        #expect(parsed.elements.first.map(FountainParser.displayText) == "Éva  walks  away.")
        #expect(parsed.scenes.isEmpty)
        #expect(parsed.elements.last?.kind == .note)
        #expect(parsed.elements.last.map(FountainParser.displayText) == "")
    }

    @Test func emptyAndFinalLine() {
        #expect(FountainParser.parse("").elements.isEmpty)
        let parsed = FountainParser.parse("An action without final newline")
        #expect(parsed.elements.count == 1)
        #expect(parsed.elements[0].kind == .action)
        #expect(parsed.elements[0].range.length == 31)
    }
}

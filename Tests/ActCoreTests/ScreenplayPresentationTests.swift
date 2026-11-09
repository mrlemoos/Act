import Foundation
import Testing
@testable import ActCore

struct ScreenplayPresentationTests {
    @Test func sameSpeakerResumesAfterActionWithoutSourceMutation() {
        let source = "INT. ROOM - DAY\n\nALICE\nHello.\n\nA clock ticks.\n\nALICE\nGoodbye."
        let screenplay = FountainParser.parse(source)
        let characters = screenplay.elements.filter { $0.kind == .character }
        let cues = ScreenplayPresentation.characterCues(in: screenplay)
        #expect(cues[characters[0].range.location] == "ALICE")
        #expect(cues[characters[1].range.location] == "ALICE (CONT'D)")
        #expect(screenplay.source == source)
        #expect(characters[1].text == "ALICE")
    }

    @Test func differentSpeakerAndNewSceneResetContinuations() {
        let source = "INT. ROOM - DAY\n\nALICE\nHello.\n\nAction.\n\nBOB\nHi.\n\nALICE\nGoodbye.\n\nEXT. ROOM - DAY\n\nALICE\nOutside."
        let cues = ScreenplayPresentation.characterCues(in: FountainParser.parse(source))
        #expect(!cues.values.contains { $0.contains("CONT'D") })
    }

    @Test func sluglineSpacingCountsExistingSourceBlankLines() {
        let source = "INT. ROOM - DAY\n\nAction.\n\nEXT. ROAD - DAY\n\nAction.\n\n\nINT. CAFE - DAY\n\nAction."
        let screenplay = FountainParser.parse(source)
        let missing = ScreenplayPresentation.missingBlankLinesBeforeSluglines(in: screenplay)
        #expect(missing[screenplay.scenes[0].range.location] == 0)
        #expect(missing[screenplay.scenes[1].range.location] == 1)
        #expect(missing[screenplay.scenes[2].range.location] == 0)
        var settings = ScreenplaySettings.standard
        settings.blankLinesBeforeSlugline = 1
        #expect(ScreenplayPresentation.missingBlankLinesBeforeSluglines(in: screenplay, settings: settings)[screenplay.scenes[1].range.location] == 0)
    }

    @Test func explicitContinuationsAreNotDuplicatedAndCanBeDisabled() {
        #expect(ScreenplayPresentation.continuationCue("ALICE (CONT'D)") == "ALICE (CONT'D)")
        #expect(ScreenplayPresentation.continuationCue("ALICE (CONT’D)") == "ALICE (CONT’D)")
        #expect(ScreenplayPresentation.continuationCue("ALICE (V.O.)") == "ALICE (V.O.) (CONT'D)")
        let source = "INT. ROOM - DAY\n\nALICE\nHello.\n\nA clock ticks.\n\nALICE\nGoodbye."
        var settings = ScreenplaySettings.standard
        settings.dialogueContinuations = false
        #expect(!ScreenplayPresentation.characterCues(in: FountainParser.parse(source), settings: settings).values.contains { $0.contains("CONT'D") })
    }
    @Test func explicitAndImplicitCueContinuationsCoexistWithUnicodeExtensions() {
        let source = "INT. CAFÉ - DAY\n\nA 🐇 crosses the room.\n\n@Éva (V.O.)\nOlá.\n\nShe turns.\n\n@Éva (V.O.) (CONT'D)\nAgain.\n\nShe waits.\n\n@Éva (V.O.)\nFinally."
        let screenplay = FountainParser.parse(source)
        let characters = screenplay.elements.filter { $0.kind == .character }
        let cues = ScreenplayPresentation.characterCues(in: screenplay)
        #expect(characters.count == 3)
        #expect(cues[characters[1].range.location] == "Éva (V.O.) (CONT'D)")
        #expect(cues[characters[2].range.location] == "Éva (V.O.) (CONT'D)")
        for character in characters {
            #expect((source as NSString).substring(with: character.range) == character.text)
            #expect((cues[character.range.location] ?? "").components(separatedBy: "CONT'D").count <= 2)
        }
        var disabled = ScreenplaySettings.standard
        disabled.dialogueContinuations = false
        let rawCues = ScreenplayPresentation.characterCues(in: screenplay, settings: disabled)
        #expect(rawCues[characters[1].range.location] == "Éva (V.O.) (CONT'D)")
        #expect(rawCues[characters[2].range.location] == "Éva (V.O.)")
    }

    @Test func notesAndOutlineDoNotInventActionInterruptions() {
        let screenplay = FountainParser.parse("INT. ROOM - DAY\n\nALICE\nHello.\n\n[[a private note]]\n= A planning beat\n\nALICE\nAgain.")
        let cues = ScreenplayPresentation.characterCues(in: screenplay)
        #expect(cues.count == 2)
        #expect(cues.values.allSatisfy { $0 == "ALICE" })
    }

}

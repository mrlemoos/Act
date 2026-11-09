import AppKit
import Foundation
import PDFKit
import Testing
@testable import ActCore

@MainActor
struct PDFTests {
    @Test func exportsTitleAndBodyWithUnicode() throws {
        let source = "Title: Café\nAuthor: Léo\n\nINT. CAFÉ - NIGHT\n\nÉva waits.\n\nÉVA\nOlá, mundo.\n"
        let bytes = try ScreenplayPDF.data(source: source)
        let document = try #require(PDFDocument(data: bytes))
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.string?.contains("Café") == true)
        #expect(document.page(at: 1)?.string?.contains("Olá, mundo.") == true)
        #expect(document.page(at: 1)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
    }

    @Test func longActionPaginatesWithinMargins() throws {
        let source = "INT. ROOM - DAY\n\n" + String(repeating: "A long action paragraph crosses the room without stopping. ", count: 600)
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.count > 2)
        for page in pages {
            for line in page.lines {
                #expect(line.baseline >= 72 && line.baseline <= 720)
                #expect(line.x >= 108 && line.x <= 540)
            }
        }
        #expect(try #require(PDFDocument(data: ScreenplayPDF.data(source: source))).pageCount == pages.count)
    }

    @Test func hidesProductionNotesAndControlSyntax() throws {
        let source = "# Sequence\n= Synopsis\n\n.INTRO #4#\n\n!A **bold** arrival. [[private note]]\n\n[[secret]]\n\n/* hidden */\n\n> THE END <"
        let document = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        let text = document.string ?? ""
        #expect(text.contains("A bold arrival."))
        #expect(!text.contains("private"))
        #expect(!text.contains("secret"))
        #expect(!text.contains("hidden"))
        #expect(!text.contains("Synopsis"))
        #expect(!text.contains("#4#"))
    }

    @Test func dualDialogueUsesParallelColumns() {
        let pages = ScreenplayPDF.layout(source: "INT. ROOM - DAY\n\nALICE\nHello.\n\nBOB ^\nGoodbye.")
        let lines = pages.flatMap(\.lines)
        let alice = lines.first { $0.text == "ALICE" }
        let bob = lines.first { $0.text == "BOB" }
        #expect(alice?.baseline == bob?.baseline)
        #expect((alice?.x ?? 0) < (bob?.x ?? 0))
    }

    @Test func inlineMultilineCommentsStayOutOfPDF() throws {
        let source = "INT. ROOM - DAY\n\nÉva waits. /* hidden\n\nINT. FALSE - DAY\n\nsecret */ She leaves.\n\nA [[private\nnote]] visible ending."
        let document = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        let text = document.string ?? ""
        #expect(text.contains("Éva waits."))
        #expect(text.contains("She leaves."))
        #expect(text.contains("visible ending."))
        for hidden in ["FALSE", "hidden", "secret", "private", "note]]"] { #expect(!text.contains(hidden)) }
    }

    @Test func longTitleAndContactPaginateWithoutOverflow() {
        let source = "Title: " + String(repeating: "A remarkably long title ", count: 200) + "\nContact:\n" + String(repeating: "    A contact address line\n", count: 120) + "\nINT. ROOM - DAY\n\nAction."
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.filter(\.isTitlePage).count > 2)
        for page in pages {
            for line in page.lines { #expect(line.baseline >= 72 && line.baseline <= 720) }
        }
        #expect(pages.last?.isTitlePage == false)
        #expect(pages.last?.lines.contains { $0.text == "Action." } == true)
    }

    @Test func headingSettingsControlExactSpacingAndWeight() {
        let source = "INT. ROOM - DAY\n\nAction.\n\n\n\nEXT. ROAD - DAY\n\nMore action."
        var single = ScreenplaySettings.standard
        single.blankLinesBeforeSlugline = 1
        single.boldSluglines = false
        let singleLines = ScreenplayPDF.layout(source: source, settings: single).flatMap(\.lines)
        let doubleLines = ScreenplayPDF.layout(source: source).flatMap(\.lines)
        let action = singleLines.first { $0.text == "Action." }!
        let singleHeading = singleLines.first { $0.text == "EXT. ROAD - DAY" }!
        let doubleHeading = doubleLines.first { $0.text == "EXT. ROAD - DAY" }!
        #expect(singleHeading.baseline - action.baseline == 24)
        #expect(doubleHeading.baseline - action.baseline == 36)
        #expect(!singleHeading.bold)
        #expect(doubleHeading.bold)
        #expect(source.contains("\n\n\n\nEXT."))
    }

    @Test func selectedFontAndSizeAffectExportAndWrapping() throws {
        let source = "INT. ROOM - DAY\n\n" + String(repeating: "A meaningful sentence fills the room. ", count: 12)
        var settings = ScreenplaySettings.standard
        settings.fontName = "Helvetica"
        settings.fontSize = 20
        let bytes = try ScreenplayPDF.data(source: source, settings: settings)
        let document = try #require(PDFDocument(data: bytes))
        let attributed = try #require(document.page(at: 0)?.attributedString)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.familyName == "Helvetica")
        #expect(abs(font.pointSize - 20) < 0.1)
        let baseline = ScreenplayPDF.layout(source: source, settings: settings).flatMap(\.lines)
        #expect(baseline.count > ScreenplayPDF.layout(source: source).flatMap(\.lines).count)
    }

    @Test func repeatedCueIsDisplayOnlyAndRespectsSetting() {
        let source = "INT. ROOM - DAY\n\nALICE\nHello.\n\nThe clock ticks.\n\nALICE\nGoodbye."
        let lines = ScreenplayPDF.layout(source: source).flatMap(\.lines)
        #expect(lines.contains { $0.text == "ALICE (CONT'D)" })
        var settings = ScreenplaySettings.standard
        settings.dialogueContinuations = false
        #expect(!ScreenplayPDF.layout(source: source, settings: settings).flatMap(\.lines).contains { $0.text.contains("CONT'D") })
        #expect(!source.contains("CONT'D"))
    }

    @Test func dialoguePageBreakAddsMoreAndContinuedCue() {
        let source = "INT. ROOM - DAY\n\nALICE\n" + String(repeating: "This dialogue continues for several pages. ", count: 180)
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.count > 2)
        for index in 0..<(pages.count - 1) {
            #expect(pages[index].lines.last?.text == "(MORE)")
            #expect(pages[index + 1].lines.first?.text == "ALICE (CONT'D)")
        }
        for page in pages {
            for line in page.lines { #expect(line.baseline <= 720) }
        }
        var settings = ScreenplaySettings.standard
        settings.dialogueContinuations = false
        let disabled = ScreenplayPDF.layout(source: source, settings: settings).flatMap(\.lines)
        #expect(!disabled.contains { $0.text.contains("(MORE)") || $0.text.contains("CONT'D") })
    }

    @Test func dualDialoguePageBreakRepeatsEachActiveSpeaker() {
        let speech = String(repeating: "A lengthy overlapping speech. ", count: 160)
        let source = "INT. ROOM - DAY\n\nALICE\n" + speech + "\n\nBOB ^\n" + speech
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.count > 1)
        let next = pages[1].lines
        #expect(next.contains { $0.text.contains("ALICE") })
        #expect(next.contains { $0.text.contains("BOB") })
        #expect(next.filter { $0.text.contains("CONT'D") }.count >= 2)
        for page in pages {
            for line in page.lines { #expect(line.baseline <= 720) }
        }
    }

    @Test func characterCueStaysWithDialogue() {
        let source = "INT. ROOM - DAY\n\n" + Array(repeating: "Action.", count: 51).joined(separator: "\n") + "\n\nALICE\nHello."
        let pages = ScreenplayPDF.layout(source: source)
        for page in pages {
            if let index = page.lines.firstIndex(where: { $0.text == "ALICE" }) {
                #expect(index + 1 < page.lines.count)
                #expect(page.lines[index + 1].text == "Hello.")
            }
        }
    }
    @Test func explicitContinuationIsNeverDuplicatedAcrossPagesOrRemovedWhenDisabled() {
        let source = "INT. ROOM - DAY\n\nALICE (CONT'D)\n" + String(repeating: "Her account runs across the page. ", count: 150)
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.count > 1)
        for page in pages {
            let cues = page.lines.filter { $0.text.hasPrefix("ALICE") }
            #expect(cues.count == 1)
            #expect(cues[0].text == "ALICE (CONT'D)")
        }
        var settings = ScreenplaySettings.standard
        settings.dialogueContinuations = false
        let disabled = ScreenplayPDF.layout(source: source, settings: settings)
        #expect(disabled[0].lines.contains { $0.text == "ALICE (CONT'D)" })
        #expect(!disabled.dropFirst().flatMap(\.lines).contains { $0.text.contains("CONT'D") || $0.text == "(MORE)" })
    }

    @Test func longCueAndLargestFontKeepTextWithinPageBoundsAndPreserveFinalBeat() {
        let cue = String(repeating: "ALEXANDRA ", count: 6).trimmingCharacters(in: .whitespaces)
        let source = "INT. ROOM - DAY\n\n" + Array(repeating: "Action.", count: 12).joined(separator: "\n") + "\n\n" + cue + "\n" + String(repeating: "A careful account continues. ", count: 100) + " LASTBEAT."
        var settings = ScreenplaySettings.standard
        settings.fontSize = 24
        let pages = ScreenplayPDF.layout(source: source, settings: settings)
        #expect(pages.count > 2)
        #expect(pages.last?.lines.last?.text.hasSuffix("LASTBEAT.") == true)
        for page in pages {
            #expect(!page.lines.isEmpty)
            for line in page.lines {
                #expect(line.baseline >= 72 && line.baseline <= 720)
                let font = NSFont(name: line.bold ? "Courier-Bold" : "Courier", size: 24)!
                let width = (line.text as NSString).size(withAttributes: [.font: font]).width
                #expect(line.x >= 108 && line.x + width <= 540.1)
            }
        }
    }

    @Test func unavailableFontFallsBackAndInvalidSettingsStayWithinBounds() throws {
        let source = "INT. ROOM - DAY\n\nAction."
        let settings = ScreenplaySettings(fontName: "ActTests-NonexistentFont-49D42", fontSize: .nan, blankLinesBeforeSlugline: -1)
        let document = try #require(PDFDocument(data: ScreenplayPDF.data(source: source, settings: settings)))
        let attributed = try #require(document.page(at: 0)?.attributedString)
        let font = try #require(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.familyName == "Courier")
        #expect(abs(font.pointSize - 12) < 0.1)
        #expect(ScreenplayPDF.layout(source: source, settings: settings).flatMap(\.lines).allSatisfy { $0.baseline.isFinite && $0.baseline <= 720 })
    }

}

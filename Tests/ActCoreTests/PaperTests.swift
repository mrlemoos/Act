import AppKit
import PDFKit
import Testing
@testable import ActCore

@MainActor
struct PaperTests {
    @Test func paperMetadataNeverCreatesACoverOrLeaksIntoBody() throws {
        let source = "Paper: A4\n\nINT. ROOM - DAY\n\nHello."
        let parsed = FountainParser.parse(source)
        #expect(parsed.elements.first?.kind == .titlePage)
        let pdf = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        #expect(pdf.pageCount == 1)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == ScreenplayPaper.a4.size)
        #expect(pdf.string?.contains("Paper:") == false)
        #expect(pdf.string?.contains("Hello.") == true)
    }

    @Test func metadataUpdatesPreserveUnicodeBodyAndLineEndings() {
        for newline in ["\n", "\r\n", "\r"] {
            let body = "INT. CAFÉ - DAY" + newline + newline + "Léo waits.  " + newline
            #expect(ScreenplayPaper.a4.updating(body) == "Paper: A4" + newline + newline + body)
            let source = "Title: Café" + newline + "Paper: unknown" + newline + "Author: Léo" + newline + newline + body
            let updated = ScreenplayPaper.a4.updating(source)
            #expect(updated == source.replacingOccurrences(of: "Paper: unknown", with: "Paper: A4"))
            #expect(ScreenplayPaper.a4.updating(updated) == updated)
            #expect(ScreenplayPaper.read(from: updated) == .a4)
        }
        #expect(ScreenplayPaper.usLetter.updating("Paper: bad") == "Paper: US Letter")
        #expect(ScreenplayPaper.a4.updating("Paper:\n    bad\nPaper: US Letter\n\nAction.") == "Paper: A4\n\nAction.")
    }

    @Test func absentUnknownAndBodyPaperFieldsUseLetterWithoutMutation() {
        for source in ["Action.", "Paper: Unknown\n\nAction.", "INT. ROOM - DAY\n\nPaper: A4"] {
            #expect(ScreenplayPaper.read(from: source) == .usLetter)
        }
        #expect(ScreenplayPaper.read(from: "paper: a4\n\nAction.") == .a4)
    }

    @Test func standardTitleLayoutGroupsFieldsAndKeepsColonsInContinuations() throws {
        let source = "Contact:\n    Léo\n    https://example.com\nAuthor: Léo\nTitle:\n    A Film: Part Two\nCredit: Written by\nPaper: A4\n\nINT. ROOM - DAY\n\nAction."
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.count == 2)
        let title = try #require(pages.first)
        #expect(title.isTitlePage)
        #expect(title.lines.map(\.text) == ["A Film: Part Two", "Written by", "Léo", "Léo", "https://example.com"])
        #expect(title.lines.first?.bold == true)
        #expect(title.lines.suffix(2).allSatisfy { $0.x == 108 })
        #expect(title.lines.last?.baseline == ScreenplayPaper.a4.size.height - 72)
        let pdf = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        #expect(pdf.page(at: 0)?.string?.contains("https://example.com") == true)
    }

    @Test func a4LongContentPreservesMarginsAndBodyNumbering() throws {
        let source = "Paper: A4\nTitle: " + String(repeating: "A long title ", count: 300) + "\nContact:\n" + String(repeating: "    Address: Madrid\n", count: 90) + "\nINT. ROOM - DAY\n\n" + String(repeating: "The rain keeps falling. ", count: 1600) + "FINAL BEAT."
        let pages = ScreenplayPDF.layout(source: source)
        #expect(pages.filter(\.isTitlePage).count > 1)
        #expect(pages.allSatisfy { $0.lines.allSatisfy { $0.baseline >= 72 && $0.baseline <= ScreenplayPaper.a4.size.height - 72 } })
        let pdf = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        #expect(pdf.string?.contains("FINAL BEAT.") == true)
        let firstBody = pages.firstIndex { !$0.isTitlePage }!
        #expect(pdf.page(at: firstBody)?.string?.hasPrefix("1.") == false)
        #expect(pdf.page(at: firstBody + 1)?.string?.contains("2.") == true)
    }
}

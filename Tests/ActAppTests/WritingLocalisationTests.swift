import ActCore
import AppKit
import PDFKit
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct WritingLocalisationTests {
    @Test func nativeEditorLocalisesAccessibilityWithoutChangingSourceOrPDFText() throws {
        let source = "Title: Café\r\nPaper: US Letter\r\n\r\nINT. KITCHEN - DAY\r\n\r\nMARA\r\nStay for coffee.\r\n\r\nShe waits.\r\n\r\nMARA\r\nPlease."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        #expect(host.textView.accessibilityLabel() == L10n.string("Screenplay editor", table: "Writing"))
        #expect(host.textView.string == source)
        #expect(try host.document.data(ofType: "dev.act.fountain") == Data(source.utf8))
        let pdf = try #require(PDFDocument(data: ScreenplayPDF.data(source: source)))
        #expect(pdf.string?.contains("INT. KITCHEN - DAY") == true)
        #expect(pdf.string?.contains("Stay for coffee.") == true)
        #expect(pdf.string?.contains("Please.") == true)
        #expect(ScreenplayPaper.read(from: source) == .usLetter)
    }

    @Test func interfaceFormatsKeepUserTextLiteralInEveryLocale() {
        let synopsis = "Léo's 100% café %@"
        for locale in L10n.supportedLocales {
            let value = L10n.format("Synopsis: %@", synopsis, table: "Writing", locale: locale)
            #expect(value.hasSuffix(synopsis))
            #expect(value != "Synopsis: %@")
            #expect(L10n.format("Character: %@", synopsis, table: "Writing", locale: locale).hasSuffix(synopsis))
        }
        #expect(L10n.string("Screenplay editor", table: "Writing", locale: "pt-BR") == "Editor de roteiro")
        #expect(L10n.string("Screenplay editor", table: "Writing", locale: "ja-JP") == "Screenplay editor")
    }

    @Test func paperDisplayNamesNeverBecomeStoredMetadata() {
        for locale in L10n.supportedLocales {
            #expect(!L10n.string(ScreenplayPaper.usLetter.rawValue, table: "Writing", locale: locale).isEmpty)
            let source = ScreenplayPaper.usLetter.updating("INT. CAFÉ - DAY\r\n\r\nLéo waits.")
            #expect(source.hasPrefix("Paper: US Letter\r\n\r\n"))
            #expect(ScreenplayPaper.read(from: source) == .usLetter)
        }
        #expect(L10n.string("US Letter", table: "Writing", locale: "es-ES") == "Carta EE. UU.")
    }
}

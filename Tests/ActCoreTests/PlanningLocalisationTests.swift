import Foundation
import Testing
@testable import ActCore

struct PlanningLocalisationTests {
    @Test func libraryBoundaryErrorsUseInterfaceCopyWithoutChangingLibrary() throws {
        var library = CharacterLibrary()
        let source = "ORLEANS waits."
        let range = NSRange(location: 0, length: 7)
        try library.mark(source: source, selection: range)
        let marked = library
        do {
            try library.mark(source: source, selection: range)
            Issue.record("An already marked occurrence must be rejected")
        } catch {
            #expect(error.localizedDescription == L10n.string("This occurrence is already marked.", table: "Characters"))
        }
        #expect(library == marked)

        library.characters[0].prompt = String(repeating: "x", count: 16_777_217)
        let prompt = library.characters[0].prompt
        do {
            _ = try CharacterLibraryStore.data(library)
            Issue.record("Oversized metadata must be rejected")
        } catch {
            #expect(error.localizedDescription == L10n.string("The character library exceeds its 16 MB metadata limit. Save a separate screenplay copy before adding more history.", table: "Characters"))
        }
        #expect(library.characters[0].prompt == prompt)
        #expect(L10n.string("This occurrence is already marked.", table: "Characters", locale: "pt-BR") == "Esta ocorrência já está marcada.")
    }

    @Test func interfaceTranslationsPreserveLiteralValuesAndDiagnostics() {
        let literal = "ORLEANS, 100% prêt. %@ / café / Hände"
        for locale in L10n.supportedLocales {
            let diagnostic = L10n.format("Local generation failed. %@", literal, table: "Shots", locale: locale)
            #expect(diagnostic.hasSuffix(literal))
            let source = L10n.format("Source: %@", literal, table: "Characters", locale: locale)
            #expect(source.hasSuffix(literal))
            let label = L10n.format("Active reference sheet for %@", literal, table: "Characters", locale: locale)
            #expect(label.hasSuffix(literal))
        }
        #expect(L10n.string("Cancel", table: "Shots", locale: "pt-BR") == "Cancelar")
        #expect(L10n.string("Cancel", table: "Characters", locale: "de-DE") == "Abbrechen")
        #expect(L10n.format("Shot %d framing", 3, table: "Shots", locale: "es-ES") == "Encuadre del plano 3")
    }

    @Test func translatedTraitLabelsDoNotRewriteStoredEvidenceOrPrompts() throws {
        var library = CharacterLibrary()
        let source = "ORLEANS has grey hair."
        let id = try library.mark(source: source, selection: NSRange(location: 0, length: 7))
        let index = try #require(library.characters.firstIndex { $0.id == id })
        library.characters[index].marks[0].traits = [
            PhysicalTrait(attribute: "hair color", value: "grey", evidence: "grey hair"),
            PhysicalTrait(attribute: "hair color", value: "black", evidence: "black hair")
        ]
        library.characters[index].prompt = "Literal prompt. Preserve grey, %@ and 100%."
        let original = try CharacterLibraryStore.data(library)
        let suggestedPrompt = library.characters[index].suggestedPrompt
        for locale in L10n.supportedLocales {
            let title = PhysicalTrait.attributeTitle("hair color", locale: locale)
            let conflicts = library.characters[index].displayedContradictions(locale: locale)
            #expect(conflicts == [title + ": black / grey"])
            #expect(library.characters[index].marks[0].traits[0].attribute == "hair color")
            #expect(library.characters[index].marks[0].traits[0].value == "grey")
            #expect(library.characters[index].marks[0].traits[0].evidence == "grey hair")
            #expect(library.characters[index].suggestedPrompt == suggestedPrompt)
            #expect(try CharacterLibraryStore.data(library) == original)
        }
        #expect(PhysicalTrait.attributeTitle("hair color", locale: "pt-BR") == "Cor do cabelo")
        #expect(PhysicalTrait.attributeTitle("hair colour", locale: "en-US") == "Hair color")
        #expect(PhysicalTrait.attributeTitle("bespoke attribute", locale: "fr-FR") == "bespoke attribute")
    }

    @Test func shotInterfaceFormattingPreservesDocumentBytes() throws {
        let source = "INT. KITCHEN - DAY\r\n\r\nMARA\r\nAção, café, 100%.\r\n"
        let anchor = SceneAnchor(id: "scene", heading: "INT. KITCHEN - DAY", text: source)
        let document = ShotListDocument(title: "My shots", source: source, anchors: [anchor], shots: [
            Shot(sceneID: anchor.id, framing: "Wide", action: "Literal action", cameraMovement: "Static", rationale: "Keep this")
        ])
        let original = try ShotListStore.data(for: document)
        for locale in L10n.supportedLocales {
            #expect(!L10n.format("Generated %d shot. Review and edit before saving.", 1, table: "Shots", locale: locale).contains("%d"))
            #expect(!L10n.format("Generated %d shots. Review and edit before saving.", 2, table: "Shots", locale: locale).contains("%d"))
            #expect(try ShotListStore.data(for: document) == original)
        }
        #expect(CharacterImageAgent.verificationPrompt.contains("grey cube"))
        #expect(CharacterImageAgent.editingVerificationPrompt.contains("grey cube"))
    }
}

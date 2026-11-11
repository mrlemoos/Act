import Foundation
import Testing
@testable import ActCore

struct BoardLocalisationTests {
    @Test func newAssetTitlesUseLocaleAndPreserveExistingAssetRecords() throws {
        let examples: [(String, String, String)] = [
            ("en-GB", "Character sheets", "Shot list"),
            ("en-US", "Character sheets", "Shot list"),
            ("pt-BR", "Fichas de personagens", "Lista de planos"),
            ("es-ES", "Fichas de personajes", "Lista de planos"),
            ("fr-FR", "Fiches de personnages", "Liste des plans"),
            ("de-DE", "Figurenblätter", "Einstellungsliste"),
            ("it-IT", "Schede dei personaggi", "Inquadrature")
        ]
        var existing = ProjectBoard()
        existing.cards = [BoardCard(kind: .characters, title: "Character sheets"), BoardCard(kind: .shots, title: "My selected shots")]
        let saved = try ProjectBoardStore.data(existing)
        for (locale, characters, shots) in examples {
            #expect(BoardPresentation.defaultAssetTitle(.characters, locale: locale) == characters)
            #expect(BoardPresentation.defaultAssetTitle(.shots, locale: locale) == shots)
            #expect(shots == L10n.string("Shot list", table: "Writing", locale: locale))
            #expect(try ProjectBoardStore.load(saved) == existing)
        }
    }

    @Test func newDefaultTitlesUseCurrentLanguageWithoutRetranslatingStoredTitles() throws {
        let expected: [(String, String, String)] = [
            ("en-GB", "Untitled beat", "Untitled group"),
            ("en-US", "Untitled beat", "Untitled group"),
            ("pt-BR", "Ideia sem título", "Grupo sem título"),
            ("es-ES", "Idea sin título", "Grupo sin título"),
            ("fr-FR", "Idée sans titre", "Groupe sans titre"),
            ("de-DE", "Unbenannte Idee", "Unbenannte Gruppe"),
            ("it-IT", "Idea senza titolo", "Gruppo senza titolo")
        ]
        for (locale, noteTitle, groupTitle) in expected {
            var board = ProjectBoard()
            board.cards = [BoardCard(kind: .note, title: BoardPresentation.defaultNoteTitle(locale: locale))]
            board.groups = [BoardGroup(title: BoardPresentation.defaultGroupTitle(locale: locale))]
            let saved = try ProjectBoardStore.data(board)
            _ = BoardPresentation.defaultNoteTitle(locale: "en-GB")
            _ = BoardPresentation.defaultGroupTitle(locale: "en-GB")
            let restored = try ProjectBoardStore.load(saved)
            #expect(restored.cards[0].title == noteTitle)
            #expect(restored.groups[0].title == groupTitle)
        }
    }

    @Test func sceneAndSharedDraftCountsUseTranslatedSingularAndPluralForms() {
        let examples: [(String, String, String, String, String)] = [
            ("en-GB", "1 scene", "2 scenes", "Shared reference · 1 other draft", "Shared reference · 2 other drafts"),
            ("en-US", "1 scene", "2 scenes", "Shared reference · 1 other draft", "Shared reference · 2 other drafts"),
            ("pt-BR", "1 cena", "2 cenas", "Referência compartilhada · 1 outro rascunho", "Referência compartilhada · 2 outros rascunhos"),
            ("es-ES", "1 escena", "2 escenas", "Referencia compartida · 1 otro borrador", "Referencia compartida · 2 otros borradores"),
            ("fr-FR", "1 scène", "2 scènes", "Référence partagée · 1 autre brouillon", "Référence partagée · 2 autres brouillons"),
            ("de-DE", "1 Szene", "2 Szenen", "Geteilte Referenz · 1 weiterer Entwurf", "Geteilte Referenz · 2 weitere Entwürfe"),
            ("it-IT", "1 scena", "2 scene", "Riferimento condiviso · 1 altra bozza", "Riferimento condiviso · 2 altre bozze")
        ]
        for (locale, singularScene, pluralScenes, singularDraft, pluralDrafts) in examples {
            #expect(BoardPresentation.sceneCount(1, locale: locale) == singularScene)
            #expect(BoardPresentation.sceneCount(2, locale: locale) == pluralScenes)
            #expect(BoardPresentation.sharedDraftCount(1, locale: locale) == singularDraft)
            #expect(BoardPresentation.sharedDraftCount(2, locale: locale) == pluralDrafts)
        }
        #expect(BoardPresentation.sceneCount(0, locale: "en-GB") == "0 scenes")
        #expect(BoardPresentation.sceneCount(0, locale: "fr-FR") == "0 scène")
        #expect(BoardPresentation.sceneCount(0, locale: "pt-BR") == "0 cena")
        #expect(BoardPresentation.sceneCount(0, locale: "es-ES") == "0 escenas")
    }

    @Test func translatedCardKindsNeverChangeStoredContentOrIdentifiers() throws {
        var board = ProjectBoard()
        var note = BoardCard(kind: .note, title: "Untitled beat")
        note.text = "Ação, Straße, scène, mañana."
        let draft = BoardCard(kind: .draft, title: "Meu roteiro.fountain", path: "/tmp/Meu roteiro.fountain")
        board.cards = [note, draft]
        let original = try ProjectBoardStore.data(board)

        #expect(BoardPresentation.kindTitle(.draft, locale: "pt-BR") == "Rascunho")
        #expect(BoardPresentation.kindTitle(.scene, locale: "fr-FR") == "Scène")
        #expect(BoardPresentation.kindTitle(.characters, locale: "de-DE") == "Figuren")
        #expect(BoardPresentation.kindTitle(.shots, locale: "it-IT") == "Inquadrature")
        #expect(BoardPresentation.kindTitle(.note, locale: "ja-JP") == "Note")
        #expect(try ProjectBoardStore.data(board) == original)
        #expect(try ProjectBoardStore.load(original) == board)
    }

    @Test func translatedReferenceActionsKeepFileNamesAndDiagnosticsLiteral() {
        let title = "Draft % %@ é.fountain"
        #expect(L10n.format("Relink %@", title, table: "Board", locale: "es-ES") == "Volver a vincular Draft % %@ é.fountain")
        let reason = "error(code: 42) /Users/leo/Draft.fountain"
        let translated = L10n.format("Cannot open linked shot list: %@ Save pending shot edits first.", reason, table: "Board", locale: "pt-BR")
        #expect(translated.contains(reason))
        #expect(translated.hasPrefix("Não foi possível abrir"))
    }
}

import Foundation
import Testing
@testable import ActCore

struct ProjectBoardTests {
    @Test func roundTripPreservesLayoutProvenanceNotesAndGroups() throws {
        var board = ProjectBoard()
        let draft = BoardCard(kind: .draft, title: "Draft.fountain", path: "/tmp/Draft.fountain")
        let group = BoardGroup(title: "Act I", position: BoardPoint(x: -20, y: 40))
        var note = BoardCard(kind: .note, title: "Opening", position: BoardPoint(x: 30, y: 120))
        note.groupID = group.id; note.text = "A quiet arrival."
        var asset = BoardCard(kind: .characters, title: "Sheets", draftID: draft.id)
        asset.sharedWith = [UUID()]
        board.cards = [draft, note, asset]; board.groups = [group]; board.zoom = 0.5
        let restored = try ProjectBoardStore.load(ProjectBoardStore.data(board))
        #expect(restored == board)
        #expect(restored.resolvedURL(for: asset)?.path == "/tmp/Draft.fountain")
    }
    @Test func movingGroupsMovesOnlyMembersAndRemovalRetainsReferences() {
        var board = ProjectBoard(); let group = BoardGroup(title: "Research")
        var member = BoardCard(kind: .note, title: "Inside"); member.groupID = group.id
        let outside = BoardCard(kind: .note, title: "Outside")
        board.groups = [group]; board.cards = [member, outside]
        board.moveGroup(group.id, by: BoardPoint(x: 50, y: -30))
        #expect(board.cards[0].position == BoardPoint(x: 50, y: -30))
        #expect(board.cards[1] == outside)
        board.removeCard(member.id)
        #expect(board.cards == [outside]); #expect(board.groups.count == 1)
    }
    @Test func changedMissingAndReorderedScenesNeverSilentlyRelink() throws {
        let source = "INT. ROOM - DAY #1#\n\nShe waits.\n\nEXT. ROAD - NIGHT #2#\n\nRain."
        let scene = try #require(FountainParser.parse(source).scenes.first)
        let card = BoardCard(kind: .scene, title: scene.heading,
            anchor: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text))
        let board = ProjectBoard()
        #expect(board.sceneState(for: card, source: source) == .current)
        #expect(board.sceneState(for: card, source: source.replacingOccurrences(of: "She waits.", with: "She leaves.")) == .changed)
        #expect(board.sceneState(for: card, source: "EXT. ROAD - NIGHT #2#\n\nRain.") == .missing)
    }
    @Test func navigationKeepsPinchAnchorFixedAndClampsZoom() {
        var board = ProjectBoard()
        board.pan = BoardPoint(x: 20, y: -40)
        let focus = BoardPoint(x: 300, y: 200)
        let world = BoardPoint(x: (focus.x - board.pan.x) / board.zoom, y: (focus.y - board.pan.y) / board.zoom)
        board.navigate(by: BoardPoint(), magnification: 1.5, around: focus)
        #expect(world.x * board.zoom + board.pan.x == focus.x)
        #expect(world.y * board.zoom + board.pan.y == focus.y)
        board.navigate(by: BoardPoint(), magnification: 100, around: focus)
        #expect(board.zoom == 2)
        board.navigate(by: BoardPoint(), magnification: 0.001, around: focus)
        #expect(board.zoom == 0.25)
        let prior = board.pan
        board.navigate(by: BoardPoint(x: 30, y: -20))
        #expect(board.pan == BoardPoint(x: prior.x + 30, y: prior.y - 20))
        let valid = board
        board.navigate(by: BoardPoint(x: .nan, y: 0))
        #expect(board == valid)
    }
    @Test func openPlanRoutesOwningDraftAndExplicitSharing() throws {
        let draftA = BoardCard(kind: .draft, title: "Alpha.fountain", path: "/tmp/Alpha.fountain")
        let draftB = BoardCard(kind: .draft, title: "Beta.fountain", path: "/tmp/Beta.fountain")
        var asset = BoardCard(kind: .characters, title: "Sheets", draftID: draftA.id)
        asset.sharedWith = [draftB.id]
        var shots = BoardCard(kind: .shots, title: "Plans", draftID: draftA.id, path: "/tmp/alpha-shots.json")
        let scene = BoardCard(kind: .scene, title: "INT. ROOM - DAY", draftID: draftA.id,
            anchor: SceneAnchor(id: "1", heading: "INT. ROOM - DAY", text: "She waits."))
        var board = ProjectBoard()
        board.cards = [draftA, draftB, asset, shots, scene]
        let characters = try #require(board.openPlan(for: asset))
        #expect(characters.screenplayURL.path == "/tmp/Alpha.fountain")
        #expect(characters.workspace == .characters)
        #expect(characters.shotListURL == nil)
        let shotPlan = try #require(board.openPlan(for: shots))
        #expect(shotPlan.screenplayURL.path == "/tmp/Alpha.fountain")
        #expect(shotPlan.workspace == .shots)
        #expect(shotPlan.shotListURL?.path == "/tmp/alpha-shots.json")
        board.toggleSharedReference(assetID: asset.id, draftID: draftB.id)
        #expect(board.cards.first { $0.id == asset.id }?.sharedWith.isEmpty == true)
        board.toggleSharedReference(assetID: asset.id, draftID: draftB.id)
        #expect(board.cards.first { $0.id == asset.id }?.sharedWith == [draftB.id])
        #expect(board.draftFileName(for: asset) == "Alpha.fountain")
        #expect(board.linkedSceneIDs(for: draftA.id) == ["1"])
    }

    @Test func relinkPathRestoresDraftTitleAndPreviewResolvesValidatedImages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ActBoard-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let screenplay = root.appendingPathComponent("Lead.fountain")
        try Data("INT. ROOM - DAY\n\nShe waits.".utf8).write(to: screenplay)
        let libraryDirectory = CharacterLibraryStore.directory(for: screenplay)
        try FileManager.default.createDirectory(at: libraryDirectory.appendingPathComponent("images"), withIntermediateDirectories: true)
        let imageURL = libraryDirectory.appendingPathComponent("images/sheet.png")
        try pngData().write(to: imageURL)
        var version = CharacterSheetVersion(imageFile: "images/sheet.png", prompt: "prompt", agent: "test")
        var character = CharacterReference(name: "Eva", colourIndex: 0)
        character.versions = [version]
        character.activeVersionID = version.id
        let library = CharacterLibrary(characters: [character])
        try CharacterLibraryStore.data(library).write(to: libraryDirectory.appendingPathComponent("characters.json"))
        let draft = BoardCard(kind: .draft, title: "Stale.fountain", path: screenplay.path)
        var asset = BoardCard(kind: .characters, title: "Sheets", draftID: draft.id)
        var board = ProjectBoard()
        board.cards = [draft, asset]
        board.relinkPath("/tmp/Replaced.fountain", for: draft.id)
        #expect(board.cards.first?.path == "/tmp/Replaced.fountain")
        #expect(board.cards.first?.title == "Replaced.fountain")
        #expect(board.characterPreviewImageURL(for: asset)?.lastPathComponent == "sheet.png")
        board.cards[0].path = screenplay.path
        #expect(board.characterPreviewImageURL(for: asset)?.path == imageURL.path)
    }

    @Test func sceneSelectionRequiresCurrentFingerprint() throws {
        let source = "INT. ROOM - DAY #1#\n\nShe waits."
        let scene = try #require(FountainParser.parse(source).scenes.first)
        let card = BoardCard(kind: .scene, title: scene.heading, draftID: UUID(),
            anchor: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text))
        let board = ProjectBoard()
        #expect(board.linkedSceneSelection(for: card, source: source) == scene.id)
        #expect(board.linkedSceneSelection(for: card, source: "INT. ROOM - DAY #1#\n\nChanged.") == nil)
    }

    @Test func rejectsUnsupportedDuplicateAndNonfiniteBoardState() throws {
        var board = ProjectBoard(); board.version = 2
        #expect(throws: (any Error).self) { try ProjectBoardStore.data(board) }
        board.version = 1
        let card = BoardCard(kind: .note, title: "Beat"); board.cards = [card, card]
        #expect(throws: (any Error).self) { try ProjectBoardStore.data(board) }
        board.cards = []; board.zoom = .infinity
        #expect(throws: (any Error).self) { try ProjectBoardStore.data(board) }
        #expect(throws: (any Error).self) { try ProjectBoardStore.load(Data("{}".utf8)) }
    }

    private func pngData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
    }
}

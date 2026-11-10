import ActCore
import AppKit
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct ProjectBoardDocumentTests {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ActBoard-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    @Test func saveReopenRemoveUndoAndSourcePreservation() throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let draft = root.appendingPathComponent("First.fountain")
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("INT. CAFÉ - DAY\r\n\r\nÉva waits.".utf8)
        try bytes.write(to: draft)
        let doc = ProjectBoardDocument(); doc.fileType = "dev.act.project"
        defer { doc.undoManager?.removeAllActions() }
        try doc.addDraft(draft)
        doc.change("Arrange") { $0.cards[0].position = BoardPoint(x: -100, y: 200); $0.zoom = 0.75 }
        let url = root.appendingPathComponent("Story.actboard")
        try doc.writeSafely(to: url, ofType: "dev.act.project", for: .saveAsOperation)
        let restored = ProjectBoardDocument(); defer { restored.undoManager?.removeAllActions() }
        try restored.read(from: Data(contentsOf: url), ofType: "dev.act.project")
        #expect(restored.board == doc.board)
        let id = try #require(doc.board.cards.first?.id)
        doc.undoManager?.removeAllActions()
        doc.undoManager?.beginUndoGrouping()
        doc.change("Remove card") { $0.removeCard(id) }
        doc.undoManager?.endUndoGrouping(); doc.undoManager?.undo()
        #expect(doc.board.cards.first?.id == id)
        #expect(try Data(contentsOf: draft) == bytes)
    }
    @Test func externalSaveConflictAndWriteFailurePreserveUnsavedBoard() throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Story.actboard")
        let original = try ProjectBoardStore.data(ProjectBoard()); try original.write(to: url)
        let doc = ProjectBoardDocument(); doc.fileURL = url; doc.fileType = "dev.act.project"
        defer { doc.undoManager?.removeAllActions() }
        try doc.read(from: original, ofType: "dev.act.project")
        doc.change("Add note") { $0.cards.append(BoardCard(kind: .note, title: "Unsaved beat")) }
        let unsaved = doc.board
        var external = ProjectBoard(); external.pan.x = 999
        let other = try ProjectBoardStore.data(external); try other.write(to: url)
        #expect(throws: (any Error).self) { try doc.writeSafely(to: url, ofType: "dev.act.project", for: .saveOperation) }
        #expect(doc.board == unsaved); #expect(doc.failure != nil)
        #expect(try Data(contentsOf: url) == other)
        let copy = root.appendingPathComponent("Copy.actboard")
        try doc.writeSafely(to: copy, ofType: "dev.act.project", for: .saveAsOperation)
        #expect(try ProjectBoardStore.load(Data(contentsOf: copy)) == unsaved)
        #expect(doc.failure == nil)
        #expect(throws: (any Error).self) {
            try doc.writeSafely(to: root.appendingPathComponent("absent/No.actboard"), ofType: "dev.act.project", for: .saveAsOperation)
        }
        #expect(doc.board == unsaved)
    }
    @Test func documentRoutingDistinguishesProjectAndStandaloneFountain() throws {
        let controller = ActDocumentController()
        #expect(try controller.typeForContents(of: URL(fileURLWithPath: "/tmp/Story.actboard")) == "dev.act.project")
        #expect(try controller.makeUntitledDocument(ofType: "dev.act.project") is ProjectBoardDocument)
        #expect(try controller.makeUntitledDocument(ofType: "dev.act.fountain") is FountainDocument)
    }
    @Test func boardAttachesAsWorkspaceWithoutCreatingItsOwnWindow() throws {
        _ = NSApplication.shared
        let host = FountainDocument()
        host.replaceSource("INT. ROOM - DAY\n\nAn unfinished draft.")
        let board = ProjectBoardDocument()
        defer { host.undoManager?.removeAllActions(); board.undoManager?.removeAllActions() }
        host.attachProjectBoard(board)
        board.makeWindowControllers()
        #expect(host.projectBoard === board)
        #expect(board.workspaceHost === host)
        #expect(host.requestedWorkspace == .board)
        #expect(board.windowControllers.isEmpty)
        #expect(host.source == "INT. ROOM - DAY\n\nAn unfinished draft.")
        #expect(host.workspaceUndoManager === board.undoManager)
        host.requestedWorkspace = .screenplay
        #expect(host.workspaceUndoManager === host.undoManager)
        board.close()
        #expect(host.projectBoard == nil)
        #expect(host.source.contains("unfinished"))
    }

    @Test func savingBoardTabPreservesUnsavedScreenplayAndWritesOnlyBoard() throws {
        _ = NSApplication.shared
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Workspace.actboard")
        let original = try ProjectBoardStore.data(ProjectBoard()); try original.write(to: url)
        let board = ProjectBoardDocument(); board.fileURL = url; board.fileType = "dev.act.project"
        try board.read(from: original, ofType: "dev.act.project")
        let host = FountainDocument()
        defer { host.undoManager?.removeAllActions(); board.undoManager?.removeAllActions() }
        host.replaceSource("INT. ROOM - DAY\n\nUnsaved writing.")
        host.attachProjectBoard(board)
        board.change("Add beat") { $0.cards.append(BoardCard(kind: .note, title: "Arrival")) }
        host.save(nil)
        TestEditorHost.pump()
        #expect(try ProjectBoardStore.load(Data(contentsOf: url)).cards.first?.title == "Arrival")
        #expect(host.source.contains("Unsaved writing."))
        #expect(host.fileURL == nil)
        #expect(host.isDocumentEdited)
        board.close()
    }

    @Test func renderBoardWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_BOARD_PREVIEW_DIRECTORY"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let doc = ProjectBoardDocument(); defer { doc.undoManager?.removeAllActions() }
        doc.change("Fixture") { board in
            let draft = BoardCard(kind: .draft, title: "Port of Ambitions.fountain", position: BoardPoint(x: 15, y: 40), path: "/tmp/Port of Ambitions.fountain")
            var note = BoardCard(kind: .note, title: "The arrival", position: BoardPoint(x: 335, y: 130)); note.text = "Victor reaches the port. Everyone already knows his name."
            let group = BoardGroup(title: "Act I · Arrival", position: BoardPoint(x: 310, y: 70)); note.groupID = group.id
            board.cards = [draft, note, BoardCard(kind: .characters, title: "Character sheets", position: BoardPoint(x: 650, y: 40), draftID: draft.id)]
            board.groups = [group]
        }
        let host = FountainDocument(); host.attachProjectBoard(doc)
        for (name, width, appearance) in [("board-light", 1280.0, NSAppearance.Name.aqua), ("board-dark", 1280.0, .darkAqua), ("board-narrow", 820.0, .aqua)] {
            let view = NSHostingView(rootView: WorkspaceView(document: host, initialWorkspace: .board))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 850), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = view
            view.layoutSubtreeIfNeeded(); TestEditorHost.pump()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
            window.contentView = nil; window.close()
        }
    }
}

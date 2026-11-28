import AppKit
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct ProjectTabTests {
    @Test func switchingTabsPreservesDocumentsWorkspaceAndUndo() throws {
        _ = NSApplication.shared
        let first = FountainDocument()
        let second = FountainDocument()
        first.makeWindowControllers()
        second.makeWindowControllers()
        let firstController = try #require(first.windowControllers.first)
        let secondController = try #require(second.windowControllers.first)
        let firstWindow = try #require(firstController.window)
        let secondWindow = try #require(secondController.window)
        defer {
            first.undoManager?.removeAllActions()
            second.undoManager?.removeAllActions()
            first.close()
            second.close()
        }
        firstController.showWindow(nil)
        secondController.showWindow(nil)
        TestEditorHost.pump()
        #expect(firstWindow.tabbedWindows?.contains(secondWindow) == true)
        first.requestedWorkspace = .characters
        second.requestedWorkspace = .shots
        first.replaceSource("INT. FIRST - DAY\n\nFirst project.")
        second.replaceSource("INT. SECOND - NIGHT\n\nSecond project.")
        firstWindow.tabGroup?.selectedWindow = firstWindow
        #expect(firstWindow.tabGroup?.selectedWindow === firstWindow)
        #expect(first.requestedWorkspace == .characters)
        #expect(first.source.contains("First project."))
        secondWindow.tabGroup?.selectedWindow = secondWindow
        #expect(second.requestedWorkspace == .shots)
        #expect(second.source.contains("Second project."))
        #expect(first.undoManager !== second.undoManager)
        first.updateChangeCount(.changeCleared)
        second.updateChangeCount(.changeCleared)
        firstWindow.close()
        #expect(second.windowControllers.first?.window === secondWindow)
        #expect(second.source.contains("Second project."))
    }

    @Test func openingAnotherBoardKeepsBothProjects() throws {
        _ = NSApplication.shared
        let controller = NSDocumentController.shared
        let first = ProjectBoardDocument()
        let second = ProjectBoardDocument()
        first.makeWindowControllers()
        let firstHost = try #require(first.workspaceHost)
        firstHost.showWindows()
        first.change("First project") { $0.cards.append(.init(kind: .note, title: "Keep this beat")) }
        second.makeWindowControllers()
        let secondHost = try #require(second.workspaceHost)
        defer {
            for board in [first, second] {
                board.undoManager?.removeAllActions()
                board.updateChangeCount(.changeCleared)
                board.close()
            }
            for host in [firstHost, secondHost] {
                host.updateChangeCount(.changeCleared)
                host.close()
                controller.removeDocument(host)
            }
        }
        #expect(firstHost !== secondHost)
        #expect(firstHost.projectBoard === first)
        #expect(secondHost.projectBoard === second)
        #expect(first.board.cards.first?.title == "Keep this beat")
    }
}

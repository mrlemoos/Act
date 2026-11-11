import ActCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let actProject = UTType(exportedAs: "dev.act.project", conformingTo: .json)
}

@MainActor
@objc(ProjectBoardDocument)
final class ProjectBoardDocument: NSDocument, ObservableObject {
    @Published private(set) var board = ProjectBoard()
    @Published var failure: String?
    @Published private(set) var saveFailed = false
    weak var workspaceHost: FountainDocument?
    private var baseline: DocumentFileSnapshot?
    override class var autosavesInPlace: Bool { true }
    override init() { super.init(); hasUndoManager = true }

    func change(_ title: String, _ edit: (inout ProjectBoard) -> Void) {
        var next = board; edit(&next)
        guard next != board else { return }
        restore(next, title: title)
    }
    private func restore(_ value: ProjectBoard, title: String) {
        let old = board
        undoManager?.registerUndo(withTarget: self) { $0.restore(old, title: title) }
        undoManager?.setActionName(title)
        board = value
        updateChangeCount(undoManager?.isUndoing == true ? .changeUndone : undoManager?.isRedoing == true ? .changeRedone : .changeDone)
    }
    override func data(ofType typeName: String) throws -> Data { try ProjectBoardStore.data(board) }
    override func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            board = try ProjectBoardStore.load(data); baseline = DocumentFileSnapshot(data: data); failure = nil; saveFailed = false
        }
    }
    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { false }
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try MainActor.assumeIsolated {
            do {
                if fileURL?.standardizedFileURL == url.standardizedFileURL, saveOperation != .saveAsOperation {
                    try baseline?.checkUnchanged(at: url)
                }
                let saved = try data(ofType: typeName)
                try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
                if saveOperation != .autosaveElsewhereOperation { baseline = DocumentFileSnapshot(data: saved) }
                failure = nil; saveFailed = false
            } catch { failure = error.localizedDescription; saveFailed = true; throw error }
        }
    }
    func addDraft(_ url: URL) throws {
        _ = try DocumentText(data: Data(contentsOf: url))
        change(L10n.string("Link draft", table: "Board")) { board in
            board.cards.append(BoardCard(kind: .draft, title: url.lastPathComponent,
                position: insertionPoint, path: url.standardizedFileURL.path))
        }
    }
    var insertionPoint: BoardPoint {
        BoardPoint(x: (100 - board.pan.x) / board.zoom + Double(board.cards.count % 6) * 32, y: (100 - board.pan.y) / board.zoom + Double(board.cards.count % 6) * 32)
    }
    func chooseDraft() {
        let panel = NSOpenPanel(); panel.title = L10n.string("Link Fountain draft", table: "Board"); panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try addDraft(url) } catch { failure = error.localizedDescription }
    }
    func relink(_ card: BoardCard) {
        let panel = NSOpenPanel(); panel.title = L10n.format("Relink %@", card.title, table: "Board")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if card.kind == .draft { _ = try DocumentText(data: Data(contentsOf: url)) }
            if card.kind == .shots { _ = try ShotListStore.read(from: url) }
            change(L10n.string("Relink file", table: "Board")) { board in
                guard let i = board.cards.firstIndex(where: { $0.id == card.id }) else { return }
                board.cards[i].path = url.standardizedFileURL.path
                if card.kind == .draft { board.cards[i].title = url.lastPathComponent }
            }
        } catch { failure = error.localizedDescription }
    }
    func relinkOwner(_ card: BoardCard) {
        if let owner = board.cards.first(where: { $0.id == card.draftID }) { relink(owner); return }
        guard let ownerID = card.draftID else { failure = L10n.string("No original draft identity is available.", table: "Board"); return }
        let panel = NSOpenPanel(); panel.title = L10n.string("Restore original draft reference", table: "Board")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try DocumentText(data: Data(contentsOf: url))
            change(L10n.string("Restore draft reference", table: "Board")) { board in
                var draft = BoardCard(kind: .draft, title: url.lastPathComponent, position: insertionPoint, path: url.path)
                draft.id = ownerID; board.cards.append(draft)
            }
        } catch { failure = error.localizedDescription }
    }
    func source(for card: BoardCard) throws -> String {
        let reference = card.kind == .shots ? board.cards.first(where: { $0.id == card.draftID }) : card
        guard let reference, let url = board.resolvedURL(for: reference) else { throw CocoaError(.fileNoSuchFile) }
        if let open = NSDocumentController.shared.document(for: url) as? FountainDocument { return open.source }
        return try DocumentText(data: Data(contentsOf: url)).source
    }
    func addScene(_ scene: FountainScene, draft: BoardCard) {
        change(L10n.string("Add scene card", table: "Board")) { board in
            board.cards.append(BoardCard(kind: .scene, title: scene.heading, position: insertionPoint,
                draftID: draft.id, anchor: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)))
        }
    }
    func addAsset(_ kind: BoardCard.Kind, draft: BoardCard) {
        var path: String?
        if kind == .shots {
            let panel = NSOpenPanel(); panel.title = L10n.string("Link existing shot list", table: "Board"); panel.allowedContentTypes = [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { _ = try ShotListStore.read(from: url); path = url.path }
            catch { failure = error.localizedDescription; return }
        }
        change(L10n.string("Link planning asset", table: "Board")) { board in
            board.cards.append(BoardCard(kind: kind, title: BoardPresentation.defaultAssetTitle(kind),
                position: insertionPoint, draftID: draft.id, path: path))
        }
    }
    func open(_ card: BoardCard) {
        let owner = board.cards.first { $0.id == card.draftID }
        let url = card.kind == .shots ? owner.flatMap { board.resolvedURL(for: $0) } : board.resolvedURL(for: card)
        guard let url else { failure = L10n.string("Draft reference missing. Relink the original draft.", table: "Board"); return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            if let error { self?.failure = error.localizedDescription; return }
            guard let draft = document as? FountainDocument else { return }
            if card.kind == .shots, let path = card.path {
                do {
                    draft.shotWorkspace.prepare(source: draft.source, name: draft.fileURL?.deletingPathExtension().lastPathComponent, identity: url.path)
                    try draft.shotWorkspace.openLinked(URL(fileURLWithPath: path))
                }
                catch { self?.failure = L10n.format("Cannot open linked shot list: %@ Save pending shot edits first.", error.localizedDescription, table: "Board"); return }
            }
            draft.requestedWorkspace = card.kind == .characters ? .characters : card.kind == .shots ? .shots : .screenplay
            if card.kind == .scene, let anchor = card.anchor {
                guard let scene = FountainParser.parse(draft.source).scenes.first(where: { $0.id == anchor.id }),
                      SceneAnchor.digest(scene.text) == anchor.fingerprint else {
                    self?.failure = L10n.string("Scene needs review. Opened draft without selecting a different scene.", table: "Board"); return
                }
                draft.requestedSceneID = scene.id
            }
        }
    }
    func confirmTermination() -> Bool {
        guard isDocumentEdited else { return true }
        let alert = NSAlert(); alert.messageText = L10n.string("Save project board changes?", table: "Board")
        alert.informativeText = L10n.string("Your linked source files are unaffected.", table: "Board")
        alert.addButton(withTitle: L10n.string("Save", table: "Board")); alert.addButton(withTitle: L10n.string("Cancel", table: "Board")); alert.addButton(withTitle: L10n.string("Discard Changes", table: "Board"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: save(nil); return !isDocumentEdited
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    override var windowForSheet: NSWindow? { workspaceHost?.windowForSheet }

    override func close() {
        workspaceHost?.detachProjectBoard(self)
        workspaceHost = nil
        super.close()
    }

    override func showWindows() {
        workspaceHost?.requestedWorkspace = .board
        workspaceHost?.showWindows()
    }

    override func makeWindowControllers() {
        if let workspaceHost { workspaceHost.requestedWorkspace = .board; return }
        let controller = NSDocumentController.shared
        let active = NSApp.keyWindow?.windowController?.document as? FountainDocument
        let existing = active ?? controller.documents.compactMap { $0 as? FountainDocument }.first { !$0.windowControllers.isEmpty }
        let host = existing ?? FountainDocument()
        if let previous = host.projectBoard, previous !== self {
            guard previous.confirmTermination() else { close(); return }
            previous.close()
        }
        if existing == nil {
            host.fileType = UTType.fountain.identifier
            controller.addDocument(host)
            host.makeWindowControllers()
        }
        host.attachProjectBoard(self)
    }
}

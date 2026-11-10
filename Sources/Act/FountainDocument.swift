import ActCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let fountain = UTType(exportedAs: "dev.act.fountain", conformingTo: .plainText)
}

@MainActor
@objc(FountainDocument)
final class FountainDocument: NSDocument, ObservableObject {
    @Published private(set) var source = ""
    lazy var shotWorkspace = ShotWorkspaceModel()
    lazy var characterWorkspace = CharacterWorkspaceModel()
    @Published var isShotWorkspaceActive = false
    @Published var isCharacterWorkspaceActive = false
    @Published var showsSettings = false
    @Published var requestedWorkspace: WorkspaceSection?
    @Published var requestedSceneID: String?
    @Published private(set) var projectBoard: ProjectBoardDocument?
    private var pdfPreview: ScreenplayPreviewController?
    private var textFile = DocumentText()
    private var snapshot: DocumentFileSnapshot?

    override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                if let fileURL {
                    shotWorkspace.relocateRecovery(identity: fileURL.path)
                    characterWorkspace.prepare(screenplayURL: fileURL, source: source)
                }
            }
        }
    }

    override class var autosavesInPlace: Bool { true }
    override var displayName: String! {
        get { super.displayName }
        set { super.displayName = newValue }
    }

    override init() {
        super.init()
        hasUndoManager = true
    }

    func ensureProjectBoard() {
        guard projectBoard == nil else { return }
        let board = ProjectBoardDocument()
        board.fileType = UTType.actProject.identifier
        NSDocumentController.shared.addDocument(board)
        attachProjectBoard(board)
    }

    func attachProjectBoard(_ board: ProjectBoardDocument) {
        projectBoard = board
        board.workspaceHost = self
        requestedWorkspace = .board
    }

    func detachProjectBoard(_ board: ProjectBoardDocument) {
        guard projectBoard === board else { return }
        projectBoard = nil
        if requestedWorkspace == .board { requestedWorkspace = .screenplay }
    }

    var workspaceUndoManager: UndoManager? {
        requestedWorkspace == .board ? projectBoard?.undoManager : undoManager
    }

    func replaceSource(_ newSource: String) {
        guard source != newSource else { return }
        let previous = source
        undoManager?.registerUndo(withTarget: self) { target in target.replaceSource(previous) }
        undoManager?.setActionName("Writing")
        source = newSource
        characterWorkspace.updateSource(newSource)
        shotWorkspace.updateScreenplaySource(newSource)
        textFile.source = newSource
        updateChangeCount(undoManager?.isUndoing == true ? .changeUndone : undoManager?.isRedoing == true ? .changeRedone : .changeDone)
    }

    func setPaper(_ paper: ScreenplayPaper) {
        replaceSource(paper.updating(source))
        undoManager?.setActionName("Paper size")
    }

    func showPDFPreview() {
        if pdfPreview == nil {
            let controller = ScreenplayPreviewController(document: self)
            pdfPreview = controller
            addWindowController(controller)
        }
        pdfPreview?.model.refresh()
        pdfPreview?.showWindow(nil)
        pdfPreview?.window?.makeKeyAndOrderFront(nil)
    }

    override func close() {
        projectBoard?.close()
        pdfPreview?.close()
        pdfPreview = nil
        super.close()
    }

    override func save(_ sender: Any?) {
        if requestedWorkspace == .board { ensureProjectBoard(); projectBoard?.save(sender) }
        else if isShotWorkspaceActive { shotWorkspace.save() }
        else if isCharacterWorkspaceActive { characterWorkspace.save() }
        else { super.save(sender) }
    }

    override func saveAs(_ sender: Any?) {
        if requestedWorkspace == .board { ensureProjectBoard(); projectBoard?.saveAs(sender) }
        else if isShotWorkspaceActive { shotWorkspace.save(asCopy: true) }
        else { super.saveAs(sender) }
    }

    override func revertToSaved(_ sender: Any?) {
        if requestedWorkspace == .board { projectBoard?.revertToSaved(sender) }
        else { super.revertToSaved(sender) }
    }

    func confirmShotClosure() -> Bool {
        if let projectBoard, !projectBoard.confirmTermination() { return false }
        characterWorkspace.save()
        guard !characterWorkspace.isDirty else {
            let alert = NSAlert()
            alert.messageText = "Character edits could not be saved"
            alert.informativeText = characterWorkspace.error ?? "Save your screenplay before closing to keep its character library."
            alert.runModal()
            return false
        }
        guard shotWorkspace.isDirty else { shotWorkspace.cancel(); characterWorkspace.cancel(); return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to your shot list?"
        alert.informativeText = "The shot list is saved separately from your screenplay."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Close Without Saving")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            shotWorkspace.save()
            guard !shotWorkspace.isDirty else { return false }
        case .alertThirdButtonReturn: shotWorkspace.discardRecovery()
        default: return false
        }
        shotWorkspace.cancel()
        characterWorkspace.cancel()
        return true
    }

    override func data(ofType typeName: String) throws -> Data {
        textFile.data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            textFile = try DocumentText(data: data)
            source = textFile.source
            characterWorkspace.updateSource(source)
            shotWorkspace.updateScreenplaySource(source)
            snapshot = DocumentFileSnapshot(data: data)
        }
    }

    override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }

    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { false }

    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try MainActor.assumeIsolated {
            if let current = fileURL, current.standardizedFileURL == url.standardizedFileURL,
               let snapshot, saveOperation != .saveAsOperation {
                try snapshot.checkUnchanged(at: current)
            }
            try super.writeSafely(to: url, ofType: typeName, for: saveOperation)
            if saveOperation != .autosaveElsewhereOperation {
                snapshot = DocumentFileSnapshot(data: textFile.data)
            }
        }
    }

    override func makeWindowControllers() {
        let view = WorkspaceView(document: self)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = displayName
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 820, height: 580)
        window.contentView = NSHostingView(rootView: view)
        window.setFrameAutosaveName("ActWorkspace")
        window.center()
        let controller = ActWindowController(window: window)
        addWindowController(controller)
        window.delegate = controller
        DispatchQueue.main.async {
            (NSApp.delegate as? ActApplicationDelegate)?.installMainMenu()
        }
    }
}

@MainActor
final class ActDocumentController: NSDocumentController {
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = "Open screenplay or project"
        panel.message = "Choose a Fountain screenplay or .actboard project."
        // Fountain is plain text and other editors register competing UTIs for
        // its extension. An unrestricted panel keeps those documents selectable.
        // DocumentText validates the actual bytes before a document is opened.
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = currentDocument?.fileURL?.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            for url in panel.urls {
                self.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            }
        }
    }

    override var defaultType: String? { UTType.fountain.identifier }
    override func documentClass(forType typeName: String) -> AnyClass? { typeName == UTType.actProject.identifier ? ProjectBoardDocument.self : FountainDocument.self }
    override func typeForContents(of url: URL) throws -> String { url.pathExtension.lowercased() == "actboard" ? UTType.actProject.identifier : UTType.fountain.identifier }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document: NSDocument = typeName == UTType.actProject.identifier ? ProjectBoardDocument() : FountainDocument()
        document.fileType = typeName
        return document
    }
    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        let document: NSDocument = typeName == UTType.actProject.identifier ? ProjectBoardDocument() : FountainDocument()
        try document.read(from: url, ofType: typeName)
        document.fileURL = url
        document.fileType = typeName
        return document
    }
}

@MainActor
final class ActWindowController: NSWindowController, NSWindowDelegate {
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (document as? FountainDocument)?.workspaceUndoManager
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (document as? FountainDocument)?.confirmShotClosure() ?? true
    }
}

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
    @Published var isShotWorkspaceActive = false
    @Published var showsSettings = false
    private var textFile = DocumentText()
    private var snapshot: DocumentFileSnapshot?

    override var fileURL: URL? {
        didSet {
            MainActor.assumeIsolated {
                if let fileURL { shotWorkspace.relocateRecovery(identity: fileURL.path) }
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

    func replaceSource(_ newSource: String) {
        guard source != newSource else { return }
        let previous = source
        undoManager?.registerUndo(withTarget: self) { target in target.replaceSource(previous) }
        undoManager?.setActionName("Writing")
        source = newSource
        shotWorkspace.updateScreenplaySource(newSource)
        textFile.source = newSource
        updateChangeCount(undoManager?.isUndoing == true ? .changeUndone : undoManager?.isRedoing == true ? .changeRedone : .changeDone)
    }

    override func save(_ sender: Any?) {
        if isShotWorkspaceActive { shotWorkspace.save() }
        else { super.save(sender) }
    }

    override func saveAs(_ sender: Any?) {
        if isShotWorkspaceActive { shotWorkspace.save(asCopy: true) }
        else { super.saveAs(sender) }
    }

    func confirmShotClosure() -> Bool {
        guard shotWorkspace.isDirty else { shotWorkspace.cancel(); return true }
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
        return true
    }

    override func data(ofType typeName: String) throws -> Data {
        textFile.data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            textFile = try DocumentText(data: data)
            source = textFile.source
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
        panel.title = "Open screenplay"
        panel.message = "Choose a UTF-8 Fountain screenplay."
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
    override func documentClass(forType typeName: String) -> AnyClass? { FountainDocument.self }
    override func typeForContents(of url: URL) throws -> String { UTType.fountain.identifier }
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let document = FountainDocument()
        document.fileType = typeName
        return document
    }
    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        let document = FountainDocument()
        try document.read(from: url, ofType: typeName)
        document.fileURL = url
        document.fileType = typeName
        return document
    }
}

@MainActor
final class ActWindowController: NSWindowController, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        (document as? FountainDocument)?.confirmShotClosure() ?? true
    }
}

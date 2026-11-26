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
    let automationID = UUID().uuidString
    @Published private(set) var automationRevision = UUID().uuidString
    @Published var aiReview = AutomationReviewLedger()
    @Published var aiReviewError: String?
    @Published var automationSelection: NSRange?
    @Published var automationSelectionRequest = UUID()
    private var reviewURL: URL?
    private var reviewLoadFailed = false
    private var applyingAutomation = false
    private var suppressSourceUndo = false
    private var reviewEpoch = UUID()
    private var pendingReviewSave: Task<Void, Never>?
    var aiReviewRecoveryDirectory: URL?
    private var unsavedReviewURL: URL?
    private var attemptedReviewRecovery = false
    private var reviewPopup: AutomationPopupController?
    weak var screenplayEditorView: NSTextView?
    /// Refreshed when the editor commits a line, not on every keystroke. See docs/adr/0001.
    @Published private(set) var outline: [FountainOutlineEntry] = []
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
                    loadAIReview(at: fileURL)
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
        // Explicit groups keep separate IPC transactions independent of run-loop timing.
        undoManager?.groupsByEvent = false
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

    var screenplay: FountainScreenplay { characterWorkspace.parsedScreenplay(for: source) }

    var workspaceUndoManager: UndoManager? {
        requestedWorkspace == .board ? projectBoard?.undoManager : undoManager
    }

    func refreshOutline() {
        let entries = FountainOutline.entries(in: screenplay)
        if entries != outline { outline = entries }
    }

    func replaceSource(_ newSource: String, deferringOutline: Bool = false) {
        guard !source.isLiterallyEqual(to: newSource) else { return }
        let previous = source
        let ownsUndoGroup = !suppressSourceUndo && undoManager?.groupingLevel == 0 && undoManager?.isUndoing != true && undoManager?.isRedoing != true
        if ownsUndoGroup { undoManager?.beginUndoGrouping() }
        defer { if ownsUndoGroup { undoManager?.endUndoGrouping() } }
        if !suppressSourceUndo {
            undoManager?.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated { target.replaceSource(previous) }
            }
            undoManager?.setActionName(L10n.string("Writing", table: "Writing"))
        }
        source = newSource
        automationRevision = UUID().uuidString
        if !applyingAutomation && !aiReview.changes.isEmpty {
            aiReview.reconcile(from: previous, to: newSource)
            pendingReviewSave?.cancel()
            pendingReviewSave = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.persistAIReview()
            }
        }
        characterWorkspace.updateSource(newSource)
        shotWorkspace.updateScreenplaySource(newSource)
        textFile.source = newSource
        updateChangeCount(undoManager?.isUndoing == true ? .changeUndone : undoManager?.isRedoing == true ? .changeRedone : .changeDone)
        if !deferringOutline { refreshOutline() }
    }

    func setPaper(_ paper: ScreenplayPaper) {
        replaceSource(paper.updating(source))
        undoManager?.setActionName(L10n.string("Paper size", table: "Writing"))
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
        reviewPopup?.close(); reviewPopup = nil
        if !aiReview.changes.isEmpty { persistAIReview() }
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
            alert.messageText = L10n.string("Character edits could not be saved", table: "Writing")
            alert.informativeText = characterWorkspace.error ?? L10n.string("Save your screenplay before closing to keep its character library.", table: "Writing")
            alert.runModal()
            return false
        }
        guard shotWorkspace.isDirty else { shotWorkspace.cancel(); characterWorkspace.cancel(); return true }
        let alert = NSAlert()
        alert.messageText = L10n.string("Save changes to your shot list?", table: "Writing")
        alert.informativeText = L10n.string("The shot list is saved separately from your screenplay.", table: "Writing")
        alert.addButton(withTitle: L10n.string("Save", table: "Writing"))
        alert.addButton(withTitle: L10n.string("Cancel", table: "Writing"))
        alert.addButton(withTitle: L10n.string("Close Without Saving", table: "Writing"))
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
            automationRevision = UUID().uuidString
            aiReview.verify(source: source)
            characterWorkspace.updateSource(source)
            shotWorkspace.updateScreenplaySource(source)
            refreshOutline()
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

    private func loadAIReview(at url: URL) {
        let destination = url.deletingPathExtension().appendingPathExtension("ai-review.json")
        guard reviewURL != destination else { return }
        reviewURL = destination
        reviewLoadFailed = false
        guard FileManager.default.fileExists(atPath: destination.path) else {
            if !aiReview.changes.isEmpty { aiReview.sourceFingerprint = SceneAnchor.digest(source); persistAIReview() }
            return
        }
        do {
            var ledger = try JSONDecoder().decode(AutomationReviewLedger.self, from: Data(contentsOf: destination))
            guard ledger.version == 1 else { throw AutomationFailure("unsupported_version", "Unsupported AI review history.") }
            ledger.verify(source: source)
            aiReview = ledger
        } catch { reviewLoadFailed = true; aiReviewError = error.localizedDescription }
    }

    func persistAIReview() {
        pendingReviewSave?.cancel(); pendingReviewSave = nil
        guard !reviewLoadFailed else { return }
        guard !aiReview.changes.isEmpty || reviewURL != nil else { return }
        do {
            let url: URL
            if let reviewURL { url = reviewURL }
            else if let unsavedReviewURL { url = unsavedReviewURL }
            else {
                let directory = aiReviewRecoveryDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Act/AIReview")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                url = directory.appendingPathComponent(automationID + ".json")
            }
            guard url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else { throw AutomationFailure("invalid_path", "Review history must not be a symbolic link.") }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(aiReview).write(to: url, options: .atomic)
            aiReviewError = nil
        } catch { aiReviewError = error.localizedDescription }
    }

    func recoverUnsavedAIReview(in directory: URL) {
        aiReviewRecoveryDirectory = directory
        guard fileURL == nil, !attemptedReviewRecovery, aiReview.changes.isEmpty else { return }
        attemptedReviewRecovery = true
        let fingerprint = SceneAnchor.digest(source)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let matches: [(URL, AutomationReviewLedger)] = files.compactMap { url in
            guard url.pathExtension == "json", ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? Int.max) <= 16_777_216,
                  url.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/"),
                  let data = try? Data(contentsOf: url), let ledger = try? JSONDecoder().decode(AutomationReviewLedger.self, from: data),
                  ledger.version == 1, !ledger.changes.isEmpty, ledger.sourceFingerprint == fingerprint else { return nil }
            return (url, ledger)
        }
        if matches.count == 1, let match = matches.first { unsavedReviewURL = match.0; aiReview = match.1 }
        else if matches.count > 1 { aiReviewError = "Several unsaved review histories match this source. Archives are preserved; no history was chosen automatically." }
    }

    func applyAutomationPreview(_ preview: AutomationPreview) throws {
        guard !reviewLoadFailed else { throw AutomationFailure("recovery_required", "AI history could not be read. Preserve and repair it before applying edits.") }
        guard screenplayEditorView?.hasMarkedText() != true else { throw AutomationFailure("busy", "Finish the current input-method composition before applying an AI edit.") }
        guard preview.revision == automationRevision, preview.sourceFingerprint == SceneAnchor.digest(source) else {
            throw AutomationFailure("revision_conflict", "The document changed after preview. Preview again.")
        }
        let previousSource = source, previousLedger = aiReview, epoch = reviewEpoch
        var rebased = aiReview, displacement = 0
        let spans = preview.changes.sorted { $0.location < $1.location }.map { change -> (NSRange, Int) in
            let range = NSRange(location: change.location - displacement, length: (change.before as NSString).length)
            let length = (change.after as NSString).length
            displacement += length - range.length
            return (range, length)
        }
        for (range, length) in spans.reversed() { rebased.rebase(through: range, replacementLength: length) }
        guard (undoManager?.groupingLevel ?? 0) == 0 else { throw AutomationFailure("busy", "A native edit transaction is still open.") }
        undoManager?.beginUndoGrouping()
        applyingAutomation = true
        suppressSourceUndo = true
        replaceSource(preview.result)
        suppressSourceUndo = false
        applyingAutomation = false
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreAIState(source: previousSource, ledger: previousLedger, epoch: epoch)
            }
        }
        undoManager?.setActionName(automationText("AI edit"))
        undoManager?.endUndoGrouping()
        aiReview = rebased
        aiReview.changes.append(contentsOf: preview.changes)
        aiReview.sourceFingerprint = SceneAnchor.digest(source)
        persistAIReview()
        if aiReviewError != nil { throw AutomationFailure("uncertain_outcome", "Edit applied, but history could not be saved: \(aiReviewError!)") }
    }

    func clearAIReview() {
        reviewEpoch = UUID()
        reviewLoadFailed = false
        aiReview.changes = []
        aiReview.sourceFingerprint = SceneAnchor.digest(source)
        persistAIReview()
    }

    func showAIReviewPopup() {
        if reviewPopup == nil {
            reviewPopup = AutomationPopupController(title: automationText("AI changes"), size: NSSize(width: 620, height: 660), content: AIReviewPopup(document: self) { [weak self] in self?.reviewPopup?.close() })
        }
        reviewPopup?.present()
    }

    func acceptAIChanges(batchID: String) throws {
        try acceptAIChanges(matching: { $0.batchID == batchID })
    }

    func acceptAIChange(operationID: UUID) throws {
        try acceptAIChanges(matching: { $0.operationID == operationID })
    }

    private func acceptAIChanges(matching matches: (AutomationChange) -> Bool) throws {
        let batch = aiReview.changes.filter(matches)
        guard !batch.isEmpty, batch.allSatisfy({ !$0.conflicted && !$0.reverted }) else { throw AutomationFailure("review_conflict", "This batch no longer matches current writing.") }
        let previous = aiReview
        for index in aiReview.changes.indices where matches(aiReview.changes[index]) {
            aiReview.changes[index].accepted = true
            aiReview.changes[index].dismissed = true
        }
        persistAIReview()
        if let aiReviewError {
            aiReview = previous
            throw AutomationFailure("history_save_failed", aiReviewError)
        }
    }

    private func restoreAIState(source restoredSource: String, ledger: AutomationReviewLedger, epoch: UUID) {
        let currentSource = source, currentLedger = aiReview
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreAIState(source: currentSource, ledger: currentLedger, epoch: epoch)
            }
        }
        applyingAutomation = true; suppressSourceUndo = true
        replaceSource(restoredSource)
        applyingAutomation = false; suppressSourceUndo = false
        if epoch == reviewEpoch {
            var restored = ledger
            let known = Set(restored.changes.map(\.id))
            for original in currentLedger.changes where !known.contains(original.id) {
                var historical = original; historical.reverted = true
                restored.changes.append(historical)
            }
            aiReview = restored
        } else if !aiReview.changes.isEmpty {
            aiReview.reconcile(from: currentSource, to: restoredSource)
        }
        aiReview.sourceFingerprint = SceneAnchor.digest(restoredSource)
        persistAIReview()
    }

    func revertAIChanges(id: String) throws {
        let records = aiReview.changes.filter { $0.id.uuidString == id || $0.operationID.uuidString == id || $0.batchID == id }
        guard !records.isEmpty, records.allSatisfy({ !$0.conflicted && !$0.reverted }) else {
            throw AutomationFailure("review_conflict", "Later writing overlaps this change, or its source lineage cannot be verified.")
        }
        // Revert both halves of a move even when one of its cards was selected.
        let operations = Set(records.map(\.operationID))
        let paired = aiReview.changes.filter { operations.contains($0.operationID) }
        guard paired.allSatisfy({ !$0.conflicted && !$0.reverted }) else { throw AutomationFailure("review_conflict", "A linked move changed after application.") }
        let inverse = paired.map { item in
            AutomationChange(operationID: item.operationID, batchID: "", kind: "revert", role: item.role, location: item.location, before: item.after, after: item.before)
        }
        let preview = try AutomationEditing.resolve(source: source, revision: automationRevision, changes: inverse)
        try applyAutomationPreview(preview)
        for index in aiReview.changes.indices where operations.contains(aiReview.changes[index].operationID) && aiReview.changes[index].kind != "revert" {
            aiReview.changes[index].reverted = true
            aiReview.changes[index].accepted = false
        }
        for index in aiReview.changes.indices where aiReview.changes[index].batchID == preview.id {
            aiReview.changes[index].accepted = true; aiReview.changes[index].dismissed = true
        }
        persistAIReview()
    }
}

@MainActor
final class ActDocumentController: NSDocumentController {
    override func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = L10n.string("Open screenplay or project", table: "Writing")
        panel.message = L10n.string("Choose a Fountain screenplay or .actboard project.", table: "Writing")
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

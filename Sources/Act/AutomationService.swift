import ActCore
import AppKit
import SwiftUI

struct AutomationReceipt: Codable {
    var fingerprint: String
    var response: AutomationValue?
}

struct AutomationImageVersion: Codable, Identifiable {
    var id = UUID().uuidString
    var targetID: String
    var targetKind: String
    var path: String
    var prompt: String
    var jobID: String
    var active = true
    var createdAt = Date()
}

struct AutomationStoryboardLibrary: Codable {
    var version = 1
    var versions: [AutomationImageVersion] = []
}

struct AutomationJob: Codable, Identifiable {
    var id = UUID().uuidString
    var documentPath: String
    var targetID: String
    var targetKind: String
    var prompt: String
    var references: [String]
    var referenceHashes: [String]
    var inputFingerprint: String
    var agent: String?
    var state: String
    var error: String?
    var resultPath: String?
    var createdAt = Date()
}

struct AutomationState: Codable {
    var version = 1
    var receipts: [String: AutomationReceipt] = [:]
    var jobs: [AutomationJob] = []
}

@MainActor
final class AutomationService: ObservableObject {
    static let shared = AutomationService()
    let root: URL
    let directory: URL
    @Published private(set) var state = AutomationState()
    @Published var error: String?
    @Published private(set) var imageRevision = UUID()
    private var previews: [String: (String, AutomationPreview)] = [:]
    private var tasks: [String: Task<Void, Never>] = [:]
    private let suppliedController: NSDocumentController?
    private let isolatedStorage: Bool
    private var socket: AutomationSocket?
    private var window: NSWindow?
    private var approvalPopup: AutomationPopupController?
    private var approvalPopupJobID: String?
    private var loadError: Error?
    private var controller: NSDocumentController { suppliedController ?? (NSApp.delegate as? ActApplicationDelegate)?.documents ?? NSDocumentController.shared }
    var documents: [FountainDocument] { controller.documents.compactMap { $0 as? FountainDocument } }
    var jobs: [AutomationJob] { state.jobs }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    init(root: URL? = nil, directory: URL? = nil, controller: NSDocumentController? = nil) {
        let environment = ProcessInfo.processInfo.environment
        isolatedStorage = directory != nil || environment["ACT_AUTOMATION_DIRECTORY"] != nil
        self.root = root ?? environment["ACT_PROJECT_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Act")
        self.directory = directory ?? environment["ACT_AUTOMATION_DIRECTORY"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Act/Automation")
        suppliedController = controller
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do {
                state = try JSONDecoder().decode(AutomationState.self, from: Data(contentsOf: stateURL))
                guard state.version == 1 else { throw AutomationFailure("unsupported_version", "Unsupported automation recovery state.") }
                for i in state.jobs.indices where state.jobs[i].state == "running" {
                    state.jobs[i].state = "uncertain_outcome"
                    state.jobs[i].error = "Act stopped while generation was running. Inspect provider results before explicitly retrying."
                }
            } catch { loadError = error; self.error = error.localizedDescription }
        }
    }

    func start() {
        do {
            let server = AutomationSocket(directory: directory) { [weak self] data in
                guard let self else { return Data() }
                return await self.handle(data)
            }
            try server.start(); socket = server
        } catch { self.error = error.localizedDescription }
    }

    func stop() { socket?.stop(); socket = nil }

    func shutdown() {
        approvalPopup?.close(); approvalPopup = nil; approvalPopupJobID = nil
        for document in documents where !document.aiReview.changes.isEmpty { document.persistAIReview() }
        for task in tasks.values { task.cancel() }
        for index in state.jobs.indices where state.jobs[index].state == "running" {
            state.jobs[index].state = state.jobs[index].agent == nil ? "cancelled" : "uncertain_outcome"
        }
        do { try persist() } catch { self.error = error.localizedDescription }
        stop()
    }

    func showWindow() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 650), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Act · " + automationText("Automation"); window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AutomationWindow(service: self))
            window.center(); self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        showNextApprovalPopup()
    }

    func showApprovalPopup(jobID: String) {
        guard let job = jobs.first(where: { $0.id == jobID }), job.state == "approval_required" else { return }
        if let current = approvalPopup {
            // Never swap the payload while someone is reviewing another request.
            if approvalPopupJobID == jobID { current.present() }
            else { error = "Finish or reject the current approval popup before reviewing another request." }
            return
        }
        error = nil
        let view = ImageApprovalPopup(service: self, job: job, accept: { [weak self] in
            guard let self else { return }
            if self.approve(jobID: jobID) { self.finishApprovalPopup() }
        }, reject: { [weak self] in
            guard let self else { return }
            self.cancelJob(jobID); self.finishApprovalPopup()
        })
        approvalPopupJobID = jobID
        approvalPopup = AutomationPopupController(title: automationText("Review request"), size: NSSize(width: 640, height: 640), content: view)
        approvalPopup?.present()
    }

    private func showNextApprovalPopup() {
        guard approvalPopup == nil, let pending = jobs.first(where: { $0.state == "approval_required" }) else { return }
        showApprovalPopup(jobID: pending.id)
    }

    private func finishApprovalPopup() {
        approvalPopup?.close(); approvalPopup = nil; approvalPopupJobID = nil
        showNextApprovalPopup()
    }

    func handle(_ data: Data) -> Data {
        var request: AutomationRequest?
        do {
            let raw = try JSONDecoder().decode(AutomationValue.self, from: data)
            request = try JSONDecoder().decode(AutomationRequest.self, from: data)
            let allowed: Set<String> = ["version", "requestID", "operation", "documentID", "expectedRevision", "parameters"]
            guard let envelope = raw.object, Set(envelope.keys).isSubset(of: allowed) else { throw AutomationFailure("invalid_parameters", "Invalid or unknown request envelope fields.") }
            return try perform(request!).data()
        } catch {
            return (try? response(request, failure: error).data()) ?? Data("{\"version\":1,\"ok\":false}".utf8)
        }
    }

    func perform(_ request: AutomationRequest) throws -> AutomationValue {
        guard request.version == 1 else { return response(request, failure: AutomationFailure("unsupported_version", "Supported protocol version: 1.")) }
        guard !request.requestID.isEmpty, request.requestID.utf8.count <= 128 else { return response(request, failure: AutomationFailure("invalid_parameters", "requestID must contain 1–128 bytes.")) }
        if let loadError { return response(request, failure: AutomationFailure("recovery_required", "Automation state could not be read: \(loadError.localizedDescription)")) }
        let fingerprint = SceneAnchor.digest(String(decoding: try AutomationValue.encoded(request).data(), as: UTF8.self))
        if let receipt = state.receipts[request.requestID] {
            guard receipt.fingerprint == fingerprint else { return response(request, failure: AutomationFailure("request_id_conflict", "requestID was already used with different parameters.")) }
            return receipt.response ?? response(request, failure: AutomationFailure("uncertain_outcome", "This request was interrupted. Inspect current state before issuing a new mutation."))
        }
        let mutating = (try AutomationContract.schema())["operations"][request.operation]["mutation"].bool ?? false
        if mutating {
            state.receipts[request.requestID] = .init(fingerprint: fingerprint)
            do { try persist() }
            catch { state.receipts.removeValue(forKey: request.requestID); return response(request, failure: error) }
        }
        let result: AutomationValue
        do {
            result = .object(["version": .number(1), "requestID": .string(request.requestID), "operation": .string(request.operation), "ok": .bool(true), "result": try execute(request)])
        } catch { result = response(request, failure: error) }
        if mutating {
            state.receipts[request.requestID]?.response = result
            do { try persist() }
            catch { return response(request, failure: AutomationFailure("uncertain_outcome", "Operation finished but its receipt could not be saved. Inspect state before retrying.")) }
        }
        return result
    }

    private func response(_ request: AutomationRequest?, failure: Error) -> AutomationValue {
        let failure = failure as? AutomationFailure ?? AutomationFailure("operation_failed", failure.localizedDescription)
        return .object(["version": .number(1), "requestID": request.map { .string($0.requestID) } ?? .null,
                        "operation": request.map { .string($0.operation) } ?? .null, "ok": .bool(false),
                        "error": .object(["code": .string(failure.code), "message": .string(failure.message), "retryable": .bool(false)])])
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    func managed(_ url: URL) throws -> URL {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(base.path + "/") else { throw AutomationFailure("outside_project_root", "Import into \(root.path) before modifying this file.") }
        return resolved
    }

    private func child(_ name: String, in parent: URL) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name.utf8.count <= 180 else {
            throw AutomationFailure("invalid_parameters", "Supply a single non-empty project or filename component.")
        }
        return try managed(parent.appendingPathComponent(name))
    }

    private func target(_ request: AutomationRequest, mutation: Bool = false, revision: String? = nil) throws -> FountainDocument {
        guard let id = request.documentID, let document = documents.first(where: { $0.automationID == id }) else {
            throw AutomationFailure("unknown_document", "Use documents.list to choose an open documentID.")
        }
        document.recoverUnsavedAIReview(in: directory.appendingPathComponent("UnsavedReviews"))
        if mutation {
            document.aiReviewRecoveryDirectory = directory.appendingPathComponent("UnsavedReviews")
            if let url = document.fileURL {
                _ = try managed(url)
                for suffix in ["shots.json", "characters", "ai-review.json", "storyboards"] {
                    _ = try managed(url.deletingPathExtension().appendingPathExtension(suffix))
                }
            }
            guard request.expectedRevision == (revision ?? document.automationRevision) else { throw AutomationFailure("revision_conflict", "Expected revision does not match. Inspect the document again.") }
        }
        return document
    }

    private func required(_ key: String, _ p: [String: AutomationValue]) throws -> String {
        guard let value = p[key]?.string, !value.isEmpty else { throw AutomationFailure("invalid_parameters", "Missing string parameter: \(key)") }
        return value
    }

    func info(_ document: FountainDocument) -> AutomationValue {
        .object(["documentID": .string(document.automationID), "name": .string(document.displayName),
                 "path": document.fileURL.map { .string($0.path) } ?? .null,
                 "revision": .string(document.automationRevision), "shotRevision": .string(shotRevision(document)),
                 "characterRevision": .string(characterRevision(document)),
                 "persistence": .string(document.fileURL == nil ? "unsaved" : document.isDocumentEdited ? "pending" : "saved"),
                 "reviewError": document.aiReviewError.map(AutomationValue.string) ?? .null])
    }

    private func shotRevision(_ doc: FountainDocument) -> String { doc.automationID + ":" + doc.shotWorkspace.automationRevision }
    private func characterRevision(_ doc: FountainDocument) -> String { doc.automationID + ":" + String(doc.characterWorkspace.revision) }

    private func prepareShots(_ doc: FountainDocument) throws {
        // Normal automation shares the writer's native recovery store. Only fixtures isolate it.
        doc.shotWorkspace.automationRecoveryDirectory = isolatedStorage ? directory.appendingPathComponent("ShotRecovery") : nil
        doc.shotWorkspace.prepare(source: doc.source, name: doc.fileURL?.deletingPathExtension().lastPathComponent, identity: doc.fileURL?.path ?? doc.automationID)
        if let path = doc.fileURL?.deletingPathExtension().appendingPathExtension("shots.json"),
           doc.shotWorkspace.fileURL == nil, !doc.shotWorkspace.isDirty, FileManager.default.fileExists(atPath: path.path) {
            try doc.shotWorkspace.openLinked(path)
        }
    }

    private func execute(_ r: AutomationRequest) throws -> AutomationValue {
        try AutomationContract.validate(r)
        let p = r.parameters
        switch r.operation {
        case "status": return .object(["app": .string("Act"), "pid": .number(Double(ProcessInfo.processInfo.processIdentifier)), "isActive": .bool(NSApp.isActive), "protocolVersion": .number(1), "projectRoot": .string(root.path), "transport": .string("unix"), "pendingApprovals": .number(Double(jobs.filter { $0.state == "approval_required" }.count))])
        case "schema": return try AutomationContract.schema()
        case "projects.list":
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            return .array(try urls.filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }.sorted { $0.path < $1.path }.map { .object(["name": .string($0.lastPathComponent), "path": .string($0.path)]) })
        case "projects.create", "projects.import":
            let name = try required("name", p), destination = try child(name, in: root)
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw AutomationFailure("name_collision", "Project already exists. Choose a different name.") }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if r.operation == "projects.create" { try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false) }
            else {
                let source = URL(fileURLWithPath: try required("path", p)).resolvingSymlinksInPath()
                guard source.pathExtension.lowercased() == "fountain" else { throw AutomationFailure("invalid_parameters", "Import a Fountain screenplay; linked sidecars are copied with it.") }
                _ = try DocumentText(data: Data(contentsOf: source))
                let staging = root.appendingPathComponent(".import-" + UUID().uuidString)
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
                do {
                    try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
                    for suffix in ["shots.json", "characters", "ai-review.json", "storyboards"] {
                        let asset = source.deletingPathExtension().appendingPathExtension(suffix)
                        if FileManager.default.fileExists(atPath: asset.path) {
                            try rejectSymlinks(asset)
                            try FileManager.default.copyItem(at: asset, to: staging.appendingPathComponent(asset.lastPathComponent))
                        }
                    }
                    try FileManager.default.moveItem(at: staging, to: destination)
                } catch {
                    try? FileManager.default.removeItem(at: staging)
                    throw error
                }
            }
            return .object(["name": .string(name), "path": .string(destination.path)])
        case "documents.list": return .array(documents.map(info))
        case "documents.import":
            let source = URL(fileURLWithPath: try required("path", p)).resolvingSymlinksInPath()
            guard source.pathExtension.lowercased() == "fountain" else { throw AutomationFailure("invalid_parameters", "Import a .fountain screenplay.") }
            _ = try DocumentText(data: Data(contentsOf: source))
            let project = try child(required("project", p), in: root)
            guard (try? project.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { throw AutomationFailure("missing_project", "Create or import the project first.") }
            let destination = try child(p["name"]?.string ?? source.lastPathComponent, in: project)
            guard destination.pathExtension.lowercased() == "fountain" else { throw AutomationFailure("invalid_parameters", "Destination name must end in .fountain.") }
            var items = [(source, destination)]
            for suffix in ["shots.json", "characters", "ai-review.json", "storyboards"] {
                let linked = source.deletingPathExtension().appendingPathExtension(suffix)
                if FileManager.default.fileExists(atPath: linked.path) {
                    try rejectSymlinks(linked)
                    items.append((linked, try managed(destination.deletingPathExtension().appendingPathExtension(suffix))))
                }
            }
            guard items.allSatisfy({ !FileManager.default.fileExists(atPath: $0.1.path) }) else { throw AutomationFailure("name_collision", "A screenplay or linked asset already exists at this destination. Choose a different filename.") }
            let staging = project.appendingPathComponent(".import-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            var moved: [URL] = []
            do {
                for (input, output) in items { try FileManager.default.copyItem(at: input, to: staging.appendingPathComponent(output.lastPathComponent)) }
                for (_, output) in items {
                    try FileManager.default.moveItem(at: staging.appendingPathComponent(output.lastPathComponent), to: output)
                    moved.append(output)
                }
                try FileManager.default.removeItem(at: staging)
            } catch {
                for output in moved { try? FileManager.default.moveItem(at: output, to: staging.appendingPathComponent(output.lastPathComponent)) }
                // Only this operation's newly copied staging data is discarded.
                try? FileManager.default.removeItem(at: staging)
                throw error
            }
            return try execute(.init(operation: "documents.open", parameters: ["path": .string(destination.path)]))
        case "documents.open", "documents.create":
            let path = try managed(URL(fileURLWithPath: required("path", p)))
            guard path.pathExtension.lowercased() == "fountain" else { throw AutomationFailure("invalid_parameters", "Document must use the .fountain extension.") }
            if r.operation == "documents.open", let existing = documents.first(where: { $0.fileURL?.resolvingSymlinksInPath() == path }) { return info(existing) }
            if r.operation == "documents.create" {
                guard !FileManager.default.fileExists(atPath: path.path) else { throw AutomationFailure("name_collision", "A screenplay already exists at this path.") }
                guard FileManager.default.fileExists(atPath: path.deletingLastPathComponent().path) else { throw AutomationFailure("missing_project", "Create or import the project first.") }
                try Data((p["source"]?.string ?? "").utf8).write(to: path, options: .withoutOverwriting)
            }
            let document = try controller.makeDocument(withContentsOf: path, ofType: "dev.act.fountain") as! FountainDocument
            controller.addDocument(document)
            document.makeWindowControllers()
            for window in document.windowControllers { window.window?.orderBack(nil) }
            try prepareShots(document)
            return info(document)
        case "documents.inspect":
            let doc = try target(r); try prepareShots(doc); return info(doc)
        case "documents.save":
            let doc = try target(r, mutation: true)
            let destination = try p["path"]?.string.map { try managed(URL(fileURLWithPath: $0)) }
            guard let url = destination ?? doc.fileURL else { throw AutomationFailure("save_required", "Supply path inside a managed project for the first save.") }
            let isNewPath = doc.fileURL?.standardizedFileURL != url.standardizedFileURL
            if isNewPath {
                guard doc.fileURL == nil else { throw AutomationFailure("use_import", "Use document import to copy a saved screenplay and all its linked assets.") }
                guard url.pathExtension.lowercased() == "fountain", !FileManager.default.fileExists(atPath: url.path) else { throw AutomationFailure("name_collision", "Save destination must be a new .fountain path.") }
            }
            do {
                try doc.writeSafely(to: url, ofType: "dev.act.fountain", for: isNewPath ? .saveAsOperation : .saveOperation)
                doc.fileURL = url
                doc.updateChangeCount(.changeCleared)
            } catch { throw AutomationFailure("save_conflict", error.localizedDescription) }
            return info(doc)
        case "source.read":
            let doc = try target(r)
            let scenes: [AutomationValue] = doc.screenplay.scenes.map { .object(["id": .string($0.id), "heading": .string($0.heading), "text": .string($0.text), "location": .number(Double($0.range.location)), "length": .number(Double($0.range.length))]) }
            var value = info(doc).object!
            if let id = p["sceneID"]?.string, id != "$document" {
                guard let scene = scenes.first(where: { $0["id"].string == id }) else { throw AutomationFailure("missing_anchor", "Scene not found.") }
                value["scene"] = scene
            } else { value["source"] = .string(doc.source); value["scenes"] = .array(scenes) }
            return .object(value)
        case "edits.preview":
            let doc = try target(r, mutation: true)
            let edits = try (p["edits"] ?? .null).decoded([AutomationEdit].self)
            let preview = try AutomationEditing.preview(source: doc.source, revision: doc.automationRevision, edits: edits)
            if previews.count >= 256 { throw AutomationFailure("busy", "Too many pending previews. Apply or discard previews before creating more.") }
            previews[preview.id] = (doc.automationID, preview)
            var result = try AutomationValue.encoded(preview).object!
            result.removeValue(forKey: "result")
            return .object(result)
        case "edits.apply":
            let doc = try target(r, mutation: true), id = try required("previewID", p)
            guard let (documentID, preview) = previews[id], documentID == doc.automationID else { throw AutomationFailure("unknown_preview", "Preview expired or belongs to another document. Preview again.") }
            try doc.applyAutomationPreview(preview)
            previews.removeValue(forKey: id)
            return info(doc)
        case "edits.discard":
            let doc = try target(r), id = try required("previewID", p)
            guard previews[id]?.0 == doc.automationID else { throw AutomationFailure("unknown_preview", "Preview not found in this document.") }
            previews.removeValue(forKey: id); return info(doc)
        case "reviews.list": return try .encoded(target(r).aiReview)
        case "reviews.archives":
            let archive = directory.appendingPathComponent("UnsavedReviews")
            let files = (try? FileManager.default.contentsOfDirectory(at: archive, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return .array(try files.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }.map { file in
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 16_777_216 else { return .object(["archiveID": .string(file.lastPathComponent), "error": .string("Archive exceeds the read limit; inspect the retained file directly.")]) }
                do { return .object(["archiveID": .string(file.lastPathComponent), "path": .string(file.path), "history": try .encoded(JSONDecoder().decode(AutomationReviewLedger.self, from: Data(contentsOf: file)))]) }
                catch { return .object(["archiveID": .string(file.lastPathComponent), "error": .string(error.localizedDescription)]) }
            })
        case "reviews.navigate":
            let doc = try target(r), id = try required("changeID", p)
            guard let change = doc.aiReview.changes.first(where: { $0.id.uuidString == id }), !change.conflicted else { throw AutomationFailure("review_conflict", "Change is no longer anchored.") }
            doc.automationSelection = change.range; doc.automationSelectionRequest = UUID(); return info(doc)
        case "reviews.revert":
            let doc = try target(r, mutation: true)
            try doc.revertAIChanges(id: required("changeID", p)); return info(doc)
        case "reviews.dismiss", "reviews.clear":
            let doc = try target(r, mutation: true)
            if r.operation == "reviews.clear" {
                guard p["confirm"]?.bool == true else { throw AutomationFailure("confirmation_required", "Clearing history requires confirm:true.") }
                doc.clearAIReview()
            } else {
                let id = p["batchID"]?.string
                for i in doc.aiReview.changes.indices where id == nil || doc.aiReview.changes[i].batchID == id { doc.aiReview.changes[i].dismissed = true }
            }
            doc.persistAIReview(); return info(doc)
        case "shots.list", "shots.add", "shots.update", "shots.remove", "shots.generate", "shots.apply": return try shots(r)
        case "characters.list", "characters.create", "characters.mark", "characters.update", "characters.extract": return try characters(r)
        case "images.prepare", "images.export", "images.submit", "images.import", "images.attach", "images.list", "images.select", "images.agents": return try images(r)
        case "jobs.list": return try .encoded(jobs)
        case "jobs.status":
            guard let job = jobs.first(where: { $0.id == p["jobID"]?.string }) else { throw AutomationFailure("unknown_job", "Job not found.") }
            return try .encoded(job)
        case "jobs.cancel":
            let id = try required("jobID", p)
            guard let index = state.jobs.firstIndex(where: { $0.id == id }) else { throw AutomationFailure("unknown_job", "Job not found.") }
            guard ["prepared", "approval_required", "running", "ready", "stale"].contains(state.jobs[index].state) else { throw AutomationFailure("invalid_job_state", "A finished job cannot be cancelled.") }
            tasks[id]?.cancel(); state.jobs[index].state = "cancelled"; try persist(); return try .encoded(state.jobs[index])
        case "jobs.retry":
            let id = try required("jobID", p)
            guard let old = state.jobs.first(where: { $0.id == id }), ["failed", "cancelled", "uncertain_outcome"].contains(old.state) else { throw AutomationFailure("invalid_job_state", "Only failed, cancelled or uncertain jobs can be retried.") }
            guard ["shot", "character"].contains(old.targetKind) else { throw AutomationFailure("use_generation_operation", "Retry local jobs through shots.generate or characters.extract with a current revision.") }
            var new = old; new.id = UUID().uuidString; new.state = old.agent == nil ? "prepared" : "approval_required"; new.error = nil; new.resultPath = nil
            state.jobs.append(new); try persist(); return try .encoded(new)
        default: throw AutomationFailure("unknown_operation", "Use schema to discover supported operations.")
        }
    }

    private func rejectSymlinks(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true else { throw AutomationFailure("invalid_path", "Import refuses symbolic links in linked assets.") }
        if values.isDirectory == true {
            for child in try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) { try rejectSymlinks(child) }
        }
    }

    private func shots(_ r: AutomationRequest) throws -> AutomationValue {
        let doc = try target(r); try prepareShots(doc)
        if r.operation == "shots.list" { return .object(["revision": .string(shotRevision(doc)), "list": try .encoded(doc.shotWorkspace.list)]) }
        _ = try target(r, mutation: true, revision: shotRevision(doc))
        guard let screenplayURL = doc.fileURL else { throw AutomationFailure("save_required", "Save before editing shot metadata.") }
        let p = r.parameters
        var list = doc.shotWorkspace.list
        if r.operation == "shots.generate" {
            guard let scene = doc.screenplay.scenes.first(where: { $0.id == p["sceneID"]?.string }) else { throw AutomationFailure("missing_anchor", "Choose a current sceneID.") }
            guard let executable = doc.shotWorkspace.executableURL, let model = doc.shotWorkspace.modelURL else { throw AutomationFailure("setup_required", "Configure Local AI in Act first.") }
            let job = AutomationJob(documentPath: screenplayURL.path, targetID: scene.id, targetKind: "shots", prompt: scene.text, references: [], referenceHashes: [], inputFingerprint: SceneAnchor.digest(scene.text), state: "running")
            state.jobs.append(job); try persist()
            tasks[job.id] = Task {
                do {
                    let shots = try await LocalShotGenerator().generate(sceneID: scene.id, heading: scene.heading, source: scene.text, configuration: .init(executableURL: executable, modelURL: model))
                    try Task.checkCancellation()
                    let path = try resultURL(for: job, extension: "json")
                    try JSONEncoder().encode(shots).write(to: path, options: .withoutOverwriting)
                    updateJob(job.id) { $0.resultPath = path.path; $0.state = "ready" }
                } catch { finishJob(job.id, error: error) }
                tasks.removeValue(forKey: job.id)
            }
            return try .encoded(job)
        }
        if r.operation == "shots.apply" {
            guard let job = jobs.first(where: { $0.id == p["jobID"]?.string }), job.targetKind == "shots", job.documentPath == screenplayURL.path,
                  job.state == "ready", let path = job.resultPath,
                  let scene = doc.screenplay.scenes.first(where: { $0.id == job.targetID }), SceneAnchor.digest(scene.text) == job.inputFingerprint else {
                throw AutomationFailure("stale_result", "Generated shots no longer match this scene or are not ready.")
            }
            let generated = try JSONDecoder().decode([Shot].self, from: Data(contentsOf: managed(URL(fileURLWithPath: path))))
            try list.replaceShots(for: SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text), with: generated)
        } else if r.operation == "shots.add" {
            let sceneID = try required("sceneID", p)
            guard let scene = doc.screenplay.scenes.first(where: { $0.id == sceneID }) else { throw AutomationFailure("missing_anchor", "Scene not found.") }
            list.acknowledge(SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text))
            list.shots.append(Shot(sceneID: sceneID, framing: p["framing"]?.string ?? "Wide", action: p["action"]?.string ?? "", cameraMovement: p["cameraMovement"]?.string ?? "Static", rationale: p["rationale"]?.string ?? ""))
        } else {
            let id = try required("shotID", p)
            guard let index = list.shots.firstIndex(where: { $0.id.uuidString == id }) else { throw AutomationFailure("unknown_shot", "Shot not found.") }
            if r.operation == "shots.remove" { list.shots.remove(at: index) }
            else {
                if let v = p["framing"]?.string { list.shots[index].framing = v }
                if let v = p["action"]?.string { list.shots[index].action = v }
                if let v = p["cameraMovement"]?.string { list.shots[index].cameraMovement = v }
                if let v = p["rationale"]?.string { list.shots[index].rationale = v }
            }
        }
        let destination = doc.shotWorkspace.fileURL ?? screenplayURL.deletingPathExtension().appendingPathExtension("shots.json")
        try doc.shotWorkspace.applyAutomationList(list, to: managed(destination))
        if r.operation == "shots.apply", let id = p["jobID"]?.string { updateJob(id) { $0.state = "succeeded" } }
        return .object(["document": info(doc), "list": try .encoded(list)])
    }

    private func characters(_ r: AutomationRequest) throws -> AutomationValue {
        let doc = try target(r), p = r.parameters
        let model = doc.characterWorkspace
        if r.operation == "characters.list" { return .object(["revision": .string(characterRevision(doc)), "library": try .encoded(model.library)]) }
        _ = try target(r, mutation: true, revision: characterRevision(doc))
        guard !model.isBusy else { throw AutomationFailure("busy", "Character workspace is busy.") }
        var library = model.library
        switch r.operation {
        case "characters.create":
            library.characters.append(CharacterReference(name: try required("name", p), colourIndex: (library.characters.map(\.colourIndex).max() ?? -1) + 1))
        case "characters.mark":
            let range = try AutomationEditing.match(required("match", p), sceneID: required("sceneID", p), source: doc.source)
            let id: UUID?
            if let text = p["characterID"]?.string {
                guard let uuid = UUID(uuidString: text) else { throw AutomationFailure("invalid_parameters", "Invalid characterID.") }; id = uuid
            } else { id = nil }
            _ = try library.mark(source: doc.source, selection: range, characterID: id)
        case "characters.update":
            guard let i = library.characters.firstIndex(where: { $0.id.uuidString == p["characterID"]?.string }) else { throw AutomationFailure("unknown_character", "Character not found.") }
            if let name = p["name"]?.string, !name.isEmpty { library.characters[i].name = name }
            if let prompt = p["prompt"]?.string { library.characters[i].prompt = prompt }
        case "characters.extract":
            guard let i = library.characters.firstIndex(where: { $0.id.uuidString == p["characterID"]?.string }), !library.characters[i].marks.isEmpty,
                  library.characters[i].marks.allSatisfy({ !$0.isDetached }) else { throw AutomationFailure("missing_anchor", "Character needs current marked action paragraphs.") }
            guard let executable = model.mlxExecutable, let directory = model.mlxModel, let path = doc.fileURL?.path else { throw AutomationFailure("setup_required", "Save and configure MLX in Act first.") }
            let original = library.characters[i]
            let job = AutomationJob(documentPath: path, targetID: original.id.uuidString, targetKind: "extraction", prompt: "Local physical extraction", references: [], referenceHashes: [], inputFingerprint: characterRevision(doc), state: "running")
            state.jobs.append(job); try persist()
            tasks[job.id] = Task {
                do {
                    var updated = original
                    for m in updated.marks.indices {
                        updated.marks[m].traits = try await CharacterPhysicalExtractor.extract(name: original.name, paragraph: updated.marks[m].paragraph, configuration: .init(executable: executable, modelDirectory: directory))
                        updated.marks[m].extractedParagraph = updated.marks[m].paragraph
                    }
                    try Task.checkCancellation()
                    guard characterRevision(doc) == job.inputFingerprint else { throw AutomationFailure("stale_result", "Character changed during extraction. Existing details preserved.") }
                    var next = model.library
                    if updated.prompt.isEmpty { updated.prompt = updated.suggestedPrompt }
                    next.characters[i] = updated
                    try model.applyAutomationLibrary(next)
                    updateJob(job.id) { $0.state = "succeeded" }
                } catch { finishJob(job.id, error: error) }
                tasks.removeValue(forKey: job.id)
            }
            return try .encoded(job)
        default: break
        }
        try model.applyAutomationLibrary(library)
        return .object(["document": info(doc), "library": try .encoded(library)])
    }

    private func resultURL(for job: AutomationJob, extension ext: String) throws -> URL {
        let base = try managed(URL(fileURLWithPath: job.documentPath).deletingPathExtension().appendingPathExtension("storyboards").appendingPathComponent("results"))
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return try managed(base.appendingPathComponent(job.id + "." + ext))
    }

    private func updateJob(_ id: String, _ update: (inout AutomationJob) -> Void) {
        guard let i = state.jobs.firstIndex(where: { $0.id == id }) else { return }
        update(&state.jobs[i])
        do { try persist() } catch { self.error = error.localizedDescription }
    }

    private func finishJob(_ id: String, error: Error) {
        guard jobs.first(where: { $0.id == id })?.state != "uncertain_outcome" else { return }
        updateJob(id) { $0.state = error is CancellationError ? "cancelled" : "failed"; $0.error = error.localizedDescription }
    }

    private func imageFingerprint(_ doc: FountainDocument, kind: String, id: String, references: [String]) throws -> String {
        let target: AutomationValue
        if kind == "shot" {
            try prepareShots(doc)
            guard let shot = doc.shotWorkspace.list.shots.first(where: { $0.id.uuidString == id }),
                  let scene = doc.screenplay.scenes.first(where: { $0.id == shot.sceneID }) else { throw AutomationFailure("unknown_shot", "Shot or its scene no longer exists.") }
            target = .object(["shot": try .encoded(shot), "sceneHash": .string(SceneAnchor.digest(scene.text))])
        } else if kind == "character" {
            guard let character = doc.characterWorkspace.library.characters.first(where: { $0.id.uuidString == id }) else { throw AutomationFailure("unknown_character", "Character no longer exists.") }
            target = try .encoded(character)
        } else { throw AutomationFailure("invalid_parameters", "Image targetKind must be shot or character.") }
        let hashes = try references.map { path -> AutomationValue in
            let url = try managed(URL(fileURLWithPath: path))
            return .string(SceneAnchor.digest(try imageBytes(url).base64EncodedString()))
        }
        return SceneAnchor.digest(String(decoding: try AutomationValue.object(["target": target, "references": .array(hashes)]).data(), as: UTF8.self))
    }

    private func imageBytes(_ url: URL) throws -> Data {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 25_165_824 else { throw CharacterSheetError.missingImage }
        return try CharacterImageGenerator.validate(Data(contentsOf: url)).data
    }

    private func versionsURL(_ doc: FountainDocument) throws -> URL {
        guard let path = doc.fileURL else { throw AutomationFailure("save_required", "Save screenplay before using images.") }
        return try managed(path.deletingPathExtension().appendingPathExtension("storyboards").appendingPathComponent("versions.json"))
    }

    private func versions(_ doc: FountainDocument) throws -> [AutomationImageVersion] {
        let url = try versionsURL(doc)
        if !FileManager.default.fileExists(atPath: url.path) { return [] }
        let library = try JSONDecoder().decode(AutomationStoryboardLibrary.self, from: Data(contentsOf: url))
        guard library.version == 1 else { throw AutomationFailure("unsupported_version", "Unsupported storyboard library version. Existing assets are preserved.") }
        guard Set(library.versions.map(\.id)).count == library.versions.count,
              library.versions.allSatisfy({ CharacterLibraryStore.safeImagePath($0.path) && $0.targetKind == "shot" }) else { throw AutomationFailure("invalid_library", "Storyboard library contains invalid image references.") }
        return library.versions
    }

    private func writeVersions(_ versions: [AutomationImageVersion], for doc: FountainDocument) throws {
        try JSONEncoder().encode(AutomationStoryboardLibrary(versions: versions)).write(to: versionsURL(doc), options: .atomic)
    }

    private func images(_ r: AutomationRequest) throws -> AutomationValue {
        let p = r.parameters
        if r.operation == "images.export" {
            guard let job = jobs.first(where: { $0.id == p["jobID"]?.string }), ["shot", "character"].contains(job.targetKind) else { throw AutomationFailure("unknown_job", "Image request not found.") }
            return try .encoded(job)
        }
        let doc = try target(r)
        if r.operation == "images.agents" {
            return .array(doc.characterWorkspace.connections.map { .object(["agent": .string($0.agent.rawValue), "canGenerate": .bool($0.canGenerate), "canEdit": .bool($0.canEdit), "isCurrent": .bool($0.isCurrent)]) })
        }
        if r.operation == "images.list" { return .object(["versions": try .encoded(versions(doc)), "document": info(doc)]) }
        _ = try target(r, mutation: true)
        guard let url = doc.fileURL else { throw AutomationFailure("save_required", "Save the screenplay before image operations.") }
        if r.operation == "images.prepare" {
            let kind = try required("targetKind", p), id = try required("targetID", p)
            var prompt = try required("prompt", p), paths: [String] = [], hashes: [String] = []
            if kind == "shot" {
                try prepareShots(doc)
                guard let shot = doc.shotWorkspace.list.shots.first(where: { $0.id.uuidString == id }) else { throw AutomationFailure("unknown_shot", "Shot not found.") }
                prompt += "\n\nReviewed shot details:\nFraming: \(shot.framing)\nAction: \(shot.action)\nCamera movement: \(shot.cameraMovement)\nRationale: \(shot.rationale)"
            }
            let references = p["references"]?.array ?? []
            guard references.count <= 8 else { throw AutomationFailure("invalid_parameters", "Select at most eight character reference images.") }
            for (index, reference) in references.enumerated() {
                guard let character = doc.characterWorkspace.library.characters.first(where: { $0.id.uuidString == reference["characterID"].string }),
                      let version = character.versions.first(where: { $0.id.uuidString == reference["versionID"].string }),
                      let directory = doc.characterWorkspace.directory,
                      CharacterLibraryStore.safeImagePath(version.imageFile) else { throw AutomationFailure("missing_reference", "Select an existing character image version.") }
                let path = try managed(directory.appendingPathComponent(version.imageFile))
                guard !paths.contains(path.path) else { throw AutomationFailure("invalid_parameters", "Select each reference version only once.") }
                paths.append(path.path); hashes.append(SceneAnchor.digest(try imageBytes(path).base64EncodedString()))
                prompt += "\nReference \(index + 1): \(character.name)"
            }
            guard prompt.utf8.count <= 32_000 else { throw AutomationFailure("invalid_parameters", "Complete outgoing prompt exceeds 32,000 UTF-8 bytes.") }
            let fingerprint = try imageFingerprint(doc, kind: kind, id: id, references: paths)
            let job = AutomationJob(documentPath: url.path, targetID: id, targetKind: kind, prompt: prompt, references: paths, referenceHashes: hashes, inputFingerprint: fingerprint, state: "prepared")
            state.jobs.append(job); try persist(); return try .encoded(job)
        }
        if r.operation == "images.select" {
            let versionID = try required("versionID", p)
            if p["targetKind"]?.string == "character" {
                var library = doc.characterWorkspace.library
                guard let i = library.characters.firstIndex(where: { $0.id.uuidString == p["targetID"]?.string }),
                      let version = library.characters[i].versions.first(where: { $0.id.uuidString == versionID }) else { throw AutomationFailure("missing_image", "Character image version not found.") }
                _ = try doc.characterWorkspace.imageData(for: version)
                library.characters[i].activeVersionID = version.id
                try doc.characterWorkspace.applyAutomationLibrary(library)
            } else {
                var all = try versions(doc)
                guard let selected = all.first(where: { $0.id == versionID }) else { throw AutomationFailure("missing_image", "Image version not found.") }
                let base = try versionsURL(doc).deletingLastPathComponent()
                _ = try imageBytes(managed(base.appendingPathComponent(selected.path)))
                for i in all.indices where all[i].targetID == selected.targetID { all[i].active = all[i].id == versionID }
                try writeVersions(all, for: doc)
            }
            imageRevision = UUID()
            return info(doc)
        }
        let id = try required("jobID", p)
        guard let index = state.jobs.firstIndex(where: { $0.id == id }), state.jobs[index].documentPath == url.path,
              ["shot", "character"].contains(state.jobs[index].targetKind) else { throw AutomationFailure("unknown_job", "Image request does not belong to this document.") }
        if r.operation == "images.submit" {
            guard state.jobs[index].state == "prepared" else { throw AutomationFailure("invalid_job_state", "Only a prepared request can be submitted.") }
            let agent = try required("agent", p)
            guard let connection = doc.characterWorkspace.availableAgents.first(where: { $0.agent.rawValue == agent }),
                  state.jobs[index].references.isEmpty || connection.canEdit else { throw AutomationFailure("capability_required", "Verify this agent's generation and required reference-edit capability in Act first.") }
            state.jobs[index].agent = agent; state.jobs[index].state = "approval_required"
            try persist()
            if NSApp.delegate is ActApplicationDelegate { showNextApprovalPopup() }
            return try .encoded(state.jobs[index])
        }
        if r.operation == "images.import" {
            guard ["prepared", "stale"].contains(state.jobs[index].state), state.jobs[index].resultPath == nil else { throw AutomationFailure("invalid_job_state", "Import requires an unfulfilled external request.") }
            let image = try CharacterImageGenerator.validate(imageBytes(URL(fileURLWithPath: required("path", p))))
            let path = try resultURL(for: state.jobs[index], extension: image.fileExtension)
            try image.data.write(to: path, options: .withoutOverwriting)
            state.jobs[index].resultPath = path.path; state.jobs[index].state = "ready"
            try persist()
        }
        guard r.operation == "images.import" || r.operation == "images.attach" else { throw AutomationFailure("unknown_operation", "Unsupported image operation.") }
        let job = state.jobs[index]
        guard job.resultPath != nil, ["ready", "stale"].contains(job.state) else { throw AutomationFailure("invalid_job_state", "No unattached result is ready.") }
        let current = (try? imageFingerprint(doc, kind: job.targetKind, id: job.targetID, references: job.references)) == job.inputFingerprint
        guard current || p["acknowledgeStale"]?.bool == true else {
            state.jobs[index].state = "stale"; try persist()
            return .object(["state": .string("stale"), "job": try .encoded(state.jobs[index]), "reviewRequired": .bool(true)])
        }
        try attach(job, to: doc)
        state.jobs[index].state = "succeeded"; try persist()
        return .object(["job": try .encoded(state.jobs[index]), "document": info(doc)])
    }

    private func attach(_ job: AutomationJob, to doc: FountainDocument) throws {
        guard let path = job.resultPath else { throw CharacterSheetError.missingImage }
        let image = try CharacterImageGenerator.validate(imageBytes(managed(URL(fileURLWithPath: path))))
        if job.targetKind == "character" {
            var library = doc.characterWorkspace.library
            guard let i = library.characters.firstIndex(where: { $0.id.uuidString == job.targetID }), let directory = doc.characterWorkspace.directory else { throw AutomationFailure("unknown_character", "Character was removed. Result remains available.") }
            let relative = "images/\(UUID().uuidString).\(image.fileExtension)"
            let destination = try managed(directory.appendingPathComponent(relative))
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.data.write(to: destination, options: .withoutOverwriting)
            let version = CharacterSheetVersion(imageFile: relative, prompt: job.prompt, agent: job.agent ?? "external")
            library.characters[i].versions.append(version); library.characters[i].activeVersionID = version.id
            try doc.characterWorkspace.applyAutomationLibrary(library)
        } else {
            try prepareShots(doc)
            guard doc.shotWorkspace.list.shots.contains(where: { $0.id.uuidString == job.targetID }) else { throw AutomationFailure("unknown_shot", "Shot was removed. Result remains available.") }
            let manifest = try versionsURL(doc), base = manifest.deletingLastPathComponent()
            var all = try versions(doc)
            for i in all.indices where all[i].targetID == job.targetID { all[i].active = false }
            let relative = "images/\(UUID().uuidString).\(image.fileExtension)"
            let destination = try managed(base.appendingPathComponent(relative))
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try image.data.write(to: destination, options: .withoutOverwriting)
            all.append(.init(targetID: job.targetID, targetKind: "shot", path: relative, prompt: job.prompt, jobID: job.id))
            try writeVersions(all, for: doc)
        }
        imageRevision = UUID()
    }

    @discardableResult
    func approve(jobID: String) -> Bool {
        do {
            guard let i = state.jobs.firstIndex(where: { $0.id == jobID }), state.jobs[i].state == "approval_required" else { return false }
            let job = state.jobs[i]
            guard let doc = documents.first(where: { $0.fileURL?.path == job.documentPath }) else { throw AutomationFailure("unknown_document", "Open the request's screenplay before approving it.") }
            _ = try managed(URL(fileURLWithPath: job.documentPath))
            guard try imageFingerprint(doc, kind: job.targetKind, id: job.targetID, references: job.references) == job.inputFingerprint else { throw AutomationFailure("stale_result", "Inputs changed. Prepare a fresh request for approval.") }
            guard let connection = doc.characterWorkspace.availableAgents.first(where: { $0.agent.rawValue == job.agent }), job.references.isEmpty || connection.canEdit else { throw AutomationFailure("capability_required", "Agent capability changed. Verify it in Character Tools.") }
            let reference = try compositeReferences(job.references)
            state.jobs[i].state = "running"
            do { try persist() }
            catch { state.jobs[i].state = "approval_required"; throw error }
            self.error = nil
            tasks[jobID] = Task {
                do {
                    let image = try await CharacterImageGenerator.generate(agent: connection.agent, executable: URL(fileURLWithPath: connection.executablePath), prompt: job.prompt, reference: reference)
                    try Task.checkCancellation()
                    let path = try resultURL(for: job, extension: image.fileExtension)
                    try image.data.write(to: path, options: .withoutOverwriting)
                    updateJob(jobID) { $0.resultPath = path.path; $0.state = "ready" }
                    if (try? imageFingerprint(doc, kind: job.targetKind, id: job.targetID, references: job.references)) == job.inputFingerprint {
                        var completed = job; completed.resultPath = path.path
                        try attach(completed, to: doc)
                        updateJob(jobID) { $0.state = "succeeded" }
                    } else { updateJob(jobID) { $0.state = "stale" } }
                } catch { finishJob(jobID, error: error) }
                tasks.removeValue(forKey: jobID)
            }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func cancelJob(_ id: String) {
        do {
            let result = try perform(.init(operation: "jobs.cancel", parameters: ["jobID": .string(id)]))
            if result["ok"].bool != true { error = result["error"]["message"].string }
        } catch { self.error = error.localizedDescription }
    }

    func attachReviewedResult(_ id: String) {
        guard let job = jobs.first(where: { $0.id == id }), let doc = documents.first(where: { $0.fileURL?.path == job.documentPath }) else {
            error = "Open the request's screenplay before attaching its result."; return
        }
        do {
            let result = try perform(.init(operation: "images.attach", documentID: doc.automationID, expectedRevision: doc.automationRevision, parameters: ["jobID": .string(id), "acknowledgeStale": .bool(true)]))
            if result["ok"].bool != true { error = result["error"]["message"].string }
        } catch { self.error = error.localizedDescription }
    }

    private func compositeReferences(_ paths: [String]) throws -> Data? {
        if paths.isEmpty { return nil }
        if paths.count == 1 { return try imageBytes(managed(URL(fileURLWithPath: paths[0]))) }
        let width = 1024, height = ((paths.count + 1) / 2) * 540
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw CharacterSheetError.missingImage }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
        for (i, path) in paths.enumerated() {
            guard let image = NSImage(data: try imageBytes(managed(URL(fileURLWithPath: path)))) else { throw CharacterSheetError.missingImage }
            let cell = NSRect(x: (i % 2) * 512 + 12, y: height - (i / 2 + 1) * 540 + 36, width: 488, height: 492)
            let scale = min(cell.width / image.size.width, cell.height / image.size.height)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: cell.midX - size.width / 2, y: cell.midY - size.height / 2, width: size.width, height: size.height))
            ("Reference \(i + 1)" as NSString).draw(at: NSPoint(x: cell.minX, y: cell.minY - 24), withAttributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}

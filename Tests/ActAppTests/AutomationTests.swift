import ActCore
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct AutomationTests {
    private let source = "INT. ROOM - DAY #1#\r\n\r\nÉva holds a red book.\r\n\r\nShe waits.\r\n\r\nEXT. STREET - NIGHT #2#\r\n\r\nRain falls.\r\n"

    @MainActor private final class Fixture {
        let directory: URL
        let controller: ActDocumentController
        let service: AutomationService
        let document: FountainDocument
        init(source: String, bom: Bool = false) throws {
            _ = NSApplication.shared
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ActAutomation-" + UUID().uuidString).resolvingSymlinksInPath()
            let root = directory.appendingPathComponent("Projects"), project = root.appendingPathComponent("Film")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            controller = ActDocumentController()
            let path = project.appendingPathComponent("Draft.fountain")
            try ((bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(source.utf8)).write(to: path)
            document = try controller.makeDocument(withContentsOf: path, ofType: "dev.act.fountain") as! FountainDocument
            controller.addDocument(document)
            service = AutomationService(root: root, directory: directory.appendingPathComponent("Endpoint"), controller: controller)
        }
        func close() {
            service.stop()
            for case let owned as FountainDocument in controller.documents {
                owned.characterWorkspace.cancel(); owned.characterWorkspace.save(); owned.shotWorkspace.cancel()
                owned.undoManager?.removeAllActions(); owned.close()
                if controller.documents.contains(where: { $0 === owned }) { controller.removeDocument(owned) }
            }
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func request(_ op: String, _ doc: FountainDocument, _ parameters: [String: AutomationValue] = [:], revision: String? = nil, id: String = UUID().uuidString) -> AutomationRequest {
        .init(requestID: id, operation: op, documentID: doc.automationID, expectedRevision: revision ?? doc.automationRevision, parameters: parameters)
    }

    private func edit(_ kind: String, _ scene: String, _ match: String, text: String? = nil) -> AutomationValue {
        var p: [String: AutomationValue] = ["kind": .string(kind), "sceneID": .string(scene), "match": .string(match)]
        if let text { p["text"] = .string(text) }
        return .object(p)
    }

    private func apply(_ fixture: Fixture, edits: [AutomationValue]) throws -> AutomationValue {
        let preview = try fixture.service.perform(request("edits.preview", fixture.document, ["edits": .array(edits)]))
        #expect(preview["ok"].bool == true)
        return try fixture.service.perform(request("edits.apply", fixture.document, ["previewID": preview["result"]["id"]]))
    }

    @Test func exactEditsPreserveBytesAndUndoWhileRetriesNeverRepeat() throws {
        let f = try Fixture(source: source, bom: true); defer { f.close() }
        let doc = f.document, scene = doc.screenplay.scenes[0].id
        let preview = try f.service.perform(request("edits.preview", doc, ["edits": .array([edit("replace", scene, "red book", text: "blue notebook")])]))
        #expect(doc.source == source)
        let command = request("edits.apply", doc, ["previewID": preview["result"]["id"]], id: "apply-one")
        let response = try f.service.perform(command)
        #expect(response["ok"].bool == true)
        #expect(doc.source == source.replacingOccurrences(of: "red book", with: "blue notebook"))
        #expect(response["result"]["persistence"].string == "pending")
        #expect(try f.service.perform(command) == response)
        #expect(doc.aiReview.changes.count == 1)
        #expect(try f.service.perform(request("reviews.dismiss", doc))["ok"].bool == true)
        #expect(doc.aiReview.changes.count == 1 && doc.aiReview.changes[0].dismissed)
        #expect(try doc.data(ofType: "dev.act.fountain") == Data([0xEF, 0xBB, 0xBF]) + Data(doc.source.utf8))
        doc.undoManager?.undo()
        #expect(doc.source == source)
        #expect(doc.aiReview.changes[0].reverted == true)
        doc.undoManager?.redo()
        #expect(doc.source.contains("blue notebook"))
        #expect(doc.aiReview.changes[0].reverted == false)
        let decomposed = "E\u{301}va"
        #expect(try apply(f, edits: [edit("replace", scene, "Éva", text: decomposed)])["ok"].bool == true)
        let expected = source.replacingOccurrences(of: "red book", with: "blue notebook").replacingOccurrences(of: "Éva", with: decomposed)
        #expect(doc.source.utf8.elementsEqual(expected.utf8))
        var duplicate = command; duplicate.parameters = [:]
        #expect(try f.service.perform(duplicate)["error"]["code"].string == "request_id_conflict")
    }

    @Test func staleAmbiguousAndPartlyInvalidBatchesLeaveWritingUntouched() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let doc = f.document, scene = doc.screenplay.scenes[0].id
        let preview = try f.service.perform(request("edits.preview", doc, ["edits": .array([edit("remove", scene, "She waits.")])]))
        let stale = request("edits.apply", doc, ["previewID": preview["result"]["id"]])
        doc.replaceSource(source + "\r\nLater writing.")
        doc.replaceSource(source)
        #expect(try f.service.perform(stale)["error"]["code"].string == "revision_conflict")
        let invalid = try f.service.perform(request("edits.preview", doc, ["edits": .array([edit("remove", scene, "She waits."), edit("remove", scene, "Does not exist.")])]))
        #expect(invalid["error"]["code"].string == "missing_anchor")
        #expect(doc.source == source)
        doc.replaceSource(source.replacingOccurrences(of: "She waits.", with: "She waits. She waits."))
        let ambiguous = try f.service.perform(request("edits.preview", doc, ["edits": .array([edit("remove", scene, "She waits.")])]))
        #expect(ambiguous["error"]["code"].string == "ambiguous_anchor")
        #expect(doc.aiReview.changes.isEmpty)
        let beforeMove = doc.source
        let badMove: AutomationValue = .object(["kind": .string("move"), "sceneID": .string(scene), "match": .string("red book"), "destinationAnchor": .string("red book"), "destinationSide": .string("before")])
        #expect(try f.service.perform(request("edits.preview", doc, ["edits": .array([badMove])]))["error"]["code"].string == "invalid_parameters")
        #expect(doc.source == beforeMove)
    }

    @Test func movesHavePairedFeedbackAndRevertTogether() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let doc = f.document
        let operation: AutomationValue = .object(["kind": .string("move"), "sceneID": .string(doc.screenplay.scenes[0].id), "match": .string("She waits.\r\n\r\n"), "destinationSceneID": .string(doc.screenplay.scenes[1].id), "destinationAnchor": .string("Rain falls.\r\n"), "destinationSide": .string("after")])
        #expect(try apply(f, edits: [operation])["ok"].bool == true)
        #expect(doc.aiReview.changes.count == 2)
        #expect(Set(doc.aiReview.changes.map(\.operationID)).count == 1)
        #expect(doc.source.hasSuffix("Rain falls.\r\nShe waits.\r\n\r\n"))
        try doc.revertAIChanges(id: doc.aiReview.changes[0].id.uuidString)
        #expect(doc.source == source)
        doc.undoManager?.undo()
        #expect(doc.source.hasSuffix("Rain falls.\r\nShe waits.\r\n\r\n"))
        #expect(doc.aiReview.changes[0].reverted == false)
    }

    @Test func safeReversionPreservesDisjointWritingAndRefusesOverlaps() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let doc = f.document
        _ = try apply(f, edits: [edit("replace", doc.screenplay.scenes[0].id, "red book", text: "green book")])
        let id = doc.aiReview.changes[0].id.uuidString
        doc.replaceSource(doc.source + "\r\nThe end.")
        try doc.revertAIChanges(id: id)
        #expect(doc.source == source + "\r\nThe end.")
        _ = try apply(f, edits: [edit("replace", doc.screenplay.scenes[0].id, "red book", text: "black book")])
        let changed = doc.aiReview.changes.last!.id.uuidString
        doc.replaceSource(doc.source.replacingOccurrences(of: "black book", with: "my own writing"))
        #expect(throws: AutomationFailure.self) { try doc.revertAIChanges(id: changed) }
        #expect(doc.source.contains("my own writing"))
    }

    @Test func savedHistorySurvivesReopenAndUnknownRecoveryCannotReplay() throws {
        let f = try Fixture(source: source); defer { f.close() }
        _ = try apply(f, edits: [edit("remove", f.document.screenplay.scenes[0].id, "She waits.")])
        #expect(try f.service.perform(request("documents.save", f.document))["ok"].bool == true)
        let reopened = try f.controller.makeDocument(withContentsOf: f.document.fileURL!, ofType: "dev.act.fountain") as! FountainDocument
        #expect(reopened.aiReview.changes.count == 1)
        #expect(reopened.aiReview.changes[0].conflicted == false)
        reopened.undoManager?.removeAllActions()
        let pending = request("edits.apply", f.document, ["previewID": .string("unknown")], id: "interrupted")
        var state = AutomationState()
        state.receipts["interrupted"] = .init(fingerprint: SceneAnchor.digest(String(decoding: try AutomationValue.encoded(pending).data(), as: UTF8.self)))
        try JSONEncoder().encode(state).write(to: f.service.directory.appendingPathComponent("state.json"), options: .atomic)
        let recovered = AutomationService(root: f.service.root, directory: f.service.directory, controller: f.controller)
        #expect(try recovered.perform(pending)["error"]["code"].string == "uncertain_outcome")
    }

    @Test func importPreservesOriginalsAndRejectsCollisionsAndEscapingPaths() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let original = f.directory.appendingPathComponent("Original.fountain")
        try Data(source.utf8).write(to: original)
        let scene = f.document.screenplay.scenes[0]
        let planned = ShotListDocument(source: source, anchors: [SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)], shots: [Shot(sceneID: scene.id, action: "Original plan")])
        try ShotListStore.write(planned, to: original.deletingPathExtension().appendingPathExtension("shots.json"))
        var library = CharacterLibrary(); library.sourceFingerprint = SceneAnchor.digest(source)
        library.characters = [CharacterReference(name: "Éva", colourIndex: 0)]
        let characterDirectory = CharacterLibraryStore.directory(for: original)
        try FileManager.default.createDirectory(at: characterDirectory, withIntermediateDirectories: true)
        let metadata = try CharacterLibraryStore.data(library)
        try metadata.write(to: characterDirectory.appendingPathComponent("characters.json"))
        let imported = try f.service.perform(.init(operation: "projects.import", parameters: ["name": .string("Imported"), "path": .string(original.path)]))
        #expect(imported["ok"].bool == true)
        #expect(try String(contentsOf: original, encoding: .utf8) == source)
        #expect(FileManager.default.fileExists(atPath: f.service.root.appendingPathComponent("Imported/Original.fountain").path))
        let second = try f.service.perform(.init(operation: "documents.import", parameters: ["project": .string("Film"), "path": .string(original.path)]))
        #expect(second["ok"].bool == true)
        #expect(f.controller.documents.count == 2)
        if let copied = f.controller.documents.last as? FountainDocument {
            #expect(copied.characterWorkspace.library.characters.first?.name == "Éva")
            #expect(copied.shotWorkspace.list.shots.first?.action == "Original plan")
        }
        #expect(f.document.characterWorkspace.library.characters.isEmpty)
        #expect(try Data(contentsOf: characterDirectory.appendingPathComponent("characters.json")) == metadata)
        if let copy = f.controller.documents.last, copy !== f.document { copy.undoManager?.removeAllActions(); copy.close() }
        #expect(try f.service.perform(.init(operation: "projects.create", parameters: ["name": .string("Imported")]))["error"]["code"].string == "name_collision")
        try FileManager.default.createSymbolicLink(at: f.service.root.appendingPathComponent("Escape"), withDestinationURL: f.directory)
        #expect(throws: AutomationFailure.self) { try f.service.managed(f.service.root.appendingPathComponent("Escape/Original.fountain")) }
        f.document.fileURL = original
        #expect(try f.service.perform(request("edits.preview", f.document, ["edits": .array([edit("remove", "$document", "She waits.")])]))["error"]["code"].string == "outside_project_root")
    }

    @Test func imageImportRetainsStaleResultsAndVersionHistory() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let doc = f.document
        let revision = try f.service.perform(request("shots.list", doc))["result"]["revision"].string!
        let added = try f.service.perform(request("shots.add", doc, ["sceneID": .string(doc.screenplay.scenes[0].id), "action": .string("Éva waits")], revision: revision))
        let shotID = added["result"]["list"]["shots"].array![0]["id"].string!
        let prepared = try f.service.perform(request("images.prepare", doc, ["targetKind": .string("shot"), "targetID": .string(shotID), "prompt": .string("A wide storyboard frame")]))
        let jobID = prepared["result"]["id"].string!
        #expect(prepared["result"]["prompt"].string?.contains("Éva waits") == true)
        #expect(prepared["result"]["prompt"].string?.contains("Rain falls") == false)
        let image = f.directory.appendingPathComponent("frame.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: image)
        let updated = try f.service.perform(request("shots.update", doc, ["shotID": .string(shotID), "action": .string("She leaves")], revision: added["result"]["document"]["shotRevision"].string!))
        #expect(updated["ok"].bool == true)
        let imported = try f.service.perform(request("images.import", doc, ["jobID": .string(jobID), "path": .string(image.path)]))
        #expect(imported["result"]["state"].string == "stale")
        #expect(try f.service.perform(request("images.list", doc))["result"]["versions"].array?.isEmpty == true)
        #expect(try f.service.perform(request("images.attach", doc, ["jobID": .string(jobID), "acknowledgeStale": .bool(true)]))["ok"].bool == true)
        let all = try f.service.perform(request("images.list", doc))["result"]["versions"].array!
        #expect(all.count == 1)
        #expect(all[0]["path"].string?.hasPrefix("images/") == true)
        #expect(FileManager.default.fileExists(atPath: image.path))
        let second = try f.service.perform(request("images.prepare", doc, ["targetKind": .string("shot"), "targetID": .string(shotID), "prompt": .string("A second storyboard version")]))
        #expect(try f.service.perform(request("images.import", doc, ["jobID": second["result"]["id"], "path": .string(image.path)]))["ok"].bool == true)
        let retained = try f.service.perform(request("images.list", doc))["result"]["versions"].array!
        #expect(retained.count == 2)
        #expect(retained[0]["active"].bool == false)
        #expect(try f.service.perform(request("images.select", doc, ["versionID": retained[0]["id"]]))["ok"].bool == true)
        #expect(try f.service.perform(request("images.list", doc))["result"]["versions"].array![0]["active"].bool == true)
        let denied = try f.service.perform(request("images.submit", doc, ["jobID": .string(jobID), "agent": .string("codex")]))
        #expect(denied["ok"].bool == false)
        let originalProject = doc.fileURL!.deletingLastPathComponent(), relocated = f.service.root.appendingPathComponent("Relocated")
        try FileManager.default.moveItem(at: originalProject, to: relocated)
        defer { try? FileManager.default.moveItem(at: relocated, to: originalProject) }
        for version in retained {
            let relative = try #require(version["path"].string)
            let movedImage = relocated.appendingPathComponent("Draft.storyboards").appendingPathComponent(relative)
            #expect(try CharacterImageGenerator.validate(Data(contentsOf: movedImage)).fileExtension == "png")
        }
    }

    @Test func configuredFixtureAgentCannotRunBeforeApprovalAndRunsOnlyOnce() async throws {
        let f = try Fixture(source: source); defer { f.close() }
        let doc = f.document
        let image = f.directory.appendingPathComponent("fixture.png")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try bitmap.representation(using: .png, properties: [:])!.write(to: image)
        let marker = f.directory.appendingPathComponent("invocations.txt"), executable = f.directory.appendingPathComponent("fixture-agent")
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // A local fixture stands in for an approved provider; no account or network is used.
        try Data(("#!/bin/sh\nprintf 'invoked\\n' >> " + quoted(marker.path) + "\n/bin/cp " + quoted(image.path) + " generated.png\n").utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        var connection = ImageAgentConnection(agent: .codex, executable: executable)
        connection.generationVerified = true
        doc.characterWorkspace.connections = [connection]
        let listed = try f.service.perform(request("shots.list", doc))
        let added = try f.service.perform(request("shots.add", doc, ["sceneID": .string(doc.screenplay.scenes[0].id)], revision: listed["result"]["revision"].string))
        let id = added["result"]["list"]["shots"].array![0]["id"]
        let prepared = try f.service.perform(request("images.prepare", doc, ["targetKind": .string("shot"), "targetID": id, "prompt": .string("Approved fixture prompt")]))
        let jobID = prepared["result"]["id"].string!
        let submit = request("images.submit", doc, ["jobID": .string(jobID), "agent": .string("codex")])
        #expect(try f.service.perform(submit)["result"]["state"].string == "approval_required")
        #expect(FileManager.default.fileExists(atPath: marker.path) == false)
        f.service.approve(jobID: jobID)
        for _ in 0..<100 {
            if f.service.jobs.first(where: { $0.id == jobID })?.state != "running" { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(f.service.jobs.first(where: { $0.id == jobID })?.state == "succeeded")
        _ = try f.service.perform(submit)
        #expect(try String(contentsOf: marker, encoding: .utf8) == "invoked\n")
        #expect(try f.service.perform(request("images.list", doc))["result"]["versions"].array?.count == 1)
    }

    @Test func clearingHistoryDoesNotResurrectItThroughNativeUndo() throws {
        let f = try Fixture(source: source); defer { f.close() }
        _ = try apply(f, edits: [edit("replace", f.document.screenplay.scenes[0].id, "red book", text: "blue notebook")])
        #expect(try f.service.perform(request("reviews.clear", f.document, ["confirm": .bool(true)]))["ok"].bool == true)
        f.document.undoManager?.undo()
        #expect(f.document.source == source)
        #expect(f.document.aiReview.changes.isEmpty)
        f.document.undoManager?.redo()
        #expect(f.document.source.contains("blue notebook"))
        #expect(f.document.aiReview.changes.isEmpty)
    }

    @Test func popupAcceptanceKeepsEditsAndRejectionSafelyRestoresSource() throws {
        let f = try Fixture(source: source); defer { f.close() }
        _ = try apply(f, edits: [edit("replace", f.document.screenplay.scenes[0].id, "red book", text: "blue notebook")])
        let batch = f.document.aiReview.changes[0].batchID
        let history = f.document.fileURL!.deletingPathExtension().appendingPathExtension("ai-review.json")
        let savedHistory = try Data(contentsOf: history)
        try FileManager.default.removeItem(at: history)
        try FileManager.default.createDirectory(at: history, withIntermediateDirectories: false)
        #expect(throws: AutomationFailure.self) { try f.document.acceptAIChanges(batchID: batch) }
        #expect(f.document.aiReview.changes[0].accepted == nil)
        #expect(f.document.source.contains("blue notebook"))
        try FileManager.default.removeItem(at: history)
        try savedHistory.write(to: history)
        try f.document.acceptAIChanges(batchID: batch)
        #expect(f.document.source.contains("blue notebook"))
        #expect(f.document.aiReview.changes[0].accepted == true)
        #expect(f.document.aiReview.changes[0].dismissed)
        try f.document.revertAIChanges(id: batch)
        #expect(f.document.source == source)
        #expect(f.document.aiReview.changes[0].accepted == false)
        #expect(f.document.aiReview.changes[0].reverted)
    }

    @Test func gutterMarkersOpenAnchoredReviewWithoutMovingCaret() throws {
        let f = try Fixture(source: source); defer { f.close() }
        _ = try apply(f, edits: [edit("replace", f.document.screenplay.scenes[0].id, "red book", text: "blue notebook"), edit("remove", f.document.screenplay.scenes[0].id, "She waits.")])
        let view = NSHostingView(rootView: ScreenplayEditor(document: f.document, sourceMode: false, selection: NSRange(location: 0, length: 0), selectionRequest: UUID()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000)); window.orderFront(nil)
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded(); TestEditorHost.pump()
        let text = try #require(TestEditorHost.findText(in: view) as? ScreenplayTextView)
        text.layoutSubtreeIfNeeded()
        let buttons = text.subviews.compactMap { $0 as? NSButton }
        #expect(Set(buttons.map(\.title)) == Set(["+", "−"]))
        let caret = text.selectedRange()
        let origin = text.enclosingScrollView?.contentView.bounds.origin
        for symbol in ["+", "−"] {
            let button = try #require(buttons.first { $0.title == symbol })
            button.performClick(nil)
            TestEditorHost.pump()
            let popover = try #require(text.reviewPopover)
            #expect(popover.isShown)
            #expect(popover.positioningRect == button.bounds)
            #expect(text.selectedRange() == caret)
            #expect(text.enclosingScrollView?.contentView.bounds.origin == origin)
            popover.close()
        }
        let first = f.document.aiReview.changes[0]
        try f.document.acceptAIChange(operationID: first.operationID)
        #expect(f.document.aiReview.changes[0].accepted == true)
        #expect(f.document.aiReview.changes[1].accepted == nil)
        try f.document.revertAIChanges(id: f.document.aiReview.changes[1].operationID.uuidString)
        #expect(f.document.source.contains("She waits."))
        #expect(f.document.source.contains("blue notebook"))
    }

    @Test func unsavedReviewRecoversUniquelyAndFollowsFirstSave() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let unsaved = FountainDocument()
        try unsaved.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        unsaved.fileType = "dev.act.fountain"; f.controller.addDocument(unsaved)
        #expect(try f.service.perform(request("images.prepare", unsaved, ["targetKind": .string("shot"), "targetID": .string("not-yet-saved"), "prompt": .string("A frame")]))["error"]["code"].string == "save_required")
        let preview = try f.service.perform(request("edits.preview", unsaved, ["edits": .array([edit("replace", unsaved.screenplay.scenes[0].id, "red book", text: "blue notebook")])]))
        #expect(try f.service.perform(request("edits.apply", unsaved, ["previewID": preview["result"]["id"]]))["ok"].bool == true)
        let archives = try f.service.perform(.init(operation: "reviews.archives"))["result"].array!
        #expect(archives.count == 1)
        let restored = FountainDocument()
        try restored.read(from: Data(unsaved.source.utf8), ofType: "dev.act.fountain")
        restored.fileType = "dev.act.fountain"; f.controller.addDocument(restored)
        let recovered = try f.service.perform(request("reviews.list", restored))
        #expect(recovered["result"]["changes"].array?.count == 1)
        let path = f.service.root.appendingPathComponent("Film/Recovered.fountain")
        #expect(try f.service.perform(request("documents.save", restored, ["path": .string(path.path)]))["ok"].bool == true)
        #expect(FileManager.default.fileExists(atPath: path.deletingPathExtension().appendingPathExtension("ai-review.json").path))
        let reopened = try f.controller.makeDocument(withContentsOf: path, ofType: "dev.act.fountain") as! FountainDocument
        #expect(reopened.aiReview.changes.count == 1)
        reopened.undoManager?.removeAllActions()
    }

    @Test func actualCompiledCLIUsesTheNativeServiceWithoutNode() async throws {
        let f = try Fixture(source: source); defer { f.close() }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cli = repo.appendingPathComponent(".build/act")
        guard FileManager.default.isExecutableFile(atPath: cli.path) else { Issue.record("Build CLI with zsh scripts/build-cli.sh before this integration test."); return }
        f.service.start()
        #expect(f.service.error == nil)
        let output = try await BackgroundCommand().run(executable: cli, arguments: ["source", "read", "--document", f.document.automationID], directory: f.directory.appendingPathComponent("Process"), environment: ["ACT_AUTOMATION_DIRECTORY": f.service.directory.path, "PATH": "/usr/bin:/bin"], timeout: 20)
        let response = try JSONDecoder().decode(AutomationValue.self, from: Data(output.utf8))
        #expect(response["ok"].bool == true)
        #expect(response["result"]["source"].string == source)
    }

    @Test func nativeEditorKeepsCaretAndScrollWhenAIChangesEarlierText() throws {
        let longSource = source.replacingOccurrences(of: "She waits.", with: (0..<110).map { "Action line \($0)." }.joined(separator: "\r\n\r\n"))
        let f = try Fixture(source: longSource); defer { f.close() }
        let view = NSHostingView(rootView: ScreenplayEditor(document: f.document, sourceMode: false, selection: NSRange(location: 0, length: 0), selectionRequest: UUID()))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded(); TestEditorHost.pump()
        let text = try #require(TestEditorHost.findText(in: view))
        let caret = (longSource as NSString).range(of: "Action line 90.").location
        text.setSelectedRange(NSRange(location: caret, length: 0)); text.scrollRangeToVisible(text.selectedRange())
        window.makeFirstResponder(text); TestEditorHost.pump()
        let origin = try #require(text.enclosingScrollView).contentView.bounds.origin
        _ = try apply(f, edits: [edit("replace", f.document.screenplay.scenes[0].id, "red book", text: "blue notebook")])
        TestEditorHost.pump()
        #expect(text.string == f.document.source)
        #expect(text.selectedRange().location == caret + 5)
        #expect(text.enclosingScrollView?.contentView.bounds.origin == origin)
        #expect(window.firstResponder === text)
    }

    @Test func disjointBatchesDoNotInvalidateInterveningAIChanges() throws {
        let f = try Fixture(source: source); defer { f.close() }
        let scene = f.document.screenplay.scenes[0].id
        _ = try apply(f, edits: [edit("replace", scene, "She waits.", text: "She listens.")])
        let original = f.document.aiReview.changes[0].id
        _ = try apply(f, edits: [edit("replace", scene, "red book", text: "blue notebook"), edit("replace", f.document.screenplay.scenes[1].id, "Rain falls.", text: "Snow falls.")])
        #expect(f.document.aiReview.changes.first(where: { $0.id == original })?.conflicted == false)
        try f.document.revertAIChanges(id: original.uuidString)
        #expect(f.document.source.contains("She waits."))
        #expect(f.document.source.contains("blue notebook"))
        #expect(f.document.source.contains("Snow falls."))
    }

    @Test func renderAIReviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_AUTOMATION_PREVIEW_DIRECTORY"] else { return }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let text = "Title: First Light\nAuthor: Act\n\nINT. BACK ROOM - NIGHT #1#\n\nA single bulb swings above the table.\n\nOrleans watches the doorway.\n\nHe folds the letter.\n\nEXT. COURTYARD - DAWN #2#\n\nThe city begins to wake.\n"
        let f = try Fixture(source: text); defer { f.close() }
        let scene = f.document.screenplay.scenes[0].id
        let edits = [
            edit("replace", scene, "A single bulb swings above the table.", text: "A bare bulb swings. Its shadow crosses the table."),
            edit("remove", scene, "Orleans watches the doorway."),
            AutomationValue.object(["kind": .string("move"), "sceneID": .string(scene), "match": .string("He folds the letter.\n\n"), "destinationSceneID": .string(f.document.screenplay.scenes[1].id), "destinationAnchor": .string("The city begins to wake.\n"), "destinationSide": .string("after")]),
        ]
        #expect(try apply(f, edits: edits)["ok"].bool == true)
        for (name, width, appearance) in [("review-light", 1280.0, NSAppearance.Name.aqua), ("review-dark", 1280.0, .darkAqua), ("review-narrow", 900.0, .aqua)] {
            let view = NSHostingView(rootView: WorkspaceView(document: f.document))
            view.sizingOptions = []
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance); window.contentView = view
            view.frame = NSRect(x: 0, y: 0, width: width, height: 900)
            view.layoutSubtreeIfNeeded(); TestEditorHost.pump()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + ".png"))
            window.contentView = nil; window.close()
            let popupView = NSHostingView(rootView: AIReviewPopup(document: f.document, close: {}))
            popupView.sizingOptions = []
            let popup = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            popup.isReleasedWhenClosed = false; popup.appearance = NSAppearance(named: appearance); popup.contentView = popupView
            popupView.frame = NSRect(x: 0, y: 0, width: 620, height: 760)
            popupView.layoutSubtreeIfNeeded(); TestEditorHost.pump(); popupView.layoutSubtreeIfNeeded()
            let popupBitmap = try #require(popupView.bitmapImageRepForCachingDisplay(in: popupView.bounds))
            popupView.cacheDisplay(in: popupView.bounds, to: popupBitmap)
            try #require(popupBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(name + "-popup.png"))
            popup.contentView = nil; popup.close()
        }
        let automation = NSHostingView(rootView: AutomationWindow(service: f.service).background(Color(nsColor: .windowBackgroundColor)))
        automation.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: .aqua); window.contentView = automation
        automation.frame = NSRect(x: 0, y: 0, width: 900, height: 750)
        automation.layoutSubtreeIfNeeded(); TestEditorHost.pump()
        let bitmap = try #require(automation.bitmapImageRepForCachingDisplay(in: automation.bounds))
        automation.cacheDisplay(in: automation.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("automation.png"))
        window.contentView = nil; window.close()
        let promptFixture = AutomationJob(documentPath: f.document.fileURL!.path, targetID: "layout-fixture", targetKind: "shot", prompt: "A wide storyboard frame of the reading room at night. Éva holds a blue notebook beside the window. Keep the lighting quiet and the camera at eye level. No text in the image.", references: [], referenceHashes: [], inputFingerprint: "layout-fixture", agent: "codex", state: "approval_required")
        let promptHost = NSHostingView(rootView: ImageApprovalPopup(service: f.service, job: promptFixture, accept: {}, reject: {}))
        promptHost.sizingOptions = []
        let promptPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        promptPanel.isReleasedWhenClosed = false; promptPanel.appearance = NSAppearance(named: .aqua); promptPanel.contentView = promptHost
        promptHost.frame = NSRect(x: 0, y: 0, width: 640, height: 520)
        promptHost.layoutSubtreeIfNeeded(); TestEditorHost.pump(); promptHost.layoutSubtreeIfNeeded()
        let promptBitmap = try #require(promptHost.bitmapImageRepForCachingDisplay(in: promptHost.bounds))
        promptHost.cacheDisplay(in: promptHost.bounds, to: promptBitmap)
        try #require(promptBitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent("image-approval-popup.png"))
        promptPanel.contentView = nil; promptPanel.close()
    }
}

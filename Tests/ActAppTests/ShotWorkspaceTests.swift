import Foundation
import Testing
import ActCore
@testable import Act

@Suite(.serialized)
@MainActor
struct ShotWorkspaceTests {
    @Test("An in-flight generation cannot lose newly added or removed manual shots")
    func generationLocksShotMutations() {
        let anchor = SceneAnchor(id: "kitchen", heading: "INT. KITCHEN - DAWN", text: "Mara waits.")
        let existing = Shot(sceneID: anchor.id, framing: "Close-up", action: "Mara listens.")
        let original = ShotListDocument(source: "Original Fountain", anchors: [anchor], shots: [existing])
        let model = ShotWorkspaceModel()
        model.list = original
        model.isDirty = false
        model.isGenerating = true

        model.addShot(anchor: SceneAnchor(id: "hall", heading: "INT. HALL - DAWN", text: "Footsteps."))
        model.removeShot(existing.id)

        #expect(model.list == original)
        #expect(!model.isDirty)

        model.isGenerating = false
        model.addShot(anchor: anchor)

        #expect(model.list.shots.count == 2)
        #expect(model.list.shots.first == existing)
        #expect(model.isDirty)
    }

    @Test("Adding a manual shot to a changed scene keeps the stale-scene warning")
    func manualAdditionDoesNotAcknowledgeChangedScreenplay() {
        let oldAnchor = SceneAnchor(id: "kitchen", heading: "INT. KITCHEN - DAWN", text: "Mara waits.")
        let changedAnchor = SceneAnchor(id: oldAnchor.id, heading: oldAnchor.heading, text: "Mara hides a letter.")
        let existing = Shot(sceneID: oldAnchor.id, framing: "Wide", action: "Mara waits.")
        let original = ShotListDocument(source: "Previous screenplay revision", anchors: [oldAnchor], shots: [existing])
        let model = ShotWorkspaceModel()
        model.list = original
        model.isDirty = false

        model.addShot(anchor: changedAnchor)

        #expect(model.list.shots.count == 2)
        #expect(model.list.shots.first == existing)
        #expect(model.list.shots.last?.sceneID == oldAnchor.id)
        #expect(model.list.anchors == [oldAnchor])
        #expect(model.list.linkState(for: oldAnchor.id, currentScenes: [changedAnchor]) == .changed)
        #expect(model.list.sourceFingerprint == original.sourceFingerprint)
        #expect(model.isDirty)
    }

    @Test("Deleting a shot preserves other scenes and marks the separate document dirty")
    func deletionOnlyRemovesRequestedShot() {
        let kitchen = SceneAnchor(id: "kitchen", heading: "INT. KITCHEN - DAWN", text: "Mara waits.")
        let hall = SceneAnchor(id: "hall", heading: "INT. HALL - DAWN", text: "Footsteps.")
        let first = Shot(sceneID: kitchen.id, action: "Mara waits.")
        let second = Shot(sceneID: hall.id, action: "Footsteps approach.")
        let original = ShotListDocument(source: "Screenplay remains authoritative", anchors: [kitchen, hall], shots: [first, second])
        let model = ShotWorkspaceModel()
        model.list = original
        model.isDirty = false

        model.removeShot(first.id)

        #expect(model.list.shots == [second])
        #expect(model.list.anchors == original.anchors)
        #expect(model.list.sourceFingerprint == original.sourceFingerprint)
        #expect(model.isDirty)
    }

    @Test("Missing AI setup preserves existing shots before offering replacement")
    func unavailableGenerationPreservesManualWork() throws {
        let source = "INT. KITCHEN - DAWN\n\nMara waits.\n"
        let scene = try #require(FountainParser.parse(source).scenes.first)
        let anchor = SceneAnchor(id: scene.id, heading: scene.heading, text: scene.text)
        let original = ShotListDocument(source: source, anchors: [anchor], shots: [Shot(sceneID: scene.id, action: "Keep this manually planned shot.")])
        let model = ShotWorkspaceModel()
        model.list = original
        model.isDirty = false
        model.executableURL = nil
        model.modelURL = nil

        model.generate(scene: scene, source: source)

        #expect(model.list == original)
        #expect(!model.isDirty)
        #expect(!model.isGenerating)
        #expect(model.error != nil)
    }

    @Test("A runtime failure ends generation without changing another scene's manual shots")
    func asynchronousRuntimeFailurePreservesDocument() async throws {
        let source = "INT. KITCHEN - DAWN\n\nMara waits.\n"
        let scene = try #require(FountainParser.parse(source).scenes.first)
        let otherScene = SceneAnchor(id: "hall", heading: "INT. HALL - DAWN", text: "Footsteps approach.")
        let original = ShotListDocument(source: source, anchors: [otherScene], shots: [Shot(sceneID: otherScene.id, action: "Keep the carefully planned hallway shot.")])
        let model = ShotWorkspaceModel()
        model.list = original
        model.isDirty = false
        model.executableURL = URL(fileURLWithPath: "/nonexistent-act-test-runtime/llama-completion")
        model.modelURL = URL(fileURLWithPath: "/nonexistent-act-test-model/model.gguf")

        model.generate(scene: scene, source: source)
        #expect(model.isGenerating)
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while model.isGenerating, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(!model.isGenerating, "Generation should finish after its missing-runtime error")
        #expect(!model.isDownloading)
        #expect(model.error != nil)
        #expect(model.status.contains("Existing shots preserved"))
        #expect(model.list == original)
        #expect(!model.isDirty)
    }

    @Test("Generation cannot start another operation while downloading or generating")
    func generationDoesNotReenterBusyWorkspace() throws {
        let source = "INT. KITCHEN - DAWN\n\nMara waits.\n"
        let scene = try #require(FountainParser.parse(source).scenes.first)
        for downloading in [false, true] {
            let model = ShotWorkspaceModel()
            model.isDownloading = downloading
            model.isGenerating = !downloading
            model.executableURL = nil
            model.modelURL = nil
            let original = model.list

            model.generate(scene: scene, source: source)

            #expect(model.list == original)
            #expect(!model.isDirty)
            #expect(model.error == nil)
            #expect(model.isDownloading == downloading)
            #expect(model.isGenerating == !downloading)
        }
    }
}

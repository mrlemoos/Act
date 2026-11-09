import XCTest
@testable import ActCore

final class ShotListTests: XCTestCase {
    func testSeparateFileRoundTripPreservesEveryField() throws {
        let anchor = SceneAnchor(id: "scene-1", heading: "INT. CAFÉ - NIGHT", text: "Clara waits.")
        let shot = Shot(sceneID: anchor.id, framing: "Close-up", action: "Clara waits, café light on her face.", cameraMovement: "Locked off", rationale: "Let the silence hold.")
        let document = ShotListDocument(source: "source stays untouched", anchors: [anchor], shots: [shot])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Screenplay.shots.json")
        try ShotListStore.write(document, to: url)
        XCTAssertEqual(try ShotListStore.read(from: url), document)
    }

    func testChangedAndMissingScenesRemainVisible() {
        let anchor = SceneAnchor(id: "one", heading: "EXT. STREET - DAY", text: "Old action")
        let document = ShotListDocument(source: "old", anchors: [anchor])
        XCTAssertEqual(document.linkState(for: "one", currentScenes: [anchor]), .current)
        XCTAssertEqual(document.linkState(for: "one", currentScenes: [SceneAnchor(id: "one", heading: anchor.heading, text: "New action")]), .changed)
        XCTAssertEqual(document.linkState(for: "one", currentScenes: []), .missing)
    }

    func testWrongSceneReplacementIsTransactional() throws {
        let anchor = SceneAnchor(id: "one", heading: "INT. ROOM - DAY", text: "Wait.")
        var document = ShotListDocument(source: "source", anchors: [anchor], shots: [Shot(sceneID: "one", action: "Original")])
        let original = document
        XCTAssertThrowsError(try document.replaceShots(for: anchor, with: [Shot(sceneID: "two")]))
        XCTAssertEqual(document, original)
    }

    func testReplacementCannotCollideWithAnotherScenesShots() throws {
        let first = SceneAnchor(id: "one", heading: "INT. ROOM - DAY", text: "Wait.")
        let second = SceneAnchor(id: "two", heading: "EXT. STREET - DAY", text: "Leave.")
        let retained = Shot(sceneID: "two", action: "Keep this shot")
        var document = ShotListDocument(source: "source", anchors: [first, second], shots: [retained])
        let before = document
        let collision = Shot(id: retained.id, sceneID: "one", action: "Replacement")
        XCTAssertThrowsError(try document.replaceShots(for: first, with: [collision]))
        XCTAssertEqual(document, before)
    }

    func testUnsupportedVersionDoesNotOverwriteExistingFile() throws {
        var document = ShotListDocument(source: "source")
        document.version = 999
        XCTAssertThrowsError(try ShotListStore.data(for: document))
    }

    func testDuplicateIdentifiersRejected() throws {
        let anchor = SceneAnchor(id: "one", heading: "INT. ROOM - DAY", text: "Wait.")
        let shot = Shot(sceneID: "one")
        XCTAssertThrowsError(try ShotListStore.data(for: ShotListDocument(source: "source", anchors: [anchor], shots: [shot, shot])))
    }
    func testValidReplacementAcknowledgesSceneAndRetainsOtherSceneAndMetadata() throws {
        let first = SceneAnchor(id: "one", heading: "INT. ROOM - DAY", text: "Old action.")
        let second = SceneAnchor(id: "two", heading: "EXT. STREET - DAY", text: "Leave.")
        let retained = Shot(sceneID: "two", action: "Keep this shot")
        var document = ShotListDocument(title: "Production list", screenplayName: "Draft.fountain", source: "original draft", anchors: [first, second], shots: [Shot(sceneID: "one"), retained])
        let fingerprint = document.sourceFingerprint
        let updated = SceneAnchor(id: "one", heading: first.heading, text: "New action.")
        let replacement = Shot(sceneID: "one", action: "A new beat")
        try document.replaceShots(for: updated, with: [replacement])
        XCTAssertEqual(document.shots, [retained, replacement])
        XCTAssertEqual(document.linkState(for: "one", currentScenes: [updated, second]), .current)
        XCTAssertEqual(document.title, "Production list")
        XCTAssertEqual(document.screenplayName, "Draft.fountain")
        XCTAssertEqual(document.sourceFingerprint, fingerprint)
        XCTAssertEqual(try ShotListStore.decode(ShotListStore.data(for: document)), document)
    }

    func testInvalidWriteLeavesPreviouslySavedFileIntactAndDecodeRejectsWrongAnchors() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Shots.json")
        let valid = ShotListDocument(source: "draft")
        try ShotListStore.write(valid, to: url)
        let bytes = try Data(contentsOf: url)
        var invalid = valid
        invalid.version = 999
        XCTAssertThrowsError(try ShotListStore.write(invalid, to: url))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let wrong = ShotListDocument(source: "draft", shots: [Shot(sceneID: "missing")])
        XCTAssertThrowsError(try ShotListStore.decode(JSONEncoder().encode(wrong)))
        let anchor = SceneAnchor(id: "one", heading: "INT. ROOM - DAY", text: "Action.")
        let duplicated = ShotListDocument(source: "draft", anchors: [anchor, anchor])
        XCTAssertThrowsError(try ShotListStore.decode(JSONEncoder().encode(duplicated)))
    }

}

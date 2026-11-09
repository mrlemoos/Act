import Foundation
import XCTest
@testable import ActCore

final class ShotRecoveryTests: XCTestCase {
    private let source = "INT. STUDIO - DAY\n\nClara waits.\n"

    private func record(identity: String, dirty: Bool = true, source: String? = nil) -> ShotRecoveryRecord {
        let script = source ?? self.source
        let anchor = SceneAnchor(id: "scene", heading: "INT. STUDIO - DAY", text: script)
        let shot = Shot(sceneID: anchor.id, framing: "Close-up", action: "Clara waits.", cameraMovement: "Static", rationale: "Stay with Clara.")
        return ShotRecoveryRecord(document: ShotListDocument(title: "Clara shots", source: script, anchors: [anchor], shots: [shot]), path: "/tmp/Clara.shots.json", baseline: Data("saved baseline".utf8), isDirty: dirty, screenplayFingerprint: SceneAnchor.digest(script), screenplayIdentity: identity)
    }

    private func withStore(_ body: (ShotRecoveryStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(ShotRecoveryStore(directory: directory))
    }

    func testFirstSaveAndRenameMoveRecoveryWithoutChangingShotMetadata() throws {
        try withStore { store in
            let original = record(identity: "untitled:first")
            try store.save(record: original, identity: original.screenplayIdentity)
            try store.relocate(from: original.screenplayIdentity, to: "/scripts/Clara.fountain", record: original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(identity: original.screenplayIdentity).path))
            let firstSave = try XCTUnwrap(store.load(identity: "/scripts/Clara.fountain", source: source))
            XCTAssertEqual(firstSave.screenplayIdentity, "/scripts/Clara.fountain")
            XCTAssertEqual(firstSave.document, original.document)
            XCTAssertEqual(firstSave.baseline, original.baseline)
            XCTAssertEqual(firstSave.path, original.path)
            try store.relocate(from: firstSave.screenplayIdentity, to: "/scripts/Clara revised.fountain", record: firstSave)
            XCTAssertNil(store.load(identity: "/scripts/Clara.fountain", source: source))
            XCTAssertEqual(store.load(identity: "/scripts/Clara revised.fountain", source: source)?.document, original.document)
        }
    }

    func testCleanSavedListRestoresMetadataAndRemainsCleanAfterScreenplayChanges() throws {
        try withStore { store in
            let saved = record(identity: "/scripts/Clara.fountain", dirty: false)
            try store.save(record: saved, identity: saved.screenplayIdentity)
            XCTAssertEqual(store.load(identity: saved.screenplayIdentity, source: "A screenplay edit"), saved)
        }
    }

    func testNativeRestoredUntitledFindsUniqueDirtyMatchingSource() throws {
        try withStore { store in
            let saved = record(identity: "untitled:before-crash")
            try store.save(record: saved, identity: saved.screenplayIdentity)
            let restored = try XCTUnwrap(store.load(identity: "untitled:restored", source: source))
            XCTAssertEqual(restored, saved)
            try store.relocate(from: restored.screenplayIdentity, to: "untitled:restored", record: restored)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(identity: saved.screenplayIdentity).path))
            XCTAssertEqual(store.load(identity: "untitled:restored", source: source)?.document, saved.document)
        }
    }

    func testUnrelatedCleanAndSavedIdentitiesAreNotClaimedByUntitledMatching() throws {
        try withStore { store in
            for item in [record(identity: "untitled:other", source: "Different screenplay"), record(identity: "untitled:clean", dirty: false), record(identity: "/scripts/same-source.fountain")] {
                try store.save(record: item, identity: item.screenplayIdentity)
            }
            XCTAssertNil(store.load(identity: "untitled:new", source: source))
            XCTAssertNil(store.load(identity: "/scripts/new-name.fountain", source: source))
        }
    }

    func testAmbiguousSourceMatchDoesNotChooseEitherDocument() throws {
        try withStore { store in
            for identity in ["untitled:one", "untitled:two"] {
                try store.save(record: record(identity: identity), identity: identity)
            }
            XCTAssertNil(store.load(identity: "untitled:new", source: source))
            XCTAssertEqual(store.load(identity: "untitled:one", source: source)?.screenplayIdentity, "untitled:one")
        }
    }

    func testMissingFilesAndCorruptRecordsAreBenign() throws {
        try withStore { store in
            XCTAssertNil(store.load(identity: "untitled:missing", source: source))
            try store.discard(identity: "untitled:missing")
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try Data("not JSON".utf8).write(to: store.url(identity: "untitled:broken"))
            XCTAssertNil(store.load(identity: "untitled:broken", source: source))
        }
    }

    func testFailedDestinationWritePreservesOriginalRecovery() throws {
        try withStore { store in
            let original = record(identity: "untitled:original")
            try store.save(record: original, identity: original.screenplayIdentity)
            let destination = "/scripts/Clara.fountain"
            try FileManager.default.createDirectory(at: store.url(identity: destination), withIntermediateDirectories: true)
            XCTAssertThrowsError(try store.relocate(from: original.screenplayIdentity, to: destination, record: original))
            XCTAssertEqual(store.load(identity: original.screenplayIdentity, source: source), original)
        }
    }

    func testSameIdentityRelocationDoesNotDeleteRecovery() throws {
        try withStore { store in
            let original = record(identity: "untitled:original")
            try store.relocate(from: original.screenplayIdentity, to: original.screenplayIdentity, record: original)
            XCTAssertEqual(store.load(identity: original.screenplayIdentity, source: source), original)
        }
    }

    func testBlankUntitledSourceDoesNotClaimAnotherDocument() throws {
        try withStore { store in
            let empty = record(identity: "untitled:empty", source: "")
            try store.save(record: empty, identity: empty.screenplayIdentity)
            XCTAssertNil(store.load(identity: "untitled:new-empty", source: ""))
        }
    }
}

import ActCore
import AppKit
import Foundation
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct NativeDocumentTests {
    @Test func safeSaveWritesCurrentBytesAndUpdatesTheConflictBaseline() throws {
        _ = NSApplication.shared
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Draft.fountain")
        let original = Data([0xEF, 0xBB, 0xBF]) + Data("INT. CAFÉ - DAY\r\n\r\nÉva waits.".utf8)
        try original.write(to: url)
        let document = try load(original, at: url)
        defer { document.undoManager?.removeAllActions() }

        let firstEdit = document.source + "\r\n\r\nShe leaves."
        document.replaceSource(firstEdit)
        try document.writeSafely(to: url, ofType: "dev.act.fountain", for: .saveOperation)
        #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF]) + Data(firstEdit.utf8))

        let secondEdit = firstEdit + "\r\n\r\nEXT. STREET - DAY"
        document.replaceSource(secondEdit)
        try document.writeSafely(to: url, ofType: "dev.act.fountain", for: .saveOperation)
        #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF]) + Data(secondEdit.utf8))
    }

    @Test func externalChangeBlocksNativeSaveAndPreservesBothVersions() throws {
        _ = NSApplication.shared
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Draft.fountain")
        let original = Data("INT. ROOM - DAY\n\nOriginal action.".utf8)
        try original.write(to: url)
        let document = try load(original, at: url)
        defer { document.undoManager?.removeAllActions() }
        document.replaceSource("INT. ROOM - DAY\n\nMy unsaved writing.")
        let external = Data("INT. ROOM - DAY\n\nAnother editor's writing.".utf8)
        try external.write(to: url)

        #expect(throws: DocumentError.self) {
            try document.writeSafely(to: url, ofType: "dev.act.fountain", for: .saveOperation)
        }
        #expect(try Data(contentsOf: url) == external)
        #expect(document.source == "INT. ROOM - DAY\n\nMy unsaved writing.")
    }

    @Test func deletedBackingFileCannotBeSilentlyRecreatedByAutosave() throws {
        _ = NSApplication.shared
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Draft.fountain")
        let original = Data("INT. ROOM - DAY\n\nOriginal action.".utf8)
        try original.write(to: url)
        let document = try load(original, at: url)
        defer { document.undoManager?.removeAllActions() }
        document.replaceSource("My recoverable writing.")
        try FileManager.default.removeItem(at: url)
        #expect(throws: DocumentError.self) {
            try document.writeSafely(to: url, ofType: "dev.act.fountain", for: .autosaveInPlaceOperation)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(document.source == "My recoverable writing.")
    }

    private func load(_ data: Data, at url: URL) throws -> FountainDocument {
        let document = FountainDocument()
        try document.read(from: data, ofType: "dev.act.fountain")
        document.fileURL = url
        document.fileType = "dev.act.fountain"
        return document
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ActDocumentTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

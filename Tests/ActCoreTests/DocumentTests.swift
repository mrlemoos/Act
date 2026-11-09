import Foundation
import Testing
@testable import ActCore

@Suite struct DocumentTests {
    @Test func preservesBytes() throws {
        for source in ["", "Title: Léa\r\n\r\nINT. CAFÉ - DAY\r\n\r\nUnknown **syntax** 🎬\r\n", "a\rb\nc\r\n"] {
            let bytes = Data(source.utf8)
            #expect(try DocumentText(data: bytes).data == bytes)
            let marked = Data([0xEF, 0xBB, 0xBF]) + bytes
            #expect(try DocumentText(data: marked).data == marked)
        }
    }

    @Test func rejectsInvalidUTF8() {
        #expect(throws: DocumentError.self) { try DocumentText(data: Data([0xFF, 0xFE])) }
    }

    @Test func detectsExternalChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("script.fountain")
        let original = Data("INT. HOME - DAY".utf8)
        try original.write(to: url)
        let snapshot = DocumentFileSnapshot(data: original)
        try snapshot.checkUnchanged(at: url)
        try Data("INT. HOME - NIGHT".utf8).write(to: url)
        #expect(throws: DocumentError.self) { try snapshot.checkUnchanged(at: url) }
        try FileManager.default.removeItem(at: url)
        #expect(throws: DocumentError.self) { try snapshot.checkUnchanged(at: url) }
    }
}

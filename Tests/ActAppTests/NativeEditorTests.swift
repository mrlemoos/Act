import ActCore
import AppKit
import Foundation
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct NativeEditorTests {
    @Test func returnInsertsContextualBreaksAndIsOneUndoStep() throws {
        for (source, ending) in [
            ("She waits.", "\n\n"), ("INT. ROOM - DAY", "\n\n"),
            ("# Act one", "\n\n"), ("= She leaves.", "\n\n"),
            ("MARA", "\n"), ("MARA\nHello.", "\n"), ("MARA\n(quietly)", "\n"),
            ("MARA\nHello.\n", "\n"), ("MARA\nHello.\n\n", "\n\n")
        ] {
            let host = try TestEditorHost(source: source)
            defer { host.close() }
            let expected = source + ending
            #expect(host.command(#selector(NSTextView.insertNewline(_:)), selection: NSRange(location: (source as NSString).length, length: 0)))
            #expect(host.textView.string == expected)
            #expect(host.document.source == expected)
            #expect(host.textView.selectedRange() == NSRange(location: (expected as NSString).length, length: 0))
            host.undo()
            #expect(host.document.source == source)
            #expect(host.textView.string == source)
            #expect(host.document.undoManager?.canUndo == false)
            host.redo()
            #expect(host.document.source == expected)
        }
    }

    @Test func returnPreservesCRLFAndWorksInSourceMode() throws {
        for sourceMode in [false, true] {
            let source = "INT. CAFÉ - DAY\r\n\r\nÉva waits."
            let host = try TestEditorHost(source: source, sourceMode: sourceMode)
            defer { host.close() }
            #expect(host.command(#selector(NSTextView.insertNewline(_:)), selection: NSRange(location: (source as NSString).length, length: 0)))
            #expect(host.document.source == source + "\r\n\r\n")
            host.undo()
            #expect(host.document.source == source)
        }
    }

    @Test func returnReplacesOnlyTheSelectedText() throws {
        let source = "Éva opens the door."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let selection = (source as NSString).range(of: "opens")
        #expect(host.command(#selector(NSTextView.insertNewline(_:)), selection: selection))
        #expect(host.document.source == "Éva \n\n the door.")
        #expect(host.textView.selectedRange() == NSRange(location: selection.location + 2, length: 0))
        host.undo()
        #expect(host.document.source == source)
    }

    @Test func modifiedReturnRemainsNative() throws {
        let host = try TestEditorHost(source: "Action.")
        defer { host.close() }
        #expect(!host.command(#selector(NSTextView.insertLineBreak(_:))))
        #expect(host.document.source == "Action.")
    }

    @Test func typedApostrophesAreCurlyWithUndoAndRedo() throws {
        for (source, selection, expected, sourceMode) in [
            ("don", NSRange(location: 3, length: 0), "don’", false),
            ("Mara", NSRange(location: 4, length: 0), "Mara’", false),
            ("Éva", NSRange(location: 3, length: 0), "Éva’", true),
            ("don't", NSRange(location: 3, length: 1), "don’t", false)
        ] {
            let host = try TestEditorHost(source: source, sourceMode: sourceMode)
            defer { host.close() }
            #expect(host.textView.string == source)
            host.insert("'", selection: selection)
            #expect(host.document.source == expected)
            #expect(host.textView.string == expected)
            #expect(host.textView.selectedRange() == NSRange(location: selection.location + 1, length: 0))
            host.undo()
            #expect(host.document.source == source)
            #expect(host.document.undoManager?.canUndo == false)
            host.redo()
            #expect(host.document.source == expected)
        }
    }

    @Test func pasteDoubleQuotesAndExistingPunctuationStayLiteral() throws {
        let original = "Don't change existing source."
        for insertion in ["Don't rewrite this paste.", "\"", "’"] {
            let host = try TestEditorHost(source: original)
            defer { host.close() }
            #expect(host.textView.string == original)
            host.insert(insertion, selection: NSRange(location: (original as NSString).length, length: 0))
            #expect(host.document.source == original + insertion)
            host.undo()
            #expect(host.document.source == original)
        }
    }

    @Test func editingAndUndoPreserveTheUTF8ByteOrderMarker() throws {
        let source = "INT. CAFÉ - DAY\r\n\r\nÉva waits."
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data(source.utf8)
        let document = FountainDocument()
        try document.read(from: bytes, ofType: "dev.act.fountain")
        document.undoManager?.groupsByEvent = false
        #expect(try document.data(ofType: "dev.act.fountain") == bytes)
        document.undoManager?.beginUndoGrouping()
        document.replaceSource(source + "\r\n\r\n")
        document.undoManager?.endUndoGrouping()
        #expect(try document.data(ofType: "dev.act.fountain") == bytes + Data("\r\n\r\n".utf8))
        document.undoManager?.undo()
        #expect(try document.data(ofType: "dev.act.fountain") == bytes)
    }
}

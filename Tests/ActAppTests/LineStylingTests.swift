import ActCore
import AppKit
import Foundation
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct LineStylingTests {
    private static let probe = NSAttributedString.Key("LineStylingProbe")

    private func isBold(_ host: TestEditorHost, at location: Int) -> Bool {
        guard let font = host.textView.textStorage?.attribute(.font, at: location, effectiveRange: nil) as? NSFont else { return false }
        return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
    }

    private func headIndent(_ host: TestEditorHost, at location: Int) -> CGFloat {
        (host.textView.textStorage?.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
    }

    private func type(_ text: String, in host: TestEditorHost) {
        for character in text { host.insert(String(character)) }
    }

    @Test func typingInsideALineDefersStylingUntilReturn() throws {
        let source = "She waits.\n\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        type("INT. ROOM - DAY", in: host)
        let heading = (source as NSString).length
        #expect(!isBold(host, at: heading))
        host.command(#selector(NSTextView.insertNewline(_:)))
        #expect(isBold(host, at: heading))
        #expect(host.document.source == source + "INT. ROOM - DAY\n\n")
    }

    @Test func outlineFollowsCommittedLinesNotKeystrokes() throws {
        let source = "INT. ROOM - DAY\n\nShe waits.\n\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        #expect(host.document.outline.map(\.text) == ["INT. ROOM - DAY"])
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        TestEditorHost.pump()
        type("EXT. ROAD - NIGHT", in: host)
        TestEditorHost.pump()
        #expect(host.document.outline.count == 1)
        host.command(#selector(NSTextView.insertNewline(_:)))
        TestEditorHost.pump()
        #expect(host.document.outline.count == 2)
        while host.document.undoManager?.canUndo == true { host.undo() }
        #expect(host.document.source == source)
        #expect(host.document.outline.count == 1)
    }

    @Test func leavingTheLineCommitsItsStyling() throws {
        let source = "She waits.\n\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        type("INT. ROOM - DAY", in: host)
        #expect(!isBold(host, at: 12))
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        TestEditorHost.pump()
        #expect(isBold(host, at: 12))
    }

    @Test func losingFocusCommitsTheLine() throws {
        let source = "She waits.\n\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.window.makeFirstResponder(host.textView)
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        type("INT. ROOM - DAY", in: host)
        #expect(!isBold(host, at: 12))
        host.window.makeFirstResponder(nil)
        TestEditorHost.pump()
        #expect(isBold(host, at: 12))
    }

    @Test func committingRestylesOnlyTheChangedLines() throws {
        let source = "INT. ROOM - DAY\n\nShe waits.\n\nMARA\nHello.\n\nHe leaves.\n\nEXT. ROAD - NIGHT\n\nRain."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)
        let ns = source as NSString
        let untouched = [ns.range(of: "INT. ROOM"), ns.range(of: "Hello."), ns.range(of: "EXT. ROAD"), ns.range(of: "Rain.")]
        for range in untouched { storage.addAttribute(Self.probe, value: true, range: range) }
        let edit = ns.range(of: "He leaves.")
        host.textView.setSelectedRange(NSRange(location: NSMaxRange(edit), length: 0))
        TestEditorHost.pump()
        type(" Slowly.", in: host)
        let edited = host.textView.string as NSString
        host.textView.setSelectedRange(NSRange(location: edited.range(of: "She waits.").location, length: 0))
        TestEditorHost.pump()
        #expect(edited.range(of: "He leaves. Slowly.").location != NSNotFound)
        for text in ["INT. ROOM", "Hello.", "EXT. ROAD", "Rain."] {
            let range = edited.range(of: text)
            #expect(storage.attribute(Self.probe, at: range.location, effectiveRange: nil) as? Bool == true, "\(text) was restyled")
        }
    }

    @Test func commitRestylesNeighboursWhoseClassificationChanged() throws {
        let source = "She waits.\n\nmara\nHello there."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let ns = source as NSString
        let cue = ns.range(of: "mara")
        let line = ns.range(of: "Hello there.")
        #expect(headIndent(host, at: line.location) == 0)
        host.insert("MARA", selection: cue)
        #expect(headIndent(host, at: line.location) == 0)
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        TestEditorHost.pump()
        #expect(headIndent(host, at: line.location) > 0)
        #expect(headIndent(host, at: cue.location) > headIndent(host, at: line.location))
    }

    @Test func continuationAnnotationsFollowEditsBeforeThem() throws {
        let source = "INT. ROOM - DAY\n\nMARA\nOne.\n\nShe waits.\n\nMARA\nTwo."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let text = try #require(host.textView as? ScreenplayTextView)
        #expect(text.continuations.map(\.text) == [" (CONT'D)"])
        host.insert("Long", selection: NSRange(location: 0, length: 0))
        let cue = (host.textView.string as NSString).range(of: "MARA", options: .backwards)
        #expect(text.continuations.first?.range == cue)
    }

    @Test func undoRestoresStylingWithoutResettingTheScript() throws {
        let source = "She waits.\n\nINT. ROOM - DAY\n\nRain."
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)
        let rain = (source as NSString).range(of: "Rain.")
        storage.addAttribute(Self.probe, value: true, range: rain)
        host.insert("X", selection: NSRange(location: 12, length: 0))
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))
        TestEditorHost.pump()
        #expect(!isBold(host, at: 12))
        host.undo()
        #expect(host.textView.string == source)
        #expect(isBold(host, at: 12))
        #expect(storage.attribute(Self.probe, at: rain.location, effectiveRange: nil) as? Bool == true)
    }
}

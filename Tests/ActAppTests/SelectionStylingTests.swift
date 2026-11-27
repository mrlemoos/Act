import ActCore
import AppKit
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct SelectionStylingTests {
    @Test func movingToEmphasisRevealsItsMarkersAndFadesThePreviousHeading() throws {
        let source = ".INT. ROOM - DAY\n\n*She waits.*\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)
        let emphasis = (source as NSString).range(of: "*She waits.*")

        host.textView.setSelectedRange(NSRange(location: emphasis.location, length: 0))

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .quaternaryLabelColor)
        #expect(storage.attribute(.foregroundColor, at: emphasis.location, effectiveRange: nil) as? NSColor == .textColor)
        #expect(storage.attribute(.foregroundColor, at: NSMaxRange(emphasis) - 1, effectiveRange: nil) as? NSColor == .textColor)
        let font = try #require(storage.attribute(.font, at: emphasis.location + 1, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        #expect(host.document.source == source)
    }

    @Test func movingFromASectionToANotePreservesTheirDistinctColours() throws {
        let source = "# Harbour\n\n[[A note]]\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)
        let note = (source as NSString).range(of: "[[A note]]")

        host.textView.setSelectedRange(NSRange(location: note.location, length: 0))

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .quaternaryLabelColor)
        #expect(storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor == SectionColours.forLevel(1))
        #expect(storage.attribute(.foregroundColor, at: note.location, effectiveRange: nil) as? NSColor == .secondaryLabelColor)
        #expect(host.document.source == source)
    }

    @Test func movingAfterAnEditCommitsFreshStylingBeforeReusingPresentations() throws {
        let source = "She waits.\n\n.INT. ROOM - DAY\n"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)

        host.insert("*", selection: NSRange(location: 0, length: 0))
        host.insert("*", selection: NSRange(location: 11, length: 0))
        let heading = (host.textView.string as NSString).range(of: ".INT. ROOM - DAY")
        host.textView.setSelectedRange(NSRange(location: heading.location, length: 0))
        host.textView.setSelectedRange(NSRange(location: 0, length: 0))

        let font = try #require(storage.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .textColor)
        #expect(storage.attribute(.foregroundColor, at: heading.location, effectiveRange: nil) as? NSColor == .quaternaryLabelColor)
        #expect(host.document.source == "*She waits.*\n\n.INT. ROOM - DAY\n")
    }

    @Test func movingInSourceModeLeavesLiteralMarkersVisible() throws {
        let source = ".INT. ROOM - DAY\n\n*She waits.*\n"
        let host = try TestEditorHost(source: source, sourceMode: true)
        defer { host.close() }
        let storage = try #require(host.textView.textStorage)
        let emphasis = (source as NSString).range(of: "*She waits.*")

        host.textView.setSelectedRange(NSRange(location: emphasis.location, length: 0))

        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .textColor)
        #expect(storage.attribute(.foregroundColor, at: emphasis.location, effectiveRange: nil) as? NSColor == .textColor)
        #expect(host.document.source == source)
    }
}

import ActCore
import AppKit
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct AutocompleteTests {
    // Match app startup before AppKit can create a generic shared document controller.
    private static let documents = ActDocumentController()
    init() { _ = Self.documents }

    @Test func acceptsWithTabAndReturnAsOneUndoStep() throws {
        for sourceMode in [false, true] {
            for command in [#selector(NSTextView.insertTab(_:)), #selector(NSTextView.insertNewline(_:))] {
                let source = "INT. ROOM - DAY\r\n\r\nMARA\r\nHello.\r\n\r\n"
                let host = try TestEditorHost(source: source, sourceMode: sourceMode)
                defer { host.close() }
                host.insert("MAR", selection: NSRange(location: (source as NSString).length, length: 0))
                #expect(host.coordinator.autocomplete.isVisible)
                #expect(host.coordinator.autocomplete.suggestions.first?.insertText == "MARA")
                #expect(host.command(command))
                #expect(host.document.source == source + "MARA")
                host.undo()
                #expect(host.document.source == source + "MAR")
            }
        }
    }

    @Test func escapeDismissesWithoutMutationAndModifiedReturnStaysNative() throws {
        let source = "INT. ROOM - DAY\n\nCUT"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        host.coordinator.refreshAutocomplete()
        #expect(host.coordinator.autocomplete.isVisible)
        #expect(!host.command(#selector(NSTextView.insertLineBreak(_:))))
        #expect(host.command(#selector(NSResponder.cancelOperation(_:))))
        #expect(!host.coordinator.autocomplete.isVisible)
        #expect(host.document.source == source)
    }

    @Test func appDeactivationDismissesList() throws {
        let source = "INT. ROOM - DAY\n\nCUT"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        host.coordinator.refreshAutocomplete()
        #expect(host.coordinator.autocomplete.isVisible)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApplication.shared)
        #expect(!host.coordinator.autocomplete.isVisible)
    }
    @Test func singleClickActionAcceptsAndPopupFollowsScrolledCaret() throws {
        let source = String(repeating: "She waits.\n\n", count: 80) + "CUT"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.window.setFrameOrigin(NSPoint(x: 120, y: 80))
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        host.textView.scrollRangeToVisible(host.textView.selectedRange())
        TestEditorHost.pump()
        host.coordinator.refreshAutocomplete()
        let popup = try #require(host.window.childWindows?.first)
        let scroll = try #require(popup.contentView as? NSScrollView)
        let table = try #require(scroll.documentView as? NSTableView)
        let action = try #require(table.action)
        let rect = host.textView.firstRect(forCharacterRange: NSRange(location: (source as NSString).length - 1, length: 1), actualRange: nil)
        #expect(abs(popup.frame.minX - rect.minX) < 30)
        #expect(abs(popup.frame.maxY - rect.minY) < 30 || abs(popup.frame.minY - rect.maxY) < 30)
        #expect(NSApplication.shared.sendAction(action, to: table.target, from: table))
        #expect(host.document.source.hasSuffix("CUT TO:"))
        #expect(!host.coordinator.autocomplete.isVisible)
        host.undo()
        #expect(host.document.source == source)
    }

    @Test func selectionChangeDismissesWithoutReopening() throws {
        let source = "INT. ROOM - DAY\n\nCUT"
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length, length: 0))
        host.coordinator.refreshAutocomplete()
        #expect(host.coordinator.autocomplete.isVisible)
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length - 1, length: 0))
        #expect(!host.coordinator.autocomplete.isVisible)
        #expect(host.document.source == source)
    }

}

import ActCore
import AppKit
import SwiftUI
@testable import Act

/// Hosts the real AppKit editor in a hidden window owned by the test process.
/// Tests never send system input or attach to the user's running application.
@MainActor
final class TestEditorHost {
    let document: FountainDocument
    let view: NSHostingView<ScreenplayEditor>
    let window: NSWindow
    let textView: NSTextView
    let coordinator: ScreenplayEditor.Coordinator

    init(source: String, settings: ScreenplaySettings = .standard, sourceMode: Bool = false, width: CGFloat = 1000, height: CGFloat = 700) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        document = FountainDocument()
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        document.undoManager?.groupsByEvent = false
        view = NSHostingView(rootView: ScreenplayEditor(document: document, sourceMode: sourceMode, selection: NSRange(location: 0, length: 0), selectionRequest: UUID(), settings: settings))
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        Self.pump()
        guard let text = Self.findText(in: view), let delegate = text.delegate as? ScreenplayEditor.Coordinator else {
            throw HostError.missingEditor
        }
        textView = text
        coordinator = delegate
    }

    @discardableResult
    func command(_ selector: Selector, selection: NSRange? = nil) -> Bool {
        if let selection { textView.setSelectedRange(selection) }
        document.undoManager?.beginUndoGrouping()
        let consumed = coordinator.textView(textView, doCommandBy: selector)
        document.undoManager?.endUndoGrouping()
        Self.pump()
        return consumed
    }

    func insert(_ text: String, selection: NSRange? = nil) {
        let selection = selection ?? textView.selectedRange()
        textView.setSelectedRange(selection)
        document.undoManager?.beginUndoGrouping()
        textView.insertText(text, replacementRange: selection)
        document.undoManager?.endUndoGrouping()
        Self.pump()
    }

    func undo() { document.undoManager?.undo(); Self.pump() }
    func redo() { document.undoManager?.redo(); Self.pump() }

    func close() {
        document.undoManager?.removeAllActions()
        window.contentView = nil
        window.close()
    }

    static func pump() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025)) }

    static func findText(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { findText(in: $0) }.first
    }

    enum HostError: Error { case missingEditor }
}

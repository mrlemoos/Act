import ActCore
import AppKit
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct ScreenplayZoomTests {
    private let source = "INT. ROOM - DAY\n\n" + String(repeating: "She waits for the last train and watches the rain against the window.\n\n", count: 80)

    private final class MagnifyEvent: NSEvent {
        var amount: CGFloat = 0
        var gesturePhase: NSEvent.Phase = .changed
        var point = NSPoint.zero
        override var magnification: CGFloat { amount }
        override var phase: NSEvent.Phase { gesturePhase }
        override var locationInWindow: NSPoint { point }
        override var type: NSEvent.EventType { .magnify }
    }

    @Test func editorRoutesSpreadPinchCancellationAndLimitReversal() throws {
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let scroll = try #require(host.textView.enclosingScrollView as? ScreenplayScrollView)
        let event = MagnifyEvent()
        event.point = scroll.convert(NSPoint(x: 300, y: 300), to: nil)
        for (amount, expected): (CGFloat, CGFloat) in [(0.5, 1.5), (-0.2, 1.2), (5, 2), (-0.1, 1.8), (-5, 0.5), (0.2, 0.6)] {
            event.amount = amount
            host.textView.magnify(with: event)
            TestEditorHost.pump()
            #expect(abs(scroll.magnification - expected) < 0.001)
            #expect(abs(host.zoom.scale - expected) < 0.001)
        }
        event.gesturePhase = .cancelled
        event.amount = 0.5
        host.textView.magnify(with: event)
        #expect(abs(scroll.magnification - 0.6) < 0.001)
        event.gesturePhase = .changed
        event.amount = .nan
        host.textView.magnify(with: event)
        #expect(abs(scroll.magnification - 0.6) < 0.001)
    }

    @Test func zoomPreservesLogicalLayoutSourceSelectionAndUndo() throws {
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let scroll = try #require(host.textView.enclosingScrollView as? ScreenplayScrollView)
        let storage = try #require(host.textView.textStorage)
        let column = host.textView.textContainer?.containerSize.width
        let attributes = NSAttributedString(attributedString: storage)
        let selection = NSRange(location: 25, length: 5)
        host.textView.setSelectedRange(selection)
        let wasEdited = host.document.isDocumentEdited
        let couldUndo = host.document.undoManager?.canUndo
        var columnChanges = 0
        scroll.onColumnWidthChange = { columnChanges += 1 }
        for scale: CGFloat in [0.5, 1, 2, 1.37] {
            host.zoom.set(scale)
            TestEditorHost.pump()
            host.view.layoutSubtreeIfNeeded()
            #expect(abs(scroll.magnification - scale) < 0.001)
            #expect(host.textView.textContainer?.containerSize.width == column)
            #expect(storage.isEqual(to: attributes))
            #expect(host.textView.selectedRange() == selection)
            #expect(host.document.source == source)
            #expect(host.document.isDocumentEdited == wasEdited)
            #expect(host.document.undoManager?.canUndo == couldUndo)
        }
        #expect(columnChanges == 0)
    }

    @Test func nativeMagnificationKeepsPointerAnchorAndAllowsHorizontalScroll() throws {
        let host = try TestEditorHost(source: source, width: 700)
        defer { host.close() }
        let scroll = try #require(host.textView.enclosingScrollView as? ScreenplayScrollView)
        host.textView.layoutManager?.ensureLayout(for: try #require(host.textView.textContainer))
        host.textView.sizeToFit()
        host.view.layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 300))
        let anchor = NSPoint(x: 280, y: 500)
        let before = scroll.contentView.convert(anchor, to: nil)
        scroll.setZoom(1.6, around: anchor)
        TestEditorHost.pump()
        let after = scroll.contentView.convert(anchor, to: nil)
        #expect(abs(before.x - after.x) < 1)
        #expect(abs(before.y - after.y) < 1, "before: \(before), after: \(after), bounds: \(scroll.contentView.bounds), text: \(host.textView.frame)")
        #expect(host.zoom.scale == 1.6)
        #expect(scroll.hasHorizontalScroller)
        #expect(scroll.contentView.bounds.width < host.textView.frame.width)
        scroll.contentView.scroll(to: NSPoint(x: 100, y: scroll.contentView.bounds.minY))
        #expect(scroll.contentView.bounds.minX > 0)
    }

    @Test func controlsClampStepResetAndIgnoreInvalidValues() throws {
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let scroll = try #require(host.textView.enclosingScrollView as? ScreenplayScrollView)
        host.zoom.set(5)
        TestEditorHost.pump()
        #expect(scroll.magnification == 2)
        host.zoom.step(-1)
        TestEditorHost.pump()
        #expect(abs(scroll.magnification - 1.9) < 0.001)
        host.zoom.set(-2)
        host.zoom.step(-1)
        TestEditorHost.pump()
        #expect(scroll.magnification == 0.5)
        host.zoom.step(1)
        TestEditorHost.pump()
        #expect(abs(scroll.magnification - 0.6) < 0.001)
        host.zoom.set(1)
        host.zoom.set(.nan)
        host.zoom.set(.infinity)
        TestEditorHost.pump()
        #expect(scroll.magnification == 1)
        #expect(host.zoom.percentage.contains("100"))
    }

    @Test func editorReconstructionAndSourceModeKeepSessionZoomWhileNewWindowsReset() throws {
        let zoom = ScreenplayZoom()
        zoom.set(1.7)
        let host = try TestEditorHost(source: source, zoom: zoom)
        defer { host.close() }
        host.view.rootView = ScreenplayEditor(document: host.document, sourceMode: true,
            selection: host.textView.selectedRange(), selectionRequest: UUID(), zoom: zoom)
        TestEditorHost.pump()
        #expect(host.textView.enclosingScrollView?.magnification == 1.7)
        let recreated = try TestEditorHost(source: source, sourceMode: true, zoom: zoom)
        defer { recreated.close() }
        #expect(recreated.textView.enclosingScrollView?.magnification == 1.7)
        let separate = try TestEditorHost(source: source)
        defer { separate.close() }
        #expect(separate.textView.enclosingScrollView?.magnification == 1)
        #expect(separate.zoom.scale == 1)
    }

    @Test func scaledTextSupportsHitTestingEditingAndUndo() throws {
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let layout = try #require(host.textView.layoutManager)
        let container = try #require(host.textView.textContainer)
        for scale: CGFloat in [0.5, 1, 2] {
            host.zoom.set(scale)
            TestEditorHost.pump()
            layout.ensureLayout(for: container)
            let index = 25
            let glyph = layout.glyphIndexForCharacter(at: index)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let point = NSPoint(x: rect.minX + host.textView.textContainerOrigin.x + 0.1,
                               y: rect.midY + host.textView.textContainerOrigin.y)
            let windowPoint = host.textView.convert(point, to: nil)
            let hit = host.textView.characterIndexForInsertion(at: host.textView.convert(windowPoint, from: nil))
            #expect(hit == index)
            host.insert("X", selection: NSRange(location: hit, length: 0))
            #expect(host.document.source == (source as NSString).replacingCharacters(in: NSRange(location: index, length: 0), with: "X"))
            host.undo()
            #expect(host.document.source == source)
        }
    }
}

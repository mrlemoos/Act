import ActCore
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct EditorPerformanceTests {
    /// Feature-length shape: about 100 scenes, 4,300 lines and 115,000 UTF-16 units.
    static let featureLength: String = {
        var scenes: [String] = ["Title: Long Script\nAuthor: Test\n"]
        for index in 1...100 {
            scenes.append("""
            INT. HARBOUR OFFICE \(index) - NIGHT

            = Mara weighs the offer.

            Rain hammers the windows. MARA (40s) leans over a desk covered in shipping manifests, *tracing* routes with one finger while the radio hisses in the corner.

            MARA
            You said the cargo would arrive before midnight.

            TOMÁS
            (quietly)
            I said it would arrive. I never promised when.

            She turns away, studies the cranes outside, and lets the silence stretch until it becomes an answer.

            MARA
            Then we wait. All of us.

            TOMÁS
            And if they don't come?

            MARA
            They always come. That's the problem with ambition.

            The radio crackles. A voice, distorted, reads out a list of berth numbers. Mara writes each one down.

            TOMÁS
            (reading over her shoulder)
            Berth nine. That's ours.

            MARA
            It was ours. Not anymore.

            She tears the page free and pockets it. Tomás watches her go to the door, hesitates, then follows.

            TOMÁS
            Where are we going?

            MARA
            Somewhere they won't think to look.

            CUT TO:

            """)
        }
        return scenes.joined(separator: "\n")
    }()

    static func milliseconds(_ block: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

    private static var runningOnCI: Bool { ProcessInfo.processInfo.environment["CI"] == "true" }
    private static var returnLineBudget: Double { runningOnCI ? 150 : 60 }
    private static var caretMoveBudget: Double { runningOnCI ? 30 : 15 }

    @Test func typingInAFeatureLengthScriptStaysResponsive() throws {
        let source = Self.featureLength
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length / 2, length: 0))
        TestEditorHost.pump()
        var samples: [Double] = []
        for _ in 0..<7 {
            host.document.undoManager?.beginUndoGrouping()
            samples.append(Self.milliseconds { host.textView.insertText("a", replacementRange: host.textView.selectedRange()) })
            host.document.undoManager?.endUndoGrouping()
        }
        #expect(Self.median(samples) < 10, "Keystroke took \(samples.map { Int($0) }) ms")
    }

    @Test func returnCommitsALineInAFeatureLengthScriptQuickly() throws {
        let source = Self.featureLength
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        host.textView.setSelectedRange(NSRange(location: (source as NSString).length / 2, length: 0))
        TestEditorHost.pump()
        var samples: [Double] = []
        for _ in 0..<5 {
            host.document.undoManager?.beginUndoGrouping()
            samples.append(Self.milliseconds { _ = host.coordinator.textView(host.textView, doCommandBy: #selector(NSTextView.insertNewline(_:))) })
            host.document.undoManager?.endUndoGrouping()
        }
        print("Return samples: \(samples) ms; median: \(Self.median(samples)) ms")
        #expect(Self.median(samples) < Self.returnLineBudget, "Return took \(samples.map { Int($0) }) ms")
    }

    @Test func movingTheCaretInAFeatureLengthScriptStaysResponsive() throws {
        let source = Self.featureLength
        let host = try TestEditorHost(source: source)
        defer { host.close() }
        let ns = source as NSString
        var samples: [Double] = []

        for index in 0..<7 {
            let location = ns.range(of: "MARA", range: NSRange(location: ns.length / 3 + index * 1500, length: 1500)).location
            samples.append(Self.milliseconds { host.textView.setSelectedRange(NSRange(location: location, length: 0)) })
        }

        print("Caret samples: \(samples) ms; median: \(Self.median(samples)) ms")
        #expect(Self.median(samples) < Self.caretMoveBudget, "Caret move took \(samples.map { Int($0) }) ms")
    }

    @Test(arguments: [false, true]) func workspaceTypingDoesNotReparsePerView(outline: Bool) throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let document = FountainDocument()
        try document.read(from: Data(Self.featureLength.utf8), ofType: "dev.act.fountain")
        document.undoManager?.groupsByEvent = false
        let view = NSHostingView(rootView: WorkspaceView(document: document, initiallyShowsOutline: outline))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.layoutSubtreeIfNeeded()
        TestEditorHost.pump()
        let text = try #require(TestEditorHost.findText(in: view))
        text.setSelectedRange(NSRange(location: (text.string as NSString).length / 2, length: 0))
        TestEditorHost.pump()
        var samples: [Double] = []
        for _ in 0..<7 {
            document.undoManager?.beginUndoGrouping()
            samples.append(Self.milliseconds {
                text.insertText("a", replacementRange: text.selectedRange())
                view.layoutSubtreeIfNeeded()
            })
            document.undoManager?.endUndoGrouping()
            TestEditorHost.pump()
        }
        #expect(Self.median(samples) < 10, "Workspace keystroke took \(samples.map { Int($0) }) ms")
    }
}

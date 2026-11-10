import ActCore
import AppKit
import PDFKit
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct ScreenplayPreviewTests {
    @Test func paperChangeIsDocumentLocalDirtyAndUndoable() throws {
        _ = NSApplication.shared
        let source = "Title: Café\r\n\r\nINT. ROOM - DAY\r\n\r\nAction."
        let document = FountainDocument()
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        document.undoManager?.groupsByEvent = false
        defer { document.undoManager?.removeAllActions() }
        let other = FountainDocument()
        document.undoManager?.beginUndoGrouping()
        document.setPaper(.a4)
        document.undoManager?.endUndoGrouping()
        #expect(document.isDocumentEdited)
        #expect(ScreenplayPaper.read(from: document.source) == .a4)
        #expect(ScreenplayPaper.read(from: other.source) == .usLetter)
        #expect(String(decoding: try document.data(ofType: "dev.act.fountain"), as: UTF8.self) == document.source)
        document.undoManager?.undo()
        #expect(document.source == source)
    }

    @Test func previewRefreshesAfterSourceAndPreferenceChanges() throws {
        _ = NSApplication.shared
        let suite = "ActPreviewTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WritingPreferences(defaults: defaults)
        let document = FountainDocument()
        defer { document.undoManager?.removeAllActions() }
        document.replaceSource("INT. ROOM - DAY\n\nOriginal.")
        let model = ScreenplayPreviewModel(document: document, preferences: preferences)
        #expect(model.pdf?.string?.contains("Original.") == true)
        document.replaceSource("Paper: A4\n\nINT. ROOM - DAY\n\nUpdated.")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        #expect(model.pdf?.string?.contains("Updated.") == true)
        #expect(model.pdf?.page(at: 0)?.bounds(for: .mediaBox).size == ScreenplayPaper.a4.size)
        let previous = model.pdf
        preferences.settings.fontSize = 16
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        #expect(model.pdf !== previous)
        #expect(model.error == nil)
    }

    @Test func menuInstallsCommandPPreview() throws {
        _ = NSApplication.shared
        let previous = NSApp.mainMenu
        defer { NSApp.mainMenu = previous }
        let delegate = ActApplicationDelegate()
        delegate.installMainMenu()
        let file = try #require(NSApp.mainMenu?.items.first { $0.title == "File" }?.submenu)
        let item = try #require(file.items.first { $0.keyEquivalent == "p" })
        #expect(item.title == "PDF Preview…")
        #expect(item.target === delegate)
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @Test func renderPreviewWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["ACT_TEST_PDF_PREVIEW_DIRECTORY"] else { return }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let document = FountainDocument()
        defer { document.undoManager?.removeAllActions() }
        let source = "Title: PORT OF AMBITIONS\nCredit: Written by\nAuthor: Léo Lemos\nContact:\n    Léo Lemos\n    leo@example.com\nDraft date: 10 November 2026\n\nINT. BACK ROOM - NIGHT\n\nAn orange flick cuts through the darkness.\n\nORLEANS\nWelcome to Madrid."
        for (paper, width, appearance) in [(ScreenplayPaper.usLetter, 800.0, NSAppearance.Name.aqua), (.a4, 580.0, .darkAqua)] {
            document.replaceSource(paper.updating(source))
            let model = ScreenplayPreviewModel(document: document)
            let view = NSHostingView(rootView: ScreenplayPreview(document: document, model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            TestEditorHost.pump()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try #require(bitmap.representation(using: .png, properties: [:])).write(to: output.appendingPathComponent(paper.rawValue + ".png"))
            try #require(model.pdf?.dataRepresentation()).write(to: output.appendingPathComponent(paper.rawValue + ".pdf"))
            window.contentView = nil
            window.close()
        }
    }
}

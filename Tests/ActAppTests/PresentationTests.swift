import ActCore
import AppKit
import SwiftUI
import Testing
@testable import Act

@Suite(.serialized)
@MainActor
struct PresentationTests {
    private let source = """
    # Act one
    = Mara waits for an answer.

    ## The departure
    = A familiar morning becomes a farewell.

    ### Two cups
    = Neither wants to speak first.

    Action before the heading.

    INT. ROOM - DAY

    MARA
    You're early.

    She puts the empty cups down.

    MARA
    I thought we had more time.
    """

    @Test func selectedBodyFontDoesNotReplaceSystemSectionStyles() throws {
        let document = try document(source)
        let settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false)
        let host = PresentationHost(editor(document, settings: settings))
        defer { host.close() }
        let text = try #require(host.textView)
        let storage = try #require(text.textStorage)
        let body = try font(at: "Action before the heading.", storage: storage)
        #expect(body.familyName?.localizedCaseInsensitiveContains("Menlo") == true)
        #expect(abs(body.pointSize - CGFloat(14) * 4 / 3) < 0.01)
        let sectionNames = ["Act one", "The departure", "Two cups"]
        var colours: [NSColor] = []
        for name in sectionNames {
            let section = try font(at: name, storage: storage)
            #expect(section.familyName != body.familyName)
            #expect(section.fontName == NSFont.systemFont(ofSize: section.pointSize, weight: .semibold).fontName)
            let index = (source as NSString).range(of: name).location
            colours.append(try #require(storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor))
        }
        let pink = try #require(colours[0].usingColorSpace(.sRGB))
        let blue = try #require(colours[1].usingColorSpace(.sRGB))
        let orange = try #require(colours[2].usingColorSpace(.sRGB))
        #expect(pink.redComponent > pink.blueComponent && pink.blueComponent > pink.greenComponent)
        #expect(blue.blueComponent > blue.greenComponent && blue.greenComponent > blue.redComponent)
        #expect(orange.redComponent > orange.greenComponent && orange.greenComponent > orange.blueComponent)
        #expect(text.string == source)
        #expect(document.source == source)
    }

    @Test func sluglineWeightAndSpacingChangeWithoutRewritingFountain() throws {
        let document = try document(source)
        var settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false)
        let host = PresentationHost(editor(document, settings: settings))
        defer { host.close() }
        let text = try #require(host.textView)
        let storage = try #require(text.textStorage)
        let heading = (source as NSString).range(of: "INT. ROOM - DAY")
        let regular = try font(at: "INT. ROOM - DAY", storage: storage)
        #expect(!NSFontManager.shared.traits(of: regular).contains(.boldFontMask))
        let oneLineY = try glyphRect(for: heading, in: text).minY

        settings.boldSluglines = true
        settings.blankLinesBeforeSlugline = 2
        host.view.rootView = editor(document, settings: settings)
        host.pump()
        let bold = try font(at: "INT. ROOM - DAY", storage: storage)
        #expect(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        let twoLinesY = try glyphRect(for: heading, in: text).minY
        #expect(twoLinesY > oneLineY + 10)
        #expect(text.string == source)
        #expect(document.source == source)
    }

    @Test func rightSettingsSidebarReflowsEditorAndClosingRestoresColumn() throws {
        let suite = "dev.act.tests.presentation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WritingPreferences(defaults: defaults)
        let document = try document(source)
        let host = PresentationHost(WorkspaceView(document: document, preferences: preferences))
        defer { host.close() }
        let text = try #require(host.textView)
        let fullWidth = try editorFrame(text, in: host.view)
        #expect(!host.window.isVisible)

        document.showsSettings = true
        host.pump()
        let sidebarWidth = try editorFrame(text, in: host.view)
        #expect(sidebarWidth.width < fullWidth.width - 250)
        #expect(sidebarWidth.maxX < host.view.bounds.maxX - 250)

        preferences.settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false, dialogueContinuations: false)
        host.pump()
        let body = try font(at: "Action before the heading.", storage: #require(text.textStorage))
        #expect(body.familyName?.localizedCaseInsensitiveContains("Menlo") == true)
        #expect(abs(body.pointSize - CGFloat(14) * 4 / 3) < 0.01)

        document.showsSettings = false
        host.pump()
        #expect(!document.showsSettings)
        let restored = try editorFrame(text, in: host.view)
        #expect(abs(restored.width - fullWidth.width) < 2)
        #expect(text.string == source)
        #expect(document.source == source)
        #expect(!host.window.isVisible)
    }

    @Test func narrowSettingsSidebarKeepsDialogueInsideEditorColumn() throws {
        let suite = "dev.act.tests.presentation." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WritingPreferences(defaults: defaults)
        preferences.settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14)
        let document = try document(source)
        document.showsSettings = true
        let host = PresentationHost(WorkspaceView(document: document, preferences: preferences), size: NSSize(width: 820, height: 700))
        defer { host.close() }
        let text = try #require(host.textView)
        let container = try #require(text.textContainer)
        let scroll = try #require(text.enclosingScrollView)
        let dialogue = (source as NSString).range(of: "I thought we had more time.")
        let rect = try glyphRect(for: dialogue, in: text)
        #expect(rect.maxX <= container.containerSize.width + 1)
        #expect(!scroll.hasHorizontalScroller)
        #expect(text.string == source)
        #expect(document.source == source)
    }

    @Test func liveExampleRendersEachStyleChangeThroughItsObservedPreferences() throws {
        let suite = "dev.act.tests.presentation.example." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = WritingPreferences(defaults: defaults)
        var variants: [(ScreenplayStyleExample.Kind, ScreenplaySettings)] = []
        var setting = ScreenplaySettings.standard
        setting.fontName = "Menlo"; variants.append((.font, setting))
        setting = .standard; setting.fontSize = 14; variants.append((.size, setting))
        setting = .standard; setting.blankLinesBeforeSlugline = 1; variants.append((.spacing, setting))
        setting = .standard; setting.boldSluglines = false; variants.append((.heading, setting))
        setting = .standard; setting.dialogueContinuations = false; variants.append((.dialogue, setting))
        for (kind, changed) in variants {
            preferences.settings = .standard
            let host = PresentationHost(ScreenplayStyleExample(preferences: preferences, kind: kind), size: NSSize(width: 280, height: 700))
            defer { host.close() }
            host.pump()
            let baseline = try host.renderedPNG()
            #expect(try baseline == host.renderedPNG(), "An unchanged example should render consistently")
            preferences.settings = changed
            host.pump()
            let updated = try host.renderedPNG()
            #expect(updated != baseline, "The example must visibly update its \(kind)")
            #expect(try updated == host.renderedPNG(), "The changed example should render consistently")
        }
    }

    @Test func continuationAnnotationsFollowSettingsAndDisappearInSourceMode() throws {
        let document = try document(source)
        var settings = ScreenplaySettings.standard
        let host = PresentationHost(editor(document, settings: settings))
        defer { host.close() }
        let text = try #require(host.textView as? ScreenplayTextView)
        let repeatedCue = (source as NSString).range(of: "MARA", options: .backwards)
        #expect(text.continuations.count == 1)
        let annotation = try #require(text.continuations.first)
        #expect(annotation.range == repeatedCue)
        #expect(annotation.text == " (CONT'D)")
        #expect(!text.string.contains("CONT'D"))

        settings.dialogueContinuations = false
        host.view.rootView = editor(document, settings: settings)
        host.pump()
        #expect(text.continuations.isEmpty)

        settings.dialogueContinuations = true
        host.view.rootView = ScreenplayEditor(document: document, sourceMode: true, selection: NSRange(location: 0, length: 0), selectionRequest: UUID(), settings: settings)
        host.pump()
        #expect(text.continuations.isEmpty)
        let storage = try #require(text.textStorage)
        let heading = try font(at: "INT. ROOM - DAY", storage: storage)
        let body = try font(at: "Action before the heading.", storage: storage)
        let section = try font(at: "Act one", storage: storage)
        #expect(heading == body)
        #expect(section == body)
        #expect(!NSFontManager.shared.traits(of: heading).contains(.boldFontMask))
        #expect(text.string == source)
        #expect(document.source == source)
    }

    @Test func outlineSynopsisSelectionMovesNativeCaretToTheBody() throws {
        let document = try document(source)
        let host = PresentationHost(editor(document, settings: .standard))
        defer { host.close() }
        let text = try #require(host.textView)
        let entry = try #require(FountainOutline.entries(in: FountainParser.parse(source)).first { $0.kind == .synopsis })
        host.view.rootView = ScreenplayEditor(document: document, sourceMode: false, selection: NSRange(location: entry.range.location, length: 0), selectionRequest: UUID())
        host.pump()
        let expected = (source as NSString).range(of: "= Mara waits for an answer.")
        #expect(text.selectedRange() == NSRange(location: expected.location, length: 0))
        #expect(text.selectedRange().location != (source as NSString).range(of: "INT. ROOM - DAY").location)
        #expect(document.source == source)
    }

    @Test func surplusSourceBlankLinesCollapseOnlyInFormattedMode() throws {
        let minimal = "Action.\n\nINT. ROOM - DAY\n\nMore action."
        let surplus = "Action.\n\n\n\n\nINT. ROOM - DAY\n\nMore action."
        let settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false)
        var gaps: [CGFloat] = []
        for textSource in [minimal, surplus] {
            let document = try document(textSource)
            let host = PresentationHost(editor(document, settings: settings))
            defer { host.close() }
            let text = try #require(host.textView)
            let ns = textSource as NSString
            let heading = try glyphRect(for: ns.range(of: "INT. ROOM - DAY"), in: text)
            let action = try glyphRect(for: ns.range(of: "Action."), in: text)
            gaps.append(heading.minY - action.minY)
            #expect(document.source == textSource)
            #expect(text.string == textSource)
        }
        #expect(abs(gaps[0] - gaps[1]) < 1)
        let document = try document(surplus)
        let host = PresentationHost(ScreenplayEditor(document: document, sourceMode: true, selection: NSRange(location: 0, length: 0), selectionRequest: UUID(), settings: settings))
        defer { host.close() }
        let text = try #require(host.textView)
        let ns = surplus as NSString
        let literalGap = try glyphRect(for: ns.range(of: "INT. ROOM - DAY"), in: text).minY - glyphRect(for: ns.range(of: "Action."), in: text).minY
        #expect(literalGap > gaps[1] + 30)
        #expect(document.source == surplus)
    }

    private func document(_ source: String) throws -> FountainDocument {
        let document = FountainDocument()
        try document.read(from: Data(source.utf8), ofType: "dev.act.fountain")
        return document
    }

    private func editor(_ document: FountainDocument, settings: ScreenplaySettings) -> ScreenplayEditor {
        ScreenplayEditor(document: document, sourceMode: false, selection: NSRange(location: 0, length: 0), selectionRequest: UUID(), settings: settings)
    }

    private func font(at text: String, storage: NSTextStorage) throws -> NSFont {
        let range = (storage.string as NSString).range(of: text)
        try #require(range.location != NSNotFound)
        return try #require(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
    }

    private func glyphRect(for range: NSRange, in text: NSTextView) throws -> NSRect {
        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        layout.ensureLayout(for: container)
        return layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: container)
    }

    private func editorFrame(_ text: NSTextView, in host: NSView) throws -> NSRect {
        let scroll = try #require(text.enclosingScrollView)
        return scroll.convert(scroll.bounds, to: host)
    }
}

@MainActor
private final class PresentationHost<Content: View> {
    let view: NSHostingView<Content>
    let window: NSWindow

    init(_ content: Content, size: NSSize = NSSize(width: 1280, height: 900)) {
        _ = NSApplication.shared
        view = NSHostingView(rootView: content)
        view.sizingOptions = []
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        pump()
    }

    var textView: NSTextView? { descendant(of: view, type: NSTextView.self) }

    func pump() {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        view.layoutSubtreeIfNeeded()
    }

    func close() { window.close() }

    func renderedPNG() throws -> Data {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileReadUnknown) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadUnknown) }
        return data
    }

    private func descendant<T: NSView>(of view: NSView, type: T.Type) -> T? {
        if let found = view as? T { return found }
        for child in view.subviews {
            if let found = descendant(of: child, type: type) { return found }
        }
        return nil
    }
}

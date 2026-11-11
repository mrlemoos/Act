import ActCore
import AppKit
import SwiftUI

struct ScreenplayEditor: NSViewRepresentable {
    @ObservedObject var document: FountainDocument
    @ObservedObject private var characters: CharacterWorkspaceModel
    let sourceMode: Bool
    let selection: NSRange
    let selectionRequest: UUID
    var settings: ScreenplaySettings = .standard

    init(document: FountainDocument, sourceMode: Bool, selection: NSRange, selectionRequest: UUID, settings: ScreenplaySettings = .standard) {
        self.document = document; self.sourceMode = sourceMode; self.selection = selection
        self.selectionRequest = selectionRequest; self.settings = settings
        characters = document.characterWorkspace
    }

    private var resolvedFont: NSFont {
        let preference = settings.validated
        let size = CGFloat(preference.fontSize) * 4 / 3
        return NSFontManager.shared.font(withFamily: preference.fontName, traits: [], weight: 5, size: size)
            ?? NSFont(name: preference.fontName, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ScreenplayScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .textBackgroundColor
        let text = ScreenplayTextView(frame: .zero)
        characters.prepare(screenplayURL: document.fileURL, source: document.source)
        text.screenplayDocument = document
        text.isRichText = false
        text.allowsUndo = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.isAutomaticTextReplacementEnabled = false
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isContinuousSpellCheckingEnabled = true
        text.usesFindBar = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.textContainer?.containerSize = NSSize(width: 624, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 64, height: 76)
        text.font = resolvedFont
        text.textColor = .textColor
        text.backgroundColor = .textBackgroundColor
        text.insertionPointColor = .textColor
        text.delegate = context.coordinator
        text.setAccessibilityLabel(L10n.string("Screenplay editor", table: "Writing"))
        text.string = document.source
        scroll.documentView = text
        context.coordinator.textView = text
        scroll.onColumnWidthChange = { [weak coordinator = context.coordinator] in coordinator?.format() }
        context.coordinator.format()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let text = context.coordinator.textView else { return }
        if text.string != document.source {
            let ranges = text.selectedRanges
            text.string = document.source
            let count = (document.source as NSString).length
            text.selectedRanges = ranges.map { value in
                let range = value.rangeValue
                return NSValue(range: NSRange(location: min(range.location, count), length: min(range.length, max(0, count - range.location))))
            }
        }
        if context.coordinator.lastSelectionRequest != selectionRequest {
            context.coordinator.lastSelectionRequest = selectionRequest
            if selection.location <= (text.string as NSString).length {
                text.setSelectedRange(selection)
                text.scrollRangeToVisible(selection)
                text.window?.makeFirstResponder(text)
            }
        }
        context.coordinator.format()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScreenplayEditor
        weak var textView: NSTextView?
        var lastSelectionRequest: UUID
        private var isFormatting = false
        private var formattedSource: String?
        private var formattedSettings: ScreenplaySettings?
        private var formattedSourceMode = false
        private var formattedWidth: CGFloat?
        private var formattedCursorElement: NSRange?
        private struct Highlight: Equatable {
            let range: NSRange
            let colourIndex: Int
            let name: String
        }
        private struct AppliedHighlight {
            let highlight: Highlight
            let underlying: [(NSRange, [NSAttributedString.Key: Any])]
        }
        private var appliedHighlights: [AppliedHighlight] = []
        init(_ parent: ScreenplayEditor) {
            self.parent = parent
            self.lastSelectionRequest = parent.selectionRequest
        }
        func textDidChange(_ notification: Notification) {
            guard !isFormatting, let textView else { return }
            parent.document.replaceSource(textView.string)
            format()
        }
        func textViewDidChangeSelection(_ notification: Notification) { format() }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSTextView.insertNewline(_:)), !textView.hasMarkedText() {
                let selection = textView.selectedRange()
                let insertion = FountainEditing.returnInsertion(in: textView.string, selection: selection)
                textView.insertText(insertion, replacementRange: selection)
                return true
            }
            if commandSelector == Selector(("undo:")) {
                parent.document.undoManager?.undo()
                return true
            }
            if commandSelector == Selector(("redo:")) {
                parent.document.undoManager?.redo()
                return true
            }
            return false
        }
        func format() {
            guard !isFormatting, let textView, !textView.hasMarkedText(), let storage = textView.textStorage else { return }
            isFormatting = true
            defer { isFormatting = false }
            let source = textView.string
            let script = parent.sourceMode ? nil : parent.characters.parsedScreenplay(for: source)
            let cursor = textView.selectedRange().location
            let cursorElement = script?.elements.first { NSLocationInRange(cursor, $0.range) }?.range
            let columnWidth = textView.textContainer?.containerSize.width ?? 624
            if formattedSource == source, formattedSettings == parent.settings,
               formattedSourceMode == parent.sourceMode, formattedWidth == columnWidth,
               formattedCursorElement == cursorElement {
                let typingAttributes = textView.typingAttributes
                updateCharacterHighlights(storage)
                textView.typingAttributes = typingAttributes
                return
            }
            let full = NSRange(location: 0, length: storage.length)
            let font = parent.resolvedFont
            let screenplayTextView = textView as? ScreenplayTextView
            screenplayTextView?.continuations = []
            let base = NSMutableParagraphStyle()
            base.lineSpacing = 3
            base.paragraphSpacing = 0
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: base], range: full)
            appliedHighlights = []
            if let script {
                let characterCues = ScreenplayPresentation.characterCues(in: script, settings: parent.settings)
                let missingBlankLines = ScreenplayPresentation.missingBlankLinesBeforeSluglines(in: script, settings: parent.settings)
                let lineHeight = (textView.layoutManager?.defaultLineHeight(for: font) ?? (font.ascender - font.descender + font.leading)) + base.lineSpacing
                for element in script.elements {
                    guard NSMaxRange(element.range) <= storage.length else { continue }
                    let style = base.mutableCopy() as! NSMutableParagraphStyle
                    let name = String(describing: element.kind).lowercased()
                    if name.contains("character") {
                        style.headIndent = min(190, columnWidth * 0.30)
                        style.firstLineHeadIndent = style.headIndent
                        let literalCue = FountainParser.displayText(element)
                        if let displayedCue = characterCues[element.range.location], displayedCue != literalCue,
                           displayedCue.hasPrefix(literalCue) {
                            let suffix = String(displayedCue.dropFirst(literalCue.count))
                            let width = (suffix as NSString).size(withAttributes: [.font: font]).width
                            // Reserve room on wrapped cues; annotation remains outside the editable source.
                            style.tailIndent = -width
                            screenplayTextView?.continuations.append(.init(range: element.range, text: suffix, font: font))
                        }
                    }
                    else if name.contains("parenthetical") { style.headIndent = min(145, columnWidth * 0.23); style.firstLineHeadIndent = style.headIndent; style.tailIndent = -min(125, columnWidth * 0.20) }
                    else if name.contains("dialogue") { style.headIndent = min(105, columnWidth * 0.17); style.firstLineHeadIndent = style.headIndent; style.tailIndent = -style.headIndent }
                    else if name.contains("transition") { style.alignment = .right }
                    else if element.kind == .centred { style.alignment = .center }
                    if element.kind == .sceneHeading {
                        style.paragraphSpacingBefore = CGFloat(missingBlankLines[element.range.location, default: 0]) * lineHeight
                        if parent.settings.boldSluglines {
                            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask), range: element.range)
                        }
                    }
                    storage.addAttribute(.paragraphStyle, value: style, range: element.range)
                    if element.kind == .section {
                        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold), range: element.range)
                        let level = (element.presentationText ?? element.text).trimmingCharacters(in: .whitespaces).prefix(while: { $0 == "#" }).count
                        storage.addAttribute(.foregroundColor, value: SectionColours.forLevel(level), range: element.range)
                    } else if [.note, .boneyard, .synopsis].contains(element.kind) {
                        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: element.range)
                    }
                    applyEmphasis(in: element.range, storage: storage, baseFont: font)
                    if element.kind == .titlePage, element.text.first?.isWhitespace != true {
                        let text = element.text as NSString
                        let colon = text.range(of: ":")
                        if colon.location != NSNotFound {
                            let label = NSRange(location: element.range.location, length: NSMaxRange(colon))
                            storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: label)
                        }
                    }
                    if !NSLocationInRange(cursor, element.range) {
                        fadeMarkers(in: element.range, storage: storage)
                    }
                }
                collapseSurplusBlankLines(in: script, storage: storage, font: font)
            }
            updateCharacterHighlights(storage)
            storage.endEditing()
            screenplayTextView?.needsDisplay = true
            textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: base]
            formattedSource = source
            formattedSettings = parent.settings
            formattedSourceMode = parent.sourceMode
            formattedWidth = columnWidth
            formattedCursorElement = cursorElement
        }

        private func updateCharacterHighlights(_ storage: NSTextStorage) {
            let highlights = parent.characters.library.characters.flatMap { character in
                character.marks.compactMap { mark -> Highlight? in
                    guard !mark.isDetached, mark.nameRange.location >= 0, mark.nameRange.length > 0,
                          NSMaxRange(mark.nameRange) <= storage.length else { return nil }
                    return Highlight(range: mark.nameRange, colourIndex: character.colourIndex, name: character.name)
                }
            }
            guard highlights != appliedHighlights.map(\.highlight) else { return }
            let keys: Set<NSAttributedString.Key> = [.foregroundColor, .backgroundColor, .toolTip]
            storage.beginEditing()
            for applied in appliedHighlights {
                for (range, attributes) in applied.underlying {
                    for key in keys { storage.removeAttribute(key, range: range) }
                    storage.addAttributes(attributes, range: range)
                }
            }
            appliedHighlights = highlights.map { highlight in
                var underlying: [(NSRange, [NSAttributedString.Key: Any])] = []
                storage.enumerateAttributes(in: highlight.range) { attributes, range, _ in
                    underlying.append((range, attributes.filter { keys.contains($0.key) }))
                }
                let colour = CharacterColours.colour(highlight.colourIndex)
                storage.addAttributes([.backgroundColor: colour.withAlphaComponent(0.18), .foregroundColor: colour,
                                       .toolTip: L10n.format("Character: %@", highlight.name, table: "Writing")], range: highlight.range)
                return AppliedHighlight(highlight: highlight, underlying: underlying)
            }
            storage.endEditing()
        }
        /// Screenplay spacing changes the presentation, never the line endings in Fountain source.
        private func collapseSurplusBlankLines(in script: FountainScreenplay, storage: NSTextStorage, font: NSFont) {
            let source = storage.string as NSString
            let target = max(1, min(parent.settings.blankLinesBeforeSlugline, 2))
            var hasBody = false
            for (index, element) in script.elements.enumerated() {
                if element.kind == .sceneHeading, hasBody {
                    var blankIndices: [Int] = []
                    var preceding = index - 1
                    while preceding >= 0, script.elements[preceding].kind == .blank {
                        blankIndices.append(preceding)
                        preceding -= 1
                    }
                    // Keep the blank paragraphs nearest the heading; collapse only the surplus.
                    for blankIndex in blankIndices.dropFirst(target) {
                        let blank = script.elements[blankIndex]
                        let paragraphRange = source.lineRange(for: blank.range)
                        guard NSMaxRange(paragraphRange) <= storage.length else { continue }
                        let collapsed = NSMutableParagraphStyle()
                        collapsed.minimumLineHeight = 0.01
                        collapsed.maximumLineHeight = 0.01
                        storage.addAttributes([.paragraphStyle: collapsed, .font: NSFontManager.shared.convert(font, toSize: 0.01)], range: paragraphRange)
                    }
                }
                if ![.blank, .titlePage, .note, .boneyard, .section, .synopsis].contains(element.kind) { hasBody = true }
            }
        }

        private let emphasisPattern = #"(?<!\\)(\*{1,3}|_)(?=\S)(.+?\S|\S)\1"#

        private func applyEmphasis(in range: NSRange, storage: NSTextStorage, baseFont: NSFont) {
            guard let expression = try? NSRegularExpression(pattern: emphasisPattern) else { return }
            let source = storage.string as NSString
            for match in expression.matches(in: storage.string, range: range) {
                let marker = source.substring(with: match.range(at: 1))
                let content = match.range(at: 2)
                if marker == "_" {
                    storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: content)
                } else {
                    var font = storage.attribute(.font, at: content.location, effectiveRange: nil) as? NSFont ?? baseFont
                    if marker.count >= 2 { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                    if marker.count == 1 || marker.count == 3 { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                    storage.addAttribute(.font, value: font, range: content)
                }
            }
        }

        private func fadeMarkers(in range: NSRange, storage: NSTextStorage) {
            let controls = #"(?m)^(?:[.@!~>#]+|={3,})|(?<!\\)\[\[|(?<!\\)\]\]|\s#[^#\r\n]+#\s*$|\^$"#
            if let expression = try? NSRegularExpression(pattern: controls) {
                for match in expression.matches(in: storage.string, range: range) {
                    storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: match.range)
                }
            }
            guard let emphasis = try? NSRegularExpression(pattern: emphasisPattern) else { return }
            for match in emphasis.matches(in: storage.string, range: range) {
                let marker = match.range(at: 1)
                storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: marker)
                storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: NSRange(location: NSMaxRange(match.range) - marker.length, length: marker.length))
            }
        }
    }
}

@MainActor
private final class ScreenplayScrollView: NSScrollView {
    var onColumnWidthChange: (() -> Void)?

    override func layout() {
        super.layout()
        guard let text = documentView as? NSTextView else { return }
        let available = contentSize.width
        let column = min(624, max(220, available - 112))
        let inset = max(32, (available - column) / 2)
        let widthChanged = text.textContainer?.containerSize.width != column
        if widthChanged {
            text.textContainer?.containerSize = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)
        }
        text.textContainerInset = NSSize(width: inset, height: 76)
        text.minSize = NSSize(width: available, height: contentSize.height)
        text.setFrameSize(NSSize(width: available, height: max(text.frame.height, contentSize.height)))
        if widthChanged { onColumnWidthChange?() }
    }
}

@MainActor
final class ScreenplayTextView: NSTextView {
    struct Continuation {
        var range: NSRange
        var text: String
        var font: NSFont
    }

    weak var screenplayDocument: FountainDocument?
    var continuations: [Continuation] = []
    override var undoManager: UndoManager? { screenplayDocument?.undoManager }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let document = screenplayDocument, selectedRange().length > 0,
              (try? CharacterActionBlock.selected(in: string, range: selectedRange(),
                  screenplay: document.characterWorkspace.parsedScreenplay(for: string))) != nil else { return menu }
        menu.addItem(.separator())
        let create = menu.addItem(withTitle: L10n.string("Mark as New Character", table: "Writing"), action: #selector(markCharacter(_:)), keyEquivalent: "")
        create.target = self
        if !document.characterWorkspace.library.characters.isEmpty {
            let link = NSMenu(title: L10n.string("Link to Character", table: "Writing"))
            for character in document.characterWorkspace.library.characters {
                let item = link.addItem(withTitle: character.name, action: #selector(markCharacter(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = character.id.uuidString
            }
            let item = menu.addItem(withTitle: L10n.string("Link to Character", table: "Writing"), action: nil, keyEquivalent: "")
            item.submenu = link
        }
        return menu
    }

    @objc func markCharacter(_ sender: NSMenuItem) {
        guard let document = screenplayDocument else { return }
        let selection = selectedRange()
        if document.fileURL == nil {
            document.saveAs(nil)
            guard document.fileURL != nil else { return }
        }
        document.characterWorkspace.prepare(screenplayURL: document.fileURL, source: document.source)
        let id = (sender.representedObject as? String).flatMap(UUID.init(uuidString:))
        _ = document.characterWorkspace.mark(selection: selection, characterID: id)
        (delegate as? ScreenplayEditor.Coordinator)?.format()
        if let error = document.characterWorkspace.error {
            let alert = NSAlert(); alert.messageText = L10n.string("Unable to mark character", table: "Writing"); alert.informativeText = error; alert.runModal()
        }
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let text = insertString as? String, text == "'", !hasMarkedText() {
            super.insertText("’", replacementRange: replacementRange)
        } else {
            super.insertText(insertString, replacementRange: replacementRange)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager, textContainer != nil else { return }
        for continuation in continuations {
            guard continuation.range.length > 0, NSMaxRange(continuation.range) <= (string as NSString).length else { continue }
            let glyphs = layoutManager.glyphRange(forCharacterRange: continuation.range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
            let origin = NSPoint(x: line.maxX + textContainerOrigin.x, y: line.minY + textContainerOrigin.y)
            let attributes: [NSAttributedString.Key: Any] = [.font: continuation.font, .foregroundColor: NSColor.secondaryLabelColor]
            let bounds = NSRect(origin: origin, size: (continuation.text as NSString).size(withAttributes: attributes))
            guard bounds.intersects(dirtyRect) else { continue }
            // The reserved tail indent keeps this annotation inside the text column even for wrapped cues.
            (continuation.text as NSString).draw(at: origin, withAttributes: attributes)
        }
    }
}

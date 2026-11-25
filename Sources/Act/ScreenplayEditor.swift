import ActCore
import AppKit
import SwiftUI

struct ScreenplayEditor: NSViewRepresentable {
    @ObservedObject var document: FountainDocument
    @ObservedObject private var characters: CharacterWorkspaceModel
    @ObservedObject var zoom: ScreenplayZoom
    let sourceMode: Bool
    let selection: NSRange
    let selectionRequest: UUID
    var settings: ScreenplaySettings = .standard

    init(document: FountainDocument, sourceMode: Bool, selection: NSRange, selectionRequest: UUID, settings: ScreenplaySettings = .standard, zoom: ScreenplayZoom = ScreenplayZoom()) {
        self.document = document; self.sourceMode = sourceMode; self.selection = selection
        self.selectionRequest = selectionRequest; self.settings = settings
        characters = document.characterWorkspace
        self.zoom = zoom
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
        scroll.scrollerStyle = .overlay
        scroll.allowsMagnification = true
        scroll.minMagnification = ScreenplayZoom.minimum
        scroll.maxMagnification = ScreenplayZoom.maximum
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.backgroundColor = .textBackgroundColor
        let text = ScreenplayTextView(frame: .zero)
        characters.prepare(screenplayURL: document.fileURL, source: document.source)
        text.screenplayDocument = document
        document.screenplayEditorView = text
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
        text.textStorage?.delegate = context.coordinator
        scroll.documentView = text
        context.coordinator.textView = text
        scroll.onColumnWidthChange = { [weak coordinator = context.coordinator] in coordinator?.format() }
        context.coordinator.format()
        scroll.onZoomChange = { [weak zoom] value in zoom?.set(value) }
        scroll.setZoom(zoom.scale)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.isUpdatingView = true
        defer { coordinator.isUpdatingView = false }
        guard let text = coordinator.textView else { return }
        (scroll as? ScreenplayScrollView)?.setZoom(zoom.scale)
        var sourceChanged = false
        if !text.string.isLiterallyEqual(to: document.source) {
            coordinator.applyExternalSource(document.source)
            sourceChanged = true
        }
        if coordinator.lastSelectionRequest != selectionRequest {
            coordinator.lastSelectionRequest = selectionRequest
            if selection.location <= (text.string as NSString).length {
                text.setSelectedRange(selection)
                text.scrollRangeToVisible(selection)
                text.window?.makeFirstResponder(text)
            }
        }
        if sourceChanged || coordinator.configurationChanged { coordinator.format() }
        else if coordinator.highlightedRevision != characters.revision { coordinator.refreshHighlights() }
        text.needsDisplay = true
    }

    /// Styling is committed per line: on line breaks, when the caret leaves its line, and when the
    /// editor loses focus. Typing inside a line never restyles the script. See docs/adr/0001.
    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var parent: ScreenplayEditor
        weak var textView: NSTextView?
        var lastSelectionRequest: UUID
        private var isStyling = false
        private var isApplyingSource = false
        var isUpdatingView = false
        private var editCrossesLines = false
        private var activeLineStart: Int?
        private var styledConfiguration: Configuration?
        private var styled: [Presentation] = []
        /// Characters edited since the last commit. Elements touching it never match old presentations by position.
        private var edited: NSRange?
        private(set) var highlightedRevision: Int?

        private struct Configuration: Equatable {
            let settings: ScreenplaySettings
            let sourceMode: Bool
            let width: CGFloat
        }

        private struct Presentation: Equatable {
            let kind: FountainElement.Kind
            let text: String
            let length: Int
            let continuation: String?
            let blankLinesBefore: Int
            let collapsed: Bool
            let faded: Bool

            func isSameLine(as other: Presentation) -> Bool { kind == other.kind && length == other.length && text == other.text }
        }

        private struct Highlight: Hashable {
            let location: Int
            let length: Int
            let identity: String
        }

        init(_ parent: ScreenplayEditor) {
            self.parent = parent
            self.lastSelectionRequest = parent.selectionRequest
        }

        private var configuration: Configuration {
            Configuration(settings: parent.settings, sourceMode: parent.sourceMode,
                          width: textView?.textContainer?.containerSize.width ?? 624)
        }

        var configurationChanged: Bool { configuration != styledConfiguration }

        private var baseParagraphStyle: NSParagraphStyle {
            let base = NSMutableParagraphStyle()
            base.lineSpacing = 3
            base.paragraphSpacing = 0
            return base
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
            if replacementString?.rangeOfCharacter(from: .newlines) != nil
                || (range.length > 0 && (textView.string as NSString).rangeOfCharacter(from: .newlines, options: [], range: range).location != NSNotFound) {
                editCrossesLines = true
            }
            return true
        }

        func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            guard let previous = edited else { edited = editedRange; return }
            let replacedEnd = NSMaxRange(editedRange) - delta
            func shifted(_ location: Int) -> Int {
                location <= editedRange.location ? location : location >= replacedEnd ? location + delta : NSMaxRange(editedRange)
            }
            let start = min(shifted(previous.location), editedRange.location)
            edited = NSRange(location: start, length: max(shifted(NSMaxRange(previous)), NSMaxRange(editedRange)) - start)
        }

        func textDidChange(_ notification: Notification) {
            guard !isStyling, let textView else { return }
            parent.document.replaceSource(textView.string, deferringOutline: true)
            if editCrossesLines {
                editCrossesLines = false
                format()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isStyling, !isApplyingSource, let textView else { return }
            if lineStart(in: textView) != activeLineStart { format() } else { refreshTypingAttributes() }
        }

        func textView(_ textView: NSTextView, shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
                      toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]) -> [NSAttributedString.Key: Any] {
            Self.typingAttributes(from: newTypingAttributes)
        }

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

        /// Replaces only the differing span, so attributes outside it survive undo, redo and paper changes.
        func applyExternalSource(_ newSource: String) {
            guard let textView, let storage = textView.textStorage else { return }
            let old = storage.string as NSString, new = newSource as NSString
            let limit = min(old.length, new.length)
            var prefix = 0
            while prefix < limit, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
            var suffix = 0
            while suffix < limit - prefix, old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
            let ranges = textView.selectedRanges
            let scrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin
            // NSTextStorage can expose a live NSString proxy. Capture lengths before mutation.
            let oldLength = old.length, lengthDelta = new.length - old.length
            isApplyingSource = true
            storage.replaceCharacters(in: NSRange(location: prefix, length: old.length - prefix - suffix),
                                      with: new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix)))
            textView.selectedRanges = ranges.map { value in
                let range = value.rangeValue
                func rebased(_ position: Int) -> Int {
                    if position <= prefix { return position }
                    if position >= oldLength - suffix { return position + lengthDelta }
                    return min(position, new.length - suffix)
                }
                let start = max(0, min(rebased(range.location), new.length))
                let end = max(start, min(rebased(NSMaxRange(range)), new.length))
                return NSValue(range: NSRange(location: start, length: end - start))
            }
            if let scrollOrigin, let scroll = textView.enclosingScrollView {
                scroll.contentView.scroll(to: scrollOrigin); scroll.reflectScrolledClipView(scroll.contentView)
            }
            isApplyingSource = false
        }

        func format() {
            guard !isStyling, let textView, !textView.hasMarkedText(), let storage = textView.textStorage else { return }
            isStyling = true
            defer { isStyling = false }
            let configuration = configuration
            let font = parent.resolvedFont
            let base = baseParagraphStyle
            storage.beginEditing()
            if configuration != styledConfiguration {
                storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: base],
                                      range: NSRange(location: 0, length: storage.length))
                styled = []
                styledConfiguration = configuration
            }
            var restyled: [NSRange] = []
            if !parent.sourceMode {
                restyled = restyleChangedLines(in: textView, storage: storage, font: font, base: base, columnWidth: configuration.width)
            }
            updateCharacterHighlights(storage)
            storage.endEditing()
            edited = nil
            // Commits often run inside the text view's own edit notifications, where attribute
            // changes are not reported to the layout manager.
            if let layoutManager = textView.layoutManager {
                for range in restyled where NSMaxRange(range) <= storage.length {
                    layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
                    layoutManager.invalidateDisplay(forCharacterRange: range)
                }
            }
            activeLineStart = lineStart(in: textView)
            refreshTypingAttributes()
            textView.needsDisplay = true
            // Mid-edit commits see text the document has not received yet; the commit after it refreshes.
            guard parent.document.source.isLiterallyEqual(to: textView.string) else { return }
            if isUpdatingView {
                // SwiftUI view updates must not publish synchronously.
                DispatchQueue.main.async { [weak document = parent.document] in document?.refreshOutline() }
            } else {
                parent.document.refreshOutline()
            }
        }

        func refreshHighlights() {
            guard !isStyling, let storage = textView?.textStorage else { return }
            isStyling = true
            defer { isStyling = false }
            storage.beginEditing()
            updateCharacterHighlights(storage)
            storage.endEditing()
        }

        private func restyleChangedLines(in textView: NSTextView, storage: NSTextStorage, font: NSFont, base: NSParagraphStyle, columnWidth: CGFloat) -> [NSRange] {
            let source = textView.string
            let script = parent.characters.parsedScreenplay(for: source)
            let cursor = textView.selectedRange().location
            let cues = ScreenplayPresentation.characterCues(in: script, settings: parent.settings)
            let missingBlankLines = ScreenplayPresentation.missingBlankLinesBeforeSluglines(in: script, settings: parent.settings)
            let collapsed = surplusBlankLines(in: script)
            let desired = script.elements.enumerated().map { index, element in
                Presentation(kind: element.kind, text: element.text, length: element.range.length,
                             continuation: element.kind == .character ? continuation(for: element, cues: cues) : nil,
                             blankLinesBefore: element.kind == .sceneHeading ? missingBlankLines[element.range.location, default: 0] : 0,
                             collapsed: collapsed.contains(index), faded: !NSLocationInRange(cursor, element.range))
            }
            let ns = source as NSString
            let edited = edited ?? NSRange(location: ns.length, length: 0)
            let elements = script.elements
            var prefix = 0
            while prefix < styled.count, prefix < desired.count, NSMaxRange(ns.lineRange(for: elements[prefix].range)) <= edited.location,
                  styled[prefix].isSameLine(as: desired[prefix]) { prefix += 1 }
            var suffix = 0
            while suffix < styled.count - prefix, suffix < desired.count - prefix,
                  elements[desired.count - 1 - suffix].range.location >= NSMaxRange(edited),
                  styled[styled.count - 1 - suffix].isSameLine(as: desired[desired.count - 1 - suffix]) { suffix += 1 }
            let offset = styled.count - desired.count
            let lineHeight = (textView.layoutManager?.defaultLineHeight(for: font) ?? (font.ascender - font.descender + font.leading)) + base.lineSpacing
            var restyled: [NSRange] = []
            for (index, element) in script.elements.enumerated() {
                let unchanged = index < prefix ? styled[index] == desired[index]
                    : index >= desired.count - suffix ? styled[index + offset] == desired[index] : false
                guard !unchanged else { continue }
                let lineRange = ns.lineRange(for: element.range)
                style(element, as: desired[index], source: source, lineRange: lineRange, storage: storage,
                      font: font, base: base, columnWidth: columnWidth, lineHeight: lineHeight)
                restyled.append(lineRange)
            }
            styled = desired
            return restyled
        }

        private func continuation(for element: FountainElement, cues: [Int: String]) -> String? {
            let literalCue = FountainParser.displayText(element)
            guard let displayedCue = cues[element.range.location], displayedCue != literalCue, displayedCue.hasPrefix(literalCue) else { return nil }
            return String(displayedCue.dropFirst(literalCue.count))
        }

        private func style(_ element: FountainElement, as presentation: Presentation, source: String, lineRange: NSRange, storage: NSTextStorage,
                           font: NSFont, base: NSParagraphStyle, columnWidth: CGFloat, lineHeight: CGFloat) {
            guard NSMaxRange(lineRange) <= storage.length else { return }
            storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: base], range: lineRange)
            if presentation.collapsed {
                let collapsed = NSMutableParagraphStyle()
                collapsed.minimumLineHeight = 0.01
                collapsed.maximumLineHeight = 0.01
                storage.addAttributes([.paragraphStyle: collapsed, .font: NSFontManager.shared.convert(font, toSize: 0.01)], range: lineRange)
                return
            }
            let style = base.mutableCopy() as! NSMutableParagraphStyle
            switch element.kind {
            case .character:
                style.headIndent = min(190, columnWidth * 0.30)
                style.firstLineHeadIndent = style.headIndent
                if let suffix = presentation.continuation {
                    // Reserve room on wrapped cues; annotation remains outside the editable source.
                    style.tailIndent = -(suffix as NSString).size(withAttributes: [.font: font]).width
                    storage.addAttribute(.screenplayContinuation, value: ScreenplayContinuationLabel(text: suffix, font: font), range: element.range)
                }
            case .parenthetical: style.headIndent = min(145, columnWidth * 0.23); style.firstLineHeadIndent = style.headIndent; style.tailIndent = -min(125, columnWidth * 0.20)
            case .dialogue: style.headIndent = min(105, columnWidth * 0.17); style.firstLineHeadIndent = style.headIndent; style.tailIndent = -style.headIndent
            case .transition: style.alignment = .right
            case .centred: style.alignment = .center
            default: break
            }
            if element.kind == .sceneHeading {
                style.paragraphSpacingBefore = CGFloat(presentation.blankLinesBefore) * lineHeight
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
            let hasEmphasis = element.text.contains { $0 == "*" || $0 == "_" }
            if hasEmphasis { applyEmphasis(in: element.range, source: source, storage: storage, baseFont: font) }
            if element.kind == .titlePage, element.text.first?.isWhitespace != true {
                let colon = (element.text as NSString).range(of: ":")
                if colon.location != NSNotFound {
                    storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                                         range: NSRange(location: element.range.location, length: NSMaxRange(colon)))
                }
            }
            if presentation.faded {
                fadeMarkers(in: element, hasEmphasis: hasEmphasis, source: source, storage: storage)
            }
        }

        private func lineStart(in textView: NSTextView) -> Int {
            let text = textView.string as NSString
            return text.paragraphRange(for: NSRange(location: min(textView.selectedRange().location, text.length), length: 0)).location
        }

        /// New text takes the style of its line; an empty line starts from the base style.
        private func refreshTypingAttributes() {
            guard let textView, let storage = textView.textStorage else { return }
            let text = storage.string as NSString
            let caret = min(textView.selectedRange().location, text.length)
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: caret, length: 0))
            let reference = caret > start ? caret - 1 : contentsEnd > start ? start : nil
            let attributes = reference.map { storage.attributes(at: $0, effectiveRange: nil) }
                ?? [.font: parent.resolvedFont, .foregroundColor: NSColor.textColor, .paragraphStyle: baseParagraphStyle]
            textView.typingAttributes = Self.typingAttributes(from: attributes)
        }

        private static func typingAttributes(from attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var cleaned = attributes
            if cleaned[.characterHighlight] != nil {
                cleaned[.foregroundColor] = cleaned[.characterHighlightUnderlyingColour] ?? NSColor.textColor
            }
            for key in [NSAttributedString.Key.characterHighlight, .characterHighlightUnderlyingColour, .backgroundColor, .toolTip, .screenplayContinuation] {
                cleaned[key] = nil
            }
            return cleaned
        }

        /// Highlights live in the text storage so they move with edits made between commits.
        private func updateCharacterHighlights(_ storage: NSTextStorage) {
            highlightedRevision = parent.characters.revision
            var colours: [String: (colour: NSColor, name: String)] = [:]
            let desired = Set(parent.characters.library.characters.flatMap { character in
                character.marks.compactMap { mark -> Highlight? in
                    guard !mark.isDetached, mark.nameRange.location >= 0, mark.nameRange.length > 0,
                          NSMaxRange(mark.nameRange) <= storage.length else { return nil }
                    let identity = "\(character.colourIndex)|\(character.name)"
                    colours[identity] = (CharacterColours.colour(character.colourIndex), character.name)
                    return Highlight(location: mark.nameRange.location, length: mark.nameRange.length, identity: identity)
                }
            })
            var current = Set<Highlight>()
            storage.enumerateAttribute(.characterHighlight, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
                if let identity = value as? String { current.insert(Highlight(location: range.location, length: range.length, identity: identity)) }
            }
            guard desired != current else { return }
            for highlight in current.subtracting(desired) {
                let range = NSRange(location: highlight.location, length: highlight.length)
                var underlying: [(NSRange, NSColor?)] = []
                storage.enumerateAttribute(.characterHighlightUnderlyingColour, in: range) { value, subrange, _ in underlying.append((subrange, value as? NSColor)) }
                for (subrange, colour) in underlying {
                    if let colour { storage.addAttribute(.foregroundColor, value: colour, range: subrange) }
                    else { storage.removeAttribute(.foregroundColor, range: subrange) }
                }
                for key in [NSAttributedString.Key.characterHighlight, .characterHighlightUnderlyingColour, .backgroundColor, .toolTip] {
                    storage.removeAttribute(key, range: range)
                }
            }
            for highlight in desired.subtracting(current) {
                guard let style = colours[highlight.identity] else { continue }
                let range = NSRange(location: highlight.location, length: highlight.length)
                var underlying: [(NSRange, NSColor)] = []
                storage.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
                    if let colour = value as? NSColor { underlying.append((subrange, colour)) }
                }
                for (subrange, colour) in underlying { storage.addAttribute(.characterHighlightUnderlyingColour, value: colour, range: subrange) }
                storage.addAttributes([.backgroundColor: style.colour.withAlphaComponent(0.18), .foregroundColor: style.colour,
                                       .toolTip: L10n.format("Character: %@", style.name, table: "Writing"),
                                       .characterHighlight: highlight.identity], range: range)
            }
        }

        /// Screenplay spacing changes the presentation, never the line endings in Fountain source.
        private func surplusBlankLines(in script: FountainScreenplay) -> Set<Int> {
            let target = max(1, min(parent.settings.blankLinesBeforeSlugline, 2))
            var collapsed = Set<Int>()
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
                    collapsed.formUnion(blankIndices.dropFirst(target))
                }
                if ![.blank, .titlePage, .note, .boneyard, .section, .synopsis].contains(element.kind) { hasBody = true }
            }
            return collapsed
        }

        private static let emphasis = try! NSRegularExpression(pattern: #"(?<!\\)(\*{1,3}|_)(?=\S)(.+?\S|\S)\1"#)
        private static let controls = try! NSRegularExpression(pattern: #"(?m)^(?:[.@!~>#]+|={3,})|(?<!\\)\[\[|(?<!\\)\]\]|\s#[^#\r\n]+#\s*$|\^$"#)

        private func applyEmphasis(in range: NSRange, source: String, storage: NSTextStorage, baseFont: NSFont) {
            for match in Self.emphasis.matches(in: source, range: range) {
                let marker = (source as NSString).substring(with: match.range(at: 1))
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

        private func fadeMarkers(in element: FountainElement, hasEmphasis: Bool, source: String, storage: NSTextStorage) {
            if element.text.first.map(".@!~>#=".contains) == true || element.text.contains(where: "[]#^".contains) {
                for match in Self.controls.matches(in: source, range: element.range) {
                    storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: match.range)
                }
            }
            guard hasEmphasis else { return }
            for match in Self.emphasis.matches(in: source, range: element.range) {
                let marker = match.range(at: 1)
                storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: marker)
                storage.addAttribute(.foregroundColor, value: NSColor.quaternaryLabelColor, range: NSRange(location: NSMaxRange(match.range) - marker.length, length: marker.length))
            }
        }
    }
}

@MainActor
final class ScreenplayScrollView: NSScrollView {
    var onColumnWidthChange: (() -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?

    func setZoom(_ scale: CGFloat, around point: NSPoint? = nil) {
        guard scale.isFinite else { return }
        let bounded = min(maxMagnification, max(minMagnification, scale))
        guard abs(magnification - bounded) > 0.000001 else { return }
        let anchor = point ?? NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        setMagnification(bounded, centeredAt: anchor)
        hasHorizontalScroller = bounded > 1
        onZoomChange?(magnification)
    }

    override func magnify(with event: NSEvent) {
        guard event.phase != .cancelled, event.magnification.isFinite else { return }
        let point = contentView.convert(event.locationInWindow, from: nil)
        setZoom(magnification * max(0.01, 1 + event.magnification), around: point)
    }

    override func layout() {
        super.layout()
        guard let text = documentView as? NSTextView else { return }
        // The clip view's bounds shrink during magnification. Its frame remains the
        // unscaled viewport, so zoom never becomes a screenplay column-width change.
        let available = contentView.frame.width
        let column = min(624, max(220, available - 112))
        let inset = max(32, (available - column) / 2)
        let widthChanged = text.textContainer?.containerSize.width != column
        if widthChanged {
            text.textContainer?.containerSize = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)
        }
        text.textContainerInset = NSSize(width: inset, height: 76)
        text.minSize = NSSize(width: available, height: contentView.bounds.height)
        text.setFrameSize(NSSize(width: available, height: max(text.frame.height, contentView.bounds.height)))
        if widthChanged { onColumnWidthChange?() }
    }
}

extension NSAttributedString.Key {
    static let characterHighlight = Self("ActCharacterHighlight")
    static let characterHighlightUnderlyingColour = Self("ActCharacterHighlightUnderlyingColour")
    static let screenplayContinuation = Self("ActScreenplayContinuation")
}

final class ScreenplayContinuationLabel: NSObject {
    let text: String
    let font: NSFont
    init(text: String, font: NSFont) { self.text = text; self.font = font }
}

@MainActor
final class ScreenplayTextView: NSTextView {
    override func magnify(with event: NSEvent) {
        enclosingScrollView?.magnify(with: event)
    }
    struct Continuation {
        var range: NSRange
        var text: String
        var font: NSFont
    }

    weak var screenplayDocument: FountainDocument?
    private var reviewButtons: [UUID: NSButton] = [:]
    private(set) var reviewPopover: NSPopover?

    override func accessibilityChildren() -> [Any]? {
        (super.accessibilityChildren() ?? []) + reviewButtons.values.sorted { $0.frame.minY < $1.frame.minY }
    }

    override func layout() {
        super.layout()
        updateReviewButtons()
    }

    private func updateReviewButtons() {
        guard let layoutManager, textContainer != nil else { return }
        let changes = screenplayDocument?.aiReview.changes.filter { !$0.dismissed && !$0.conflicted && !$0.reverted } ?? []
        let active = Set(changes.map(\.id))
        for id in Array(reviewButtons.keys) where !active.contains(id) {
            reviewButtons.removeValue(forKey: id)?.removeFromSuperview()
        }
        let length = (string as NSString).length
        var markersPerLine: [CGFloat: Int] = [:]
        for change in changes {
            guard change.location >= 0, NSMaxRange(change.range) <= length else { continue }
            let button = reviewButtons[change.id] ?? NSButton(title: "", target: self, action: #selector(reviewMarkerClicked(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(change.id.uuidString)
            button.title = change.kind == "move" ? "↔" : change.after.isEmpty ? "−" : "+"
            button.isBordered = false
            button.font = .monospacedSystemFont(ofSize: 13, weight: .bold)
            button.contentTintColor = change.kind == "move" ? .systemBlue : change.after.isEmpty ? .systemOrange : .systemGreen
            button.setAccessibilityLabel(automationText("AI changes") + " " + button.title)
            button.toolTip = automationText("AI changes")
            var line = NSRect(x: 0, y: 0, width: 0, height: 20)
            if length > 0 {
                let glyph = layoutManager.glyphIndexForCharacter(at: min(change.location, length - 1))
                line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            }
            let offset = markersPerLine[line.minY, default: 0]
            markersPerLine[line.minY] = offset + 1
            button.frame = NSRect(x: max(0, textContainerOrigin.x + line.minX - 30 - CGFloat(offset * 26)), y: textContainerOrigin.y + line.minY - 3, width: 26, height: max(22, line.height + 6))
            if button.superview == nil { addSubview(button); reviewButtons[change.id] = button }
        }
    }

    @objc private func reviewMarkerClicked(_ sender: NSButton) {
        guard let document = screenplayDocument,
              let change = document.aiReview.changes.first(where: { $0.id.uuidString == sender.identifier?.rawValue }),
              !change.dismissed, !change.conflicted, !change.reverted else { return }
        reviewPopover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: AIInlineReviewPopover(document: document, operationID: change.operationID) { [weak self] in
            self?.reviewPopover?.close()
            self?.needsDisplay = true
        })
        reviewPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxX)
    }

    private var keyObserver: NSObjectProtocol?
    override var undoManager: UndoManager? { screenplayDocument?.undoManager }

    var continuations: [Continuation] { continuations(in: NSRange(location: 0, length: (string as NSString).length)) }

    private func continuations(in range: NSRange) -> [Continuation] {
        var found: [Continuation] = []
        textStorage?.enumerateAttribute(.screenplayContinuation, in: range) { value, range, _ in
            if let label = value as? ScreenplayContinuationLabel { found.append(.init(range: range, text: label.text, font: label.font)) }
        }
        return found
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { (delegate as? ScreenplayEditor.Coordinator)?.format() }
        return resigned
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { (self?.delegate as? ScreenplayEditor.Coordinator)?.format() }
            }
        }
    }

    /// The selected name when it can be marked, with the existing character Command-M would link it to.
    private func markableSelection() -> (name: String, match: CharacterReference?)? {
        guard let document = screenplayDocument, selectedRange().length > 0,
              let block = try? CharacterActionBlock.selected(in: string, range: selectedRange(),
                  screenplay: document.characterWorkspace.parsedScreenplay(for: string)) else { return nil }
        let match = document.characterWorkspace.library.characters.first { $0.name.caseInsensitiveCompare(block.name) == .orderedSame }
        return (block.name, match)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "m",
           window?.firstResponder === self, !hasMarkedText(), let markable = markableSelection() {
            markSelection(characterID: markable.match?.id)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let document = screenplayDocument, let markable = markableSelection() else { return menu }
        menu.addItem(.separator())
        let create = menu.addItem(withTitle: L10n.string("Mark as New Character", table: "Writing"), action: #selector(markCharacter(_:)),
                                  keyEquivalent: markable.match == nil ? "m" : "")
        create.target = self
        if !document.characterWorkspace.library.characters.isEmpty {
            let link = NSMenu(title: L10n.string("Link to Character", table: "Writing"))
            for character in document.characterWorkspace.library.characters {
                let item = link.addItem(withTitle: character.name, action: #selector(markCharacter(_:)),
                                        keyEquivalent: character.id == markable.match?.id ? "m" : "")
                item.target = self; item.representedObject = character.id.uuidString
            }
            let item = menu.addItem(withTitle: L10n.string("Link to Character", table: "Writing"), action: nil, keyEquivalent: "")
            item.submenu = link
        }
        return menu
    }

    @objc func markCharacter(_ sender: NSMenuItem) {
        markSelection(characterID: (sender.representedObject as? String).flatMap(UUID.init(uuidString:)))
    }

    private func markSelection(characterID id: UUID?) {
        guard let document = screenplayDocument else { return }
        let selection = selectedRange()
        if document.fileURL == nil {
            document.saveAs(nil)
            guard document.fileURL != nil else { return }
        }
        document.characterWorkspace.prepare(screenplayURL: document.fileURL, source: document.source)
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
        NSGraphicsContext.saveGraphicsState()
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
        if string.isEmpty {
            ("INT." as NSString).draw(at: textContainerOrigin, withAttributes: [
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: NSColor.quaternaryLabelColor
            ])
        }
        guard let layoutManager, let textContainer else { return }
        updateReviewButtons()
        if let document = screenplayDocument {
            for change in document.aiReview.changes where !change.dismissed && !change.conflicted && !change.reverted {
                let length = (string as NSString).length
                guard length > 0, change.location >= 0, NSMaxRange(change.range) <= length else { continue }
                let range = change.range.length == 0 ? NSRange(location: min(change.location, length - 1), length: 1) : change.range
                let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let colour: NSColor = change.kind == "move" ? .systemBlue : change.after.isEmpty ? .systemOrange : .systemGreen
                if !change.after.isEmpty {
                    layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                        let rect = rect.offsetBy(dx: self.textContainerOrigin.x, dy: self.textContainerOrigin.y)
                        if rect.intersects(dirtyRect) { colour.withAlphaComponent(0.10).setFill(); NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill() }
                    }
                }

            }
        }
        let visible = layoutManager.glyphRange(forBoundingRect: dirtyRect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y), in: textContainer)
        for continuation in continuations(in: layoutManager.characterRange(forGlyphRange: visible, actualGlyphRange: nil)) {
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

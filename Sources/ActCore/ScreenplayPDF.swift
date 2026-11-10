import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum ScreenplayPDFError: LocalizedError {
    case cannotCreatePDF
    public var errorDescription: String? { "Act could not create the screenplay PDF." }
}

public struct ScreenplayPDFLine: Sendable {
    public let text: String
    public let x: CGFloat
    /// Distance from the top edge of the page to the text baseline.
    public let baseline: CGFloat
    public let bold: Bool
}

public struct ScreenplayPDFPage: Sendable {
    public let lines: [ScreenplayPDFLine]
    public let isTitlePage: Bool
}

public enum ScreenplayPDF {
    public static let pageSize = CGSize(width: 612, height: 792)
    private static let top: CGFloat = 72

    @MainActor
    public static func export(source: String, to url: URL, settings: ScreenplaySettings = .standard) throws {
        try data(source: source, settings: settings).write(to: url, options: .atomic)
    }

    @MainActor
    public static func data(source: String, settings: ScreenplaySettings = .standard) throws -> Data {
        let settings = settings.validated
        let output = NSMutableData()
        let size = ScreenplayPaper.read(from: source).size
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ScreenplayPDFError.cannotCreatePDF
        }
        var bodyPage = 0
        for page in layout(source: source, settings: settings) {
            context.beginPDFPage(nil)
            if !page.isTitlePage {
                bodyPage += 1
                if bodyPage > 1 {
                    draw("\(bodyPage).", x: size.width - 72 - textWidth("\(bodyPage).", bold: false, settings: settings),
                         baseline: 36, bold: false, settings: settings, pageHeight: size.height, in: context)
                }
            }
            for line in page.lines {
                draw(line.text, x: line.x, baseline: line.baseline, bold: line.bold, settings: settings, pageHeight: size.height, in: context)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return output as Data
    }

    @MainActor
    public static func layout(source: String, settings: ScreenplaySettings = .standard) -> [ScreenplayPDFPage] {
        let settings = settings.validated
        let screenplay = FountainParser.parse(source)
        let size = ScreenplayPaper.read(from: source).size
        let bottom = size.height - 72
        let right = size.width - 72
        let bodyWidth = right - 108
        let fontSize = settings.fontSize
        let lineHeight = CGFloat(max(12, fontSize))
        let characterCues = ScreenplayPresentation.characterCues(in: screenplay, settings: settings)
        func presentationText(_ element: FountainElement) -> String {
            visibleText(characterCues[element.range.location] ?? FountainParser.displayText(element))
        }
        var pages: [ScreenplayPDFPage] = []
        let fields = FountainTitleField.read(from: source).filter { $0.key != "paper" && !$0.value.isEmpty }
        if !fields.isEmpty {
            var titleLines: [ScreenplayPDFLine] = []
            var y: CGFloat = size.height / 3
            let footerKeys = ["contact", "copyright", "draft date", "notes"]
            // Field order in the source does not alter conventional title-page placement.
            let order = ["title", "credit", "author", "authors", "source"]
            let centred = order.flatMap { key in fields.filter { $0.key == key } }
            let footer = fields.filter { footerKeys.contains($0.key) }
            func rows(_ field: FountainTitleField) -> [String] {
                field.value.components(separatedBy: "\n").flatMap {
                    let text = visibleText($0)
                    return text.isEmpty ? [""] : wrapped(text, width: bodyWidth, bold: field.key == "title", settings: settings)
                }
            }
            func append(_ field: FountainTitleField, centred: Bool) {
                for text in rows(field) {
                    if y > bottom {
                        pages.append(ScreenplayPDFPage(lines: titleLines, isTitlePage: true))
                        titleLines = []
                        y = top
                    }
                    let width = textWidth(text, bold: field.key == "title", settings: settings)
                    titleLines.append(ScreenplayPDFLine(text: text, x: centred ? max(0, (size.width - width) / 2) : 108,
                                                       baseline: y, bold: field.key == "title"))
                    y += lineHeight
                }
                y += lineHeight
            }
            for field in centred { append(field, centred: true) }
            if !footer.isEmpty {
                let footerRows = footer.reduce(0) { $0 + rows($1).count } + footer.count - 1
                y = max(y, bottom - CGFloat(footerRows - 1) * lineHeight)
                for field in footer { append(field, centred: false) }
            }
            if !titleLines.isEmpty { pages.append(ScreenplayPDFPage(lines: titleLines, isTitlePage: true)) }
        }
        var lines: [ScreenplayPDFLine] = []
        var y = top
        func finishPage() {
            pages.append(ScreenplayPDFPage(lines: lines, isTitlePage: false))
            lines = []
            y = top
        }
        let printable = screenplay.elements.filter {
            ![.titlePage, .note, .boneyard, .section, .synopsis].contains($0.kind)
        }
        var consumed: Set<Int> = []
        for (index, element) in printable.enumerated() {
            if consumed.contains(index) { continue }
            if element.kind == .character, !element.isDualDialogue {
                var leftEnd = index + 1
                while leftEnd < printable.count && [.dialogue, .parenthetical].contains(printable[leftEnd].kind) { leftEnd += 1 }
                var rightStart = leftEnd
                while rightStart < printable.count && printable[rightStart].kind == .blank { rightStart += 1 }
                if rightStart < printable.count, printable[rightStart].kind == .character, printable[rightStart].isDualDialogue {
                    var rightEnd = rightStart + 1
                    while rightEnd < printable.count && [.dialogue, .parenthetical].contains(printable[rightEnd].kind) { rightEnd += 1 }
                    func column(_ range: Range<Int>, x: CGFloat) -> [(String, CGFloat)] {
                        range.flatMap { i -> [(String, CGFloat)] in
                            let item = printable[i]
                            let inset: CGFloat = item.kind == .character ? 36 : item.kind == .parenthetical ? 18 : 0
                            return wrapped(presentationText(item), width: 180 - inset, bold: false, settings: settings).map { ($0, x + inset) }
                        }
                    }
                    let left = column(index..<leftEnd, x: 108)
                    let rightColumn = column(rightStart..<rightEnd, x: size.width - 288)
                    let count = max(left.count, rightColumn.count)
                    let cueRows = max(wrapped(presentationText(element), width: 144, bold: false, settings: settings).count,
                                      wrapped(presentationText(printable[rightStart]), width: 144, bold: false, settings: settings).count)
                    if y + CGFloat(min(count, max(4, cueRows + 2)) - 1) * lineHeight > bottom, !lines.isEmpty { finishPage() }
                    var row = 0
                    while row < count {
                        let available = max(0, Int(floor((bottom - y) / lineHeight)) + 1)
                        if available == 0 || (settings.dialogueContinuations && available < 2 && count - row > available) { finishPage(); continue }
                        let splitting = count - row > available
                        let countHere = min(count - row, max(1, available - (splitting && settings.dialogueContinuations ? 1 : 0)))
                        for _ in 0..<countHere {
                            for values in [left, rightColumn] where row < values.count {
                                lines.append(ScreenplayPDFLine(text: values[row].0, x: values[row].1, baseline: y, bold: false))
                            }
                            row += 1
                            y += lineHeight
                        }
                        if row < count {
                            if settings.dialogueContinuations {
                                if row < left.count { lines.append(ScreenplayPDFLine(text: "(MORE)", x: 144, baseline: min(y, bottom), bold: false)) }
                                if row < rightColumn.count { lines.append(ScreenplayPDFLine(text: "(MORE)", x: size.width - 252, baseline: min(y, bottom), bold: false)) }
                            }
                            finishPage()
                            if settings.dialogueContinuations {
                                var cueHeight = 0
                                for (start, values, x) in [(index, left, CGFloat(144)), (rightStart, rightColumn, size.width - 252)] where row < values.count {
                                    let cueLines = wrapped(ScreenplayPresentation.continuationCue(presentationText(printable[start])), width: 144, bold: false, settings: settings)
                                    for (offset, text) in cueLines.enumerated() {
                                        lines.append(ScreenplayPDFLine(text: text, x: x, baseline: y + CGFloat(offset) * lineHeight, bold: false))
                                    }
                                    cueHeight = max(cueHeight, cueLines.count)
                                }
                                y += CGFloat(cueHeight) * lineHeight
                            }
                        }
                    }
                    consumed.formUnion(index..<rightEnd)
                    continue
                }
            }
            if element.kind == .character {
                var end = index + 1
                while end < printable.count && [.dialogue, .parenthetical].contains(printable[end].kind) { end += 1 }
                if end > index + 1 {
                    let cue = presentationText(element)
                    var rows: [(String, CGFloat)] = []
                    for item in printable[index..<end] {
                        let x: CGFloat = item.kind == .character ? 252 : item.kind == .parenthetical ? 216 : 180
                        let width: CGFloat = item.kind == .parenthetical ? 180 : 252
                        rows += wrapped(presentationText(item), width: width, bold: false, settings: settings).map { ($0, x) }
                    }
                    let cueRows = wrapped(cue, width: 252, bold: false, settings: settings).count
                    if y + CGFloat(min(rows.count, max(4, cueRows + 2)) - 1) * lineHeight > bottom, !lines.isEmpty { finishPage() }
                    var row = 0
                    while row < rows.count {
                        let available = max(0, Int(floor((bottom - y) / lineHeight)) + 1)
                        if available == 0 || (settings.dialogueContinuations && available < 2 && rows.count - row > available) { finishPage(); continue }
                        let splitting = rows.count - row > available
                        let count = min(rows.count - row, max(1, available - (splitting && settings.dialogueContinuations ? 1 : 0)))
                        for _ in 0..<count {
                            lines.append(ScreenplayPDFLine(text: rows[row].0, x: rows[row].1, baseline: y, bold: false))
                            row += 1
                            y += lineHeight
                        }
                        if row < rows.count {
                            if settings.dialogueContinuations {
                                lines.append(ScreenplayPDFLine(text: "(MORE)", x: 252, baseline: min(y, bottom), bold: false))
                            }
                            finishPage()
                            if settings.dialogueContinuations {
                                for text in wrapped(ScreenplayPresentation.continuationCue(cue), width: 252, bold: false, settings: settings) {
                                    lines.append(ScreenplayPDFLine(text: text, x: 252, baseline: y, bold: false))
                                    y += lineHeight
                                }
                            }
                        }
                    }
                    consumed.formUnion(index..<end)
                    continue
                }
            }
            if element.kind == .pageBreak {
                if !lines.isEmpty { finishPage() }
                continue
            }
            if element.kind == .blank {
                if !lines.isEmpty { y += lineHeight }
                continue
            }
            if element.kind == .sceneHeading, let previous = lines.last {
                y = previous.baseline + CGFloat(settings.blankLinesBeforeSlugline + 1) * lineHeight
            }
            let bold = element.kind == .sceneHeading && settings.boldSluglines
            let x: CGFloat
            let width: CGFloat
            switch element.kind {
            case .character: x = 252; width = 252
            case .dialogue: x = 180; width = 252
            case .parenthetical: x = 216; width = 180
            default: x = 108; width = bodyWidth
            }
            let visible = presentationText(element)
            guard !visible.isEmpty else { continue }
            let wrappedLines = wrapped(visible, width: width, bold: bold, settings: settings)
            var reserve = wrappedLines.count
            if element.kind == .character || element.kind == .sceneHeading {
                // Keep a cue or heading with the start of the next printable element.
                let following = printable.dropFirst(index + 1).first { $0.kind != .blank }
                if let following, following.kind != .pageBreak { reserve += following.kind == .parenthetical ? 3 : 2 }
            }
            if y + CGFloat(min(reserve, 6) - 1) * lineHeight > bottom, !lines.isEmpty { finishPage() }
            for text in wrappedLines {
                if y > bottom { finishPage() }
                let lineX: CGFloat
                if element.kind == .transition {
                    lineX = max(108, right - textWidth(text, bold: bold, settings: settings))
                } else if element.kind == .centred {
                    lineX = max(108, (size.width - textWidth(text, bold: bold, settings: settings)) / 2)
                } else { lineX = x }
                lines.append(ScreenplayPDFLine(text: text, x: lineX, baseline: y, bold: bold))
                y += lineHeight
            }
        }
        if !lines.isEmpty || pages.isEmpty { finishPage() }
        return pages
    }

    @MainActor
    private static func attributed(_ text: String, bold: Bool, settings: ScreenplaySettings) -> NSAttributedString {
        let settings = settings.validated
        let size = settings.fontSize
        let base = NSFont(name: settings.fontName, size: size)
            ?? NSFontManager.shared.font(withFamily: settings.fontName, traits: [], weight: 5, size: size)
            ?? NSFont(name: "Courier", size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let font = NSFontManager.shared.convert(base, toHaveTrait: bold ? .boldFontMask : .unboldFontMask)
        return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
    }

    @MainActor
    private static func textWidth(_ text: String, bold: Bool, settings: ScreenplaySettings) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed(text, bold: bold, settings: settings)), nil, nil, nil))
    }

    @MainActor
    private static func wrapped(_ text: String, width: CGFloat, bold: Bool, settings: ScreenplaySettings) -> [String] {
        let value = attributed(text, bold: bold, settings: settings)
        let typesetter = CTTypesetterCreateWithAttributedString(value)
        let ns = text as NSString
        var offset = 0
        var result: [String] = []
        while offset < ns.length {
            var length = CTTypesetterSuggestLineBreak(typesetter, offset, Double(width))
            if length == 0 { length = ns.rangeOfComposedCharacterSequence(at: offset).length }
            result.append(ns.substring(with: NSRange(location: offset, length: length)).trimmingCharacters(in: .whitespaces))
            offset += length
        }
        return result
    }

    private static func visibleText(_ text: String) -> String {
        var value = text.replacingOccurrences(of: "\\[\\[.*?\\]\\]", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+#[^#]+#\\s*$", with: "", options: .regularExpression)
        // Fountain emphasis marks are presentation syntax. Escaped punctuation remains literal.
        for _ in 0..<3 {
            value = value.replacingOccurrences(of: "(?<!\\\\)(\\*{1,3}|_)(?=\\S)(.+?\\S|\\S)\\1", with: "$2", options: .regularExpression)
        }
        value = value.replacingOccurrences(of: "\\\\([*_\\\\])", with: "$1", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespaces)
    }

    @MainActor
    private static func draw(_ text: String, x: CGFloat, baseline: CGFloat, bold: Bool, settings: ScreenplaySettings, pageHeight: CGFloat, in context: CGContext) {
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: pageHeight - baseline)
        CTLineDraw(CTLineCreateWithAttributedString(attributed(text, bold: bold, settings: settings)), context)
    }
}

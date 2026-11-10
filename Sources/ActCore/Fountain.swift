import Foundation

public struct FountainElement: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case titlePage, sceneHeading, action, character, dialogue, parenthetical
        case transition, centred, section, synopsis, note, boneyard, pageBreak, blank
    }
    public let kind: Kind
    public let text: String
    /// Range in the unmodified source, excluding the line terminator.
    public let range: NSRange
    public let isDualDialogue: Bool
    /// Comment-free presentation for this line, resolved with document-wide comment state.
    public let presentationText: String?

    public init(kind: Kind, text: String, range: NSRange, isDualDialogue: Bool = false, presentationText: String? = nil) {
        self.kind = kind
        self.text = text
        self.range = range
        self.isDualDialogue = isDualDialogue
        self.presentationText = presentationText
    }
}

public struct FountainScene: Identifiable, Equatable, Sendable {
    public let id: String
    public let heading: String
    /// Complete raw scene source, including its heading and line terminators.
    public let text: String
    public let range: NSRange
}

public struct FountainScreenplay: Equatable, Sendable {
    public let source: String
    public let elements: [FountainElement]
    public let scenes: [FountainScene]
}

public enum FountainParser {
    public static func parse(_ source: String) -> FountainScreenplay {
        let ns = source as NSString
        var lines: [(String, NSRange)] = []
        var position = 0
        while position < ns.length {
            var start = 0, end = 0, contentsEnd = 0
            ns.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: position, length: 0))
            let range = NSRange(location: start, length: contentsEnd - start)
            lines.append((ns.substring(with: range), range))
            position = end
        }
        var commentState: FountainElement.Kind?
        let presentation = lines.map { stripComments($0.0, state: &commentState) }
        var elements: [FountainElement] = []
        var dialogue = false, titlePage = false
        var bodyStarted = false
        for (index, line) in lines.enumerated() {
            let (raw, range) = line
            let visible = presentation[index].text
            let value = visible.trimmingCharacters(in: .whitespaces)
            let previousBlank = index == 0 || presentation[index - 1].text.trimmingCharacters(in: .whitespaces).isEmpty
            let next = index + 1 < lines.count ? presentation[index + 1].text.trimmingCharacters(in: .whitespaces) : ""
            let kind: FountainElement.Kind
            if value.isEmpty, let hiddenKind = presentation[index].hiddenKind {
                kind = hiddenKind
            } else if value.isEmpty {
                kind = .blank
                dialogue = false
                titlePage = false
            } else if !bodyStarted && (isTitleField(value) || (titlePage && visible.first?.isWhitespace == true)) {
                kind = .titlePage
                titlePage = true
            } else {
                bodyStarted = true
                titlePage = false
                if previousBlank && isSceneHeading(value) {
                    kind = .sceneHeading; dialogue = false
                } else if value.hasPrefix("===") {
                    kind = .pageBreak; dialogue = false
                } else if value.hasPrefix("#") {
                    kind = .section; dialogue = false
                } else if value.hasPrefix("=") {
                    kind = .synopsis; dialogue = false
                } else if value.hasPrefix(">") && value.hasSuffix("<") {
                    kind = .centred; dialogue = false
                } else if value.hasPrefix(">") || (previousBlank && value == value.uppercased() && value.hasSuffix("TO:")) {
                    kind = .transition; dialogue = false
                } else if value.hasPrefix("!") {
                    kind = .action; dialogue = false
                } else if value.hasPrefix("@") || (previousBlank && isCharacter(value) && !next.isEmpty) {
                    kind = .character; dialogue = true
                } else if dialogue && value.hasPrefix("(") {
                    kind = .parenthetical
                } else if dialogue {
                    kind = .dialogue
                } else {
                    kind = .action
                }
            }
            elements.append(FountainElement(kind: kind, text: raw, range: range,
                                            isDualDialogue: kind == .character && value.hasSuffix("^"),
                                            presentationText: visible))
        }
        let headings = elements.filter { $0.kind == .sceneHeading }
        var occurrences: [String: Int] = [:]
        let scenes = headings.enumerated().map { index, element in
            let heading = displayText(element)
            let normalised = heading.uppercased().trimmingCharacters(in: .whitespaces)
            let identity = sceneNumber(heading).map { "number:\($0)" } ?? "heading:\(normalised)"
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            let key = "\(identity):\(occurrence)"
            let end = index + 1 < headings.count ? headings[index + 1].range.location : ns.length
            let range = NSRange(location: element.range.location, length: end - element.range.location)
            return FountainScene(id: stableHash(key), heading: heading, text: ns.substring(with: range), range: range)
        }
        return FountainScreenplay(source: source, elements: elements, scenes: scenes)
    }

    /// Presentation text only. Never use this value to overwrite the source file.
    public static func displayText(_ element: FountainElement) -> String {
        if element.kind == .note || element.kind == .boneyard { return "" }
        var commentState: FountainElement.Kind?
        var text = (element.presentationText ?? stripComments(element.text, state: &commentState).text).trimmingCharacters(in: .whitespaces)
        switch element.kind {
        case .sceneHeading:
            if text.hasPrefix(".") { text.removeFirst() }
        case .character:
            if text.hasPrefix("@") { text.removeFirst() }
            if text.hasSuffix("^") { text.removeLast() }
        case .action:
            if text.hasPrefix("!") { text.removeFirst() }
        case .transition:
            if text.hasPrefix(">") { text.removeFirst() }
        case .centred:
            if text.hasPrefix(">") { text.removeFirst() }
            if text.hasSuffix("<") { text.removeLast() }
        default: break
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Delimiters are scanned before element classification, including comments starting mid-line.
    /// Source text and ranges remain untouched, even for unclosed comments.
    private static func stripComments(_ raw: String, state: inout FountainElement.Kind?) -> (text: String, hiddenKind: FountainElement.Kind?) {
        var visible = ""
        var hiddenKind = state
        var index = raw.startIndex
        while index < raw.endIndex {
            let remainder = raw[index...]
            if let active = state {
                let closing = active == .boneyard ? "*/" : "]]"
                if remainder.hasPrefix(closing) {
                    index = raw.index(index, offsetBy: 2)
                    state = nil
                } else {
                    index = raw.index(after: index)
                }
            } else {
                let escaped = index > raw.startIndex && raw[raw.index(before: index)] == "\\"
                if !escaped && (remainder.hasPrefix("/*") || remainder.hasPrefix("[[")) {
                    let opening: FountainElement.Kind = remainder.hasPrefix("/*") ? .boneyard : .note
                    state = opening
                    if hiddenKind == nil { hiddenKind = opening }
                    index = raw.index(index, offsetBy: 2)
                } else {
                    visible.append(raw[index])
                    index = raw.index(after: index)
                }
            }
        }
        return (visible, hiddenKind)
    }

    private static func isSceneHeading(_ text: String) -> Bool {
        if text.hasPrefix("."), text.count > 1,
           text.dropFirst().unicodeScalars.first.map(CharacterSet.alphanumerics.contains) == true { return true }
        let upper = text.uppercased()
        return ["INT", "EXT", "EST", "INT./EXT", "INT/EXT", "I/E"].contains {
            upper.hasPrefix($0 + ".") || upper.hasPrefix($0 + " ")
        }
    }

    private static func isCharacter(_ text: String) -> Bool {
        let cue = text.hasSuffix("^") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text
        let name = cue.split(separator: "(", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? cue
        return cue.count <= 80 && name == name.uppercased() && name.unicodeScalars.contains(where: CharacterSet.letters.contains)
            && !cue.hasSuffix(":") && !cue.hasPrefix("\\")
    }

    private static func isTitleField(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":") else { return false }
        let key = text[..<colon].lowercased()
        return ["title", "credit", "author", "authors", "source", "draft date", "contact", "copyright", "notes", "paper"].contains(key)
    }

    private static func sceneNumber(_ heading: String) -> String? {
        guard heading.hasSuffix("#"), let start = heading.dropLast().lastIndex(of: "#") else { return nil }
        return String(heading[heading.index(after: start)..<heading.index(before: heading.endIndex)])
    }

    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }
}

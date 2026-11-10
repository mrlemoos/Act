import Foundation

public enum CharacterSheetError: LocalizedError, Sendable {
    case invalidSelection, staleMark, invalidExtraction, invalidLibrary, externalChange, missingImage
    case operation(String)
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: "Select a character name inside an action paragraph. Dialogue, comments and scene headings cannot be marked."
        case .staleMark: "This character mark no longer matches an action paragraph. Mark the name again to relink it."
        case .invalidExtraction: "MLX returned invalid or unsupported physical details. Existing details and your prompt are preserved."
        case .invalidLibrary: "This character library has an unsupported version or invalid references."
        case .externalChange: "The character library changed outside Act. Reopen the screenplay before editing it further."
        case .missingImage: "The agent returned no new, valid image. Check its image tools and permissions, then retry."
        case .operation(let reason): reason
        }
    }
}

public struct CharacterActionBlock: Equatable, Sendable {
    public var name: String
    public var nameRange: NSRange
    public var range: NSRange
    public var text: String

    public static func selected(in source: String, range: NSRange) throws -> Self {
        let raw = source as NSString
        guard range.location >= 0, range.length > 0, range.length <= 100,
              range.location <= raw.length, range.length <= raw.length - range.location else { throw CharacterSheetError.invalidSelection }
        let name = raw.substring(with: range)
        guard name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              name.unicodeScalars.contains(where: CharacterSet.letters.contains),
              !name.contains(where: \.isNewline) else { throw CharacterSheetError.invalidSelection }
        let elements = FountainParser.parse(source).elements
        guard let index = elements.firstIndex(where: { $0.kind == .action && NSIntersectionRange($0.range, range) == range }) else {
            throw CharacterSheetError.invalidSelection
        }
        // Do not allow a selection inside a hidden note in an otherwise visible action line.
        guard isVisible(range, in: source) else { throw CharacterSheetError.invalidSelection }
        var first = index, last = index
        while first > 0 && elements[first - 1].kind == .action { first -= 1 }
        while last + 1 < elements.count && elements[last + 1].kind == .action { last += 1 }
        let blockRange = NSRange(location: elements[first].range.location,
                                 length: NSMaxRange(elements[last].range) - elements[first].range.location)
        let text = elements[first...last].map(FountainParser.displayText).joined(separator: "\n")
        return Self(name: name, nameRange: range, range: blockRange, text: text)
    }

    private static func isVisible(_ selection: NSRange, in source: String) -> Bool {
        let units = Array(source.utf16)
        var closing: (UInt16, UInt16)?
        var index = 0
        while index < NSMaxRange(selection) {
            let pair = index + 1 < units.count ? (units[index], units[index + 1]) : (units[index], UInt16(0))
            if let end = closing {
                if index >= selection.location { return false }
                if pair == end { closing = nil; index += 2 } else { index += 1 }
            } else if (index == 0 || units[index - 1] != 92) && (pair == (91, 91) || pair == (47, 42)) {
                if index + 1 >= selection.location { return false }
                closing = pair == (91, 91) ? (93, 93) : (42, 47)
                index += 2
            } else { index += 1 }
        }
        return true
    }
}

public struct PhysicalTrait: Codable, Equatable, Sendable {
    public var attribute: String
    public var value: String
    public var evidence: String
    public init(attribute: String, value: String, evidence: String) {
        self.attribute = attribute; self.value = value; self.evidence = evidence
    }
}

public struct CharacterMark: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var nameRange: NSRange
    public var paragraph: String
    public var extractedParagraph: String?
    public var traits: [PhysicalTrait] = []
    public var isDetached = false
    public var needsReview: Bool { isDetached || (extractedParagraph != nil && extractedParagraph != paragraph) }
}

public struct CharacterSheetVersion: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var createdAt = Date()
    public var imageFile: String
    public var prompt: String
    public var agent: String
    public var referenceVersionID: UUID?
    public init(imageFile: String, prompt: String, agent: String, referenceVersionID: UUID? = nil) {
        self.imageFile = imageFile; self.prompt = prompt; self.agent = agent; self.referenceVersionID = referenceVersionID
    }
}

public struct CharacterReference: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var colourIndex: Int
    public var marks: [CharacterMark] = []
    public var prompt = ""
    public var versions: [CharacterSheetVersion] = []
    public var activeVersionID: UUID?
    public var needsReview: Bool { marks.contains(where: \.needsReview) }
    public var activeVersion: CharacterSheetVersion? { versions.first { $0.id == activeVersionID } }

    public var contradictions: [String] {
        let traits = marks.flatMap(\.traits)
        let grouped = Dictionary(grouping: traits) { $0.attribute.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        return grouped.keys.sorted().compactMap { key in
            let values = Set(grouped[key, default: []].map { $0.value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
            return values.count > 1 ? "\(key): \(values.sorted().joined(separator: " / "))" : nil
        }
    }

    public var suggestedPrompt: String {
        let details = Array(Set(marks.flatMap(\.traits).map { "\($0.attribute): \($0.value)" })).sorted()
        return """
        Create one character reference sheet for \(name). Show front, profile and back views, plus facial expressions, on a neutral background. Keep appearance consistent across all views.

        Explicit physical details:
        \(details.isEmpty ? "No physical details stated. Unspecified traits remain creative choices for review." : details.joined(separator: "\n"))

        Do not treat unspecified traits as screenplay facts.
        """
    }
}

public struct CharacterLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var sourceFingerprint = ""
    public var characters: [CharacterReference] = []
    public init() {}

    @discardableResult
    public mutating func mark(source: String, selection: NSRange, characterID: UUID? = nil) throws -> UUID {
        let block = try CharacterActionBlock.selected(in: source, range: selection)
        guard !characters.flatMap(\.marks).contains(where: { !$0.isDetached && $0.nameRange == selection }) else {
            throw CharacterSheetError.operation("This occurrence is already marked.")
        }
        let index: Int
        if let characterID {
            guard let found = characters.firstIndex(where: { $0.id == characterID }) else { throw CharacterSheetError.invalidLibrary }
            index = found
        } else {
            index = characters.count
            let used = Set(characters.map(\.colourIndex))
            let colour = (0...).first { !used.contains($0) }!
            characters.append(CharacterReference(name: block.name, colourIndex: colour))
        }
        characters[index].marks.append(CharacterMark(name: block.name, nameRange: selection, paragraph: block.text))
        sourceFingerprint = SceneAnchor.digest(source)
        return characters[index].id
    }

    /// Rebase marks through a single contiguous edit. Overlapping edits never silently retarget a name.
    public mutating func reconcile(from old: String, to new: String) {
        guard old != new else { return }
        let before = Array(old.utf16), after = Array(new.utf16)
        var prefix = 0, suffix = 0
        while prefix < min(before.count, after.count) && before[prefix] == after[prefix] { prefix += 1 }
        while suffix < min(before.count, after.count) - prefix && before[before.count - suffix - 1] == after[after.count - suffix - 1] { suffix += 1 }
        let removed = before.count - prefix - suffix
        let inserted = after.count - prefix - suffix
        for c in characters.indices {
            for m in characters[c].marks.indices {
                var mark = characters[c].marks[m]
                guard !mark.isDetached else { continue }
                let range = mark.nameRange
                if prefix + removed <= range.location { mark.nameRange.location += inserted - removed }
                else if prefix < NSMaxRange(range) { mark.isDetached = true }
                if !mark.isDetached,
                   let block = try? CharacterActionBlock.selected(in: new, range: mark.nameRange), block.name == mark.name {
                    mark.paragraph = block.text
                } else { mark.isDetached = true }
                characters[c].marks[m] = mark
            }
        }
        sourceFingerprint = SceneAnchor.digest(new)
    }

    /// On reopening, stale offsets are never trusted merely because the same name is there.
    public mutating func verify(source: String) {
        let matches = sourceFingerprint == SceneAnchor.digest(source)
        for c in characters.indices {
            for m in characters[c].marks.indices {
                let mark = characters[c].marks[m]
                guard matches, let block = try? CharacterActionBlock.selected(in: source, range: mark.nameRange),
                      block.name == mark.name, block.text == mark.paragraph else {
                    characters[c].marks[m].isDetached = true
                    continue
                }
            }
        }
        sourceFingerprint = SceneAnchor.digest(source)
    }
}

public enum CharacterLibraryStore {
    public static func directory(for screenplay: URL) -> URL {
        screenplay.deletingPathExtension().appendingPathExtension("characters")
    }
    public static func data(_ library: CharacterLibrary) throws -> Data {
        try validate(library)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(library)
        guard data.count <= 16_777_216 else { throw CharacterSheetError.operation("The character library exceeds its 16 MB metadata limit. Save a separate screenplay copy before adding more history.") }
        return data
    }
    public static func decode(_ data: Data) throws -> CharacterLibrary {
        guard data.count <= 16_777_216 else { throw CharacterSheetError.invalidLibrary }
        let result = try JSONDecoder().decode(CharacterLibrary.self, from: data)
        try validate(result)
        return result
    }
    public static func validate(_ library: CharacterLibrary) throws {
        guard library.version == 1, Set(library.characters.map(\.id)).count == library.characters.count,
              Set(library.characters.map(\.colourIndex)).count == library.characters.count,
              Set(library.characters.flatMap(\.marks).map(\.id)).count == library.characters.flatMap(\.marks).count else { throw CharacterSheetError.invalidLibrary }
        for character in library.characters {
            guard character.colourIndex >= 0, !character.name.isEmpty,
                  Set(character.versions.map(\.id)).count == character.versions.count,
                  character.activeVersionID == nil || character.versions.contains(where: { $0.id == character.activeVersionID }) else { throw CharacterSheetError.invalidLibrary }
            for mark in character.marks {
                guard mark.nameRange.location >= 0, mark.nameRange.length > 0, mark.nameRange.length <= 100,
                      mark.nameRange.location < Int.max - mark.nameRange.length else { throw CharacterSheetError.invalidLibrary }
            }
            for version in character.versions {
                guard safeImagePath(version.imageFile), version.referenceVersionID == nil || character.versions.contains(where: { $0.id == version.referenceVersionID }) else {
                    throw CharacterSheetError.invalidLibrary
                }
            }
        }
    }
    public static func safeImagePath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0] == "images" && !parts[1].isEmpty && parts[1] != "." && parts[1] != ".."
            && !path.contains("\\") && ["png", "jpg", "jpeg", "webp"].contains((path as NSString).pathExtension.lowercased())
    }
}

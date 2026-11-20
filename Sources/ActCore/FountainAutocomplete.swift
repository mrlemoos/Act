import Foundation

public enum FountainAutocomplete {
    public enum Category: String, Equatable, Sendable {
        case character, sceneHeading, transition
    }

    public struct Session: Equatable, Sendable {
        public let lineRange: NSRange
        public let completableRange: NSRange
        public let category: Category
        public let filter: String
        public let sceneNumberSuffix: String?
        public let forcedPrefix: String?

        public init(lineRange: NSRange, completableRange: NSRange, category: Category, filter: String,
                    sceneNumberSuffix: String?, forcedPrefix: String?) {
            self.lineRange = lineRange
            self.completableRange = completableRange
            self.category = category
            self.filter = filter
            self.sceneNumberSuffix = sceneNumberSuffix
            self.forcedPrefix = forcedPrefix
        }
    }

    public struct Suggestion: Equatable, Sendable {
        public let insertText: String
        public let displayText: String

        public init(insertText: String, displayText: String) {
            self.insertText = insertText
            self.displayText = displayText
        }
    }

  private static let continuationPattern = #"\(\s*CONT\s*['’]?\s*D\s*\)"#
    private static let builtInExtensions = ["(V.O.)", "(O.S.)", "(O.C.)"]
    private static let sceneHeadingPrefixes = ["INT.", "EXT.", "EST.", "INT./EXT.", "INT/EXT.", "I/E.",
                                               "INT ", "EXT ", "EST ", "INT./EXT ", "INT/EXT ", "I/E "]
    private static let builtInTransitions: [(display: String, insert: String)] = [
        ("CUT TO:", "CUT TO:"),
        ("DISSOLVE TO:", "DISSOLVE TO:"),
        ("BACK TO:", "BACK TO:"),
        ("SMASH CUT TO:", "SMASH CUT TO:"),
        ("MATCH CUT TO:", "MATCH CUT TO:"),
        ("FADE OUT.", ">FADE OUT.")
    ]

    public static func session(source: String, selection: NSRange, libraryNames: [String] = [],
                             imeComposing: Bool = false) -> Session? {
        guard !imeComposing else { return nil }
        let text = source as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
              selection.length <= text.length - selection.location else { return nil }
        guard selectionConfinedToLine(selection, in: text) else { return nil }

        var lineStart = 0, lineEnd = 0, contentsEnd = 0
        text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                          for: NSRange(location: selection.location, length: 0))
        let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
        let line = text.substring(with: lineRange)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        guard previousLineBlank(in: text, before: lineStart) || isScreenplayBodyStart(in: text, lineStart: lineStart) else { return nil }
        guard let category = categoryForLine(line, source: source, lineStart: lineStart) else { return nil }

        let forced = forcedPrefix(in: trimmed)
        let sceneSuffix = FountainParser.trailingSceneNumberSuffix(in: trimmed)
        let body = sceneSuffix.map { String(trimmed.dropLast($0.count)).trimmingCharacters(in: .whitespaces) } ?? trimmed

        guard !body.isEmpty || forced != nil else { return nil }

        let completableEnd = selection.length == 0 ? selection.location : NSMaxRange(selection)
        let typedLineEnd = sceneSuffix.map { contentsEnd - $0.count } ?? contentsEnd
        let end = min(max(completableEnd, lineStart), typedLineEnd)
        guard end >= lineStart, end <= contentsEnd else { return nil }
        let completableRange = NSRange(location: lineStart, length: end - lineStart)
        let typed = text.substring(with: completableRange)
        let filter = normalisedFilter(from: typed, forced: forced, category: category)

        let session = Session(lineRange: lineRange, completableRange: completableRange, category: category,
                              filter: filter, sceneNumberSuffix: sceneSuffix, forcedPrefix: forced)
        let suggestions = suggestions(for: session, screenplay: FountainParser.parse(source),
                                        libraryNames: libraryNames, locale: nil)
        return suggestions.isEmpty ? nil : session
    }

    public static func suggestions(for session: Session, screenplay: FountainScreenplay, libraryNames: [String],
                                   locale: String? = nil) -> [Suggestion] {
        let ranked: [Ranked]
        switch session.category {
        case .character:
            ranked = characterCandidates(screenplay: screenplay, libraryNames: libraryNames, session: session)
        case .sceneHeading:
            ranked = sceneHeadingCandidates(screenplay: screenplay, session: session, locale: locale)
        case .transition:
            ranked = transitionCandidates(screenplay: screenplay, session: session)
        }
        let filtered = ranked.filter { matches($0, filter: session.filter) }
        let sorted = filtered.sorted()
        var seen: Set<String> = []
        var results: [Suggestion] = []
        for item in sorted {
            guard seen.insert(item.insertText).inserted else { continue }
            results.append(Suggestion(insertText: item.insertText, displayText: item.displayText))
            if results.count >= 15 { break }
        }
        return results
    }

    public static func applying(_ suggestion: Suggestion, to source: String, session: Session) -> (source: String, selection: NSRange)? {
        let text = source as NSString
        guard session.lineRange.location >= 0, NSMaxRange(session.lineRange) <= text.length,
              NSMaxRange(session.completableRange) <= NSMaxRange(session.lineRange) else { return nil }
        var lineEnd = 0, contentsEnd = 0
        text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd,
                          for: NSRange(location: session.lineRange.location, length: 0))
        let lineEnding = text.substring(with: NSRange(location: contentsEnd, length: lineEnd - contentsEnd))
        let prefix = text.substring(to: session.completableRange.location)
        let tailOnLine = text.substring(with: NSRange(location: NSMaxRange(session.completableRange),
                                                      length: NSMaxRange(session.lineRange) - NSMaxRange(session.completableRange)))
        let newSource = prefix + suggestion.insertText + tailOnLine + lineEnding + text.substring(from: lineEnd)
        let caret = session.completableRange.location + (suggestion.insertText as NSString).length
        return (newSource, NSRange(location: caret, length: 0))
    }

    // MARK: - Ranking

    private struct Ranked: Comparable {
        let insertText: String
        let displayText: String
        let prefixMatch: Bool
        let documentPriority: Bool
        let count: Int
        let lastOffset: Int

        static func < (lhs: Ranked, rhs: Ranked) -> Bool {
            if lhs.prefixMatch != rhs.prefixMatch { return lhs.prefixMatch && !rhs.prefixMatch }
            if lhs.documentPriority != rhs.documentPriority { return lhs.documentPriority && !rhs.documentPriority }
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            if lhs.lastOffset != rhs.lastOffset { return lhs.lastOffset > rhs.lastOffset }
            return lhs.displayText.localizedCaseInsensitiveCompare(rhs.displayText) == .orderedAscending
        }
    }

    private static func matches(_ item: Ranked, filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        let haystack = item.displayText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let needle = filter.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return haystack.hasPrefix(needle) || haystack.localizedCaseInsensitiveContains(needle)
    }

    private static func prefixRank(_ candidate: String, filter: String) -> (Bool, Bool) {
        guard !filter.isEmpty else { return (true, false) }
        let haystack = candidate.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let needle = filter.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        if haystack.hasPrefix(needle) { return (true, true) }
        if haystack.localizedCaseInsensitiveContains(needle) { return (true, false) }
        return (false, false)
    }

    // MARK: - Character candidates

    private static func characterCandidates(screenplay: FountainScreenplay, libraryNames: [String], session: Session) -> [Ranked] {
        let text = screenplay.source as NSString
        let line = text.substring(with: session.lineRange)
        let forced = session.forcedPrefix ?? forcedPrefix(in: line.trimmingCharacters(in: .whitespaces))
        let body = sceneBody(line: line, suffix: session.sceneNumberSuffix)
        let (namePart, extensionPart) = splitCue(body)
        var ranked: [Ranked] = []

        if extensionPart != nil || body.contains("(") {
            ranked += extensionCandidates(name: namePart, screenplay: screenplay, session: session)
        } else {
            var counts: [String: Int] = [:]
            var last: [String: Int] = [:]
            for element in screenplay.elements where element.kind == .character {
                let cue = FountainParser.displayText(element)
                let name = cueName(from: cue)
                guard !name.isEmpty else { continue }
                counts[name, default: 0] += 1
                last[name] = element.range.location
            }
            for (name, count) in counts {
                let insert = forced == "@" ? "@" + name : name
                let (ok, prefix) = prefixRank(insert, filter: session.filter)
                guard ok else { continue }
                ranked.append(Ranked(insertText: insert, displayText: name, prefixMatch: prefix,
                                     documentPriority: true, count: count, lastOffset: last[name] ?? 0))
            }
            if libraryEligible(namePart: namePart, forced: forced) {
                let spoken = Set(counts.keys.map { $0.uppercased() })
                for library in libraryNames {
                    let upper = library.uppercased()
                    guard !spoken.contains(upper) else { continue }
                    let insert = forced == "@" ? "@" + upper : upper
                    let (ok, prefix) = prefixRank(insert, filter: session.filter)
                    guard ok else { continue }
                    ranked.append(Ranked(insertText: insert, displayText: upper, prefixMatch: prefix,
                                         documentPriority: false, count: 0, lastOffset: -1))
                }
            }
            ranked += extensionCandidates(name: namePart, screenplay: screenplay, session: session)
        }
        return ranked
    }

    private static func extensionCandidates(name: String, screenplay: FountainScreenplay, session: Session) -> [Ranked] {
        guard !name.isEmpty else { return [] }
        var harvested: Set<String> = []
        for element in screenplay.elements where element.kind == .character {
            let cue = FountainParser.displayText(element)
            guard cue.uppercased().hasPrefix(name.uppercased()) else { continue }
            if let ext = cueExtension(from: cue, speaker: name), !isContinuation(ext) { harvested.insert(ext) }
        }
        var options = builtInExtensions + harvested.sorted()
        options = Array(Set(options)).sorted()
        return options.compactMap { ext in
            let insert = name + " " + ext
            let (ok, prefix) = prefixRank(insert, filter: session.filter)
            guard ok else { return nil }
            return Ranked(insertText: insert, displayText: insert, prefixMatch: prefix,
                          documentPriority: true, count: 1, lastOffset: 0)
        }
    }

    private static func libraryEligible(namePart: String, forced: String?) -> Bool {
        let stripped = namePart.hasPrefix("@") ? String(namePart.dropFirst()) : namePart
        let beforeParen = stripped.split(separator: "(", maxSplits: 1).first.map(String.init) ?? stripped
        let trimmed = beforeParen.trimmingCharacters(in: .whitespaces)
        guard trimmed.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
        return trimmed == trimmed.uppercased() && FountainParser.isCharacterCue(trimmed)
    }

    // MARK: - Scene headings

    public static func shippedTimeOfDayKeys(locale: String) -> [String] {
        let normalised = L10n.resolvedLanguage(preferences: [locale])
        switch normalised {
        case "es-ES":
            return ["DAY", "NIGHT", "DAWN", "DUSK", "MORNING", "LATER", "CONTINUOUS"].map { builtInTimeKey($0) }
        case "pt-BR":
            return ["DAY", "NIGHT", "DAWN", "DUSK", "MORNING", "LATER", "CONTINUOUS"].map { builtInTimeKey($0) }
        case "it-IT":
            return ["DAY", "NIGHT", "DAWN", "DUSK", "MORNING", "EVENING", "LATER", "CONTINUOUS"].map { builtInTimeKey($0) }
        default:
            return ["DAY", "NIGHT", "DAWN", "DUSK", "MORNING", "EVENING", "LATER", "CONTINUOUS", "SAME"].map { builtInTimeKey($0) }
        }
    }

    private static func builtInTimeKey(_ english: String) -> String { "Time of day|\(english)" }

    private static func localisedTimeOfDay(locale: String?) -> [(key: String, text: String)] {
        shippedTimeOfDayKeys(locale: locale ?? L10n.language).map { key in
            (key, L10n.string(key, table: "Autocomplete", locale: locale))
        }
    }

    private static func sceneHeadingCandidates(screenplay: FountainScreenplay, session: Session, locale: String?) -> [Ranked] {
        var ranked: [Ranked] = []
        var headingCounts: [String: Int] = [:]
        var headingLast: [String: Int] = [:]
        var locationCounts: [String: Int] = [:]
        var locationLast: [String: Int] = [:]
        var timeCounts: [String: Int] = [:]
        var timeLast: [String: Int] = [:]

        for element in screenplay.elements where element.kind == .sceneHeading {
            let heading = FountainParser.displayText(element)
            let withoutNumber = FountainParser.trailingSceneNumberSuffix(in: heading)
                .map { String(heading.dropLast($0.count)).trimmingCharacters(in: .whitespaces) } ?? heading
            headingCounts[withoutNumber, default: 0] += 1
            headingLast[withoutNumber] = element.range.location
            if let dash = withoutNumber.range(of: " - ") {
                let location = String(withoutNumber[..<dash.lowerBound]).trimmingCharacters(in: .whitespaces)
                let time = String(withoutNumber[dash.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !location.isEmpty {
                    locationCounts[location, default: 0] += 1
                    locationLast[location] = element.range.location
                }
                if !time.isEmpty {
                    timeCounts[time, default: 0] += 1
                    timeLast[time] = element.range.location
                }
            }
        }

        func add(_ insert: String, display: String, count: Int, last: Int, documentPriority: Bool = true) {
            let (ok, prefix) = prefixRank(insert, filter: session.filter)
            guard ok else { return }
            ranked.append(Ranked(insertText: insert, displayText: display, prefixMatch: prefix,
                                 documentPriority: documentPriority, count: count, lastOffset: last))
        }

        for prefix in sceneHeadingPrefixes {
            let insert = session.forcedPrefix == "." ? "." + prefix : prefix
            add(insert, display: prefix, count: 0, last: -1, documentPriority: false)
        }
        for (heading, count) in headingCounts {
            let insert = session.forcedPrefix == "." ? "." + heading : heading
            add(insert, display: heading, count: count, last: headingLast[heading] ?? 0)
        }
        for (location, count) in locationCounts {
            add(location, display: location, count: count, last: locationLast[location] ?? 0)
        }
        for (time, count) in timeCounts {
            add(time, display: time, count: count, last: timeLast[time] ?? 0, documentPriority: true)
        }
        let documentedTimes = Set(timeCounts.keys)
        for (_, term) in localisedTimeOfDay(locale: locale) where !documentedTimes.contains(term) {
            add(term, display: term, count: 0, last: -1, documentPriority: false)
        }
        return ranked
    }

    // MARK: - Transitions

    private static func transitionCandidates(screenplay: FountainScreenplay, session: Session) -> [Ranked] {
        var counts: [String: Int] = [:]
        var last: [String: Int] = [:]
        for element in screenplay.elements where element.kind == .transition {
            let display = FountainParser.displayText(element)
            counts[display, default: 0] += 1
            last[display] = element.range.location
        }
        var ranked: [Ranked] = []
        for (display, count) in counts {
            let insert = transitionInsert(display, hasForced: session.forcedPrefix == ">")
            let (ok, prefix) = prefixRank(insert, filter: session.filter)
            guard ok else { continue }
            ranked.append(Ranked(insertText: insert, displayText: display, prefixMatch: prefix,
                                 documentPriority: true, count: count, lastOffset: last[display] ?? 0))
        }
        for builtin in builtInTransitions {
            var insert = builtin.insert
            if session.forcedPrefix == ">" {
                if !insert.hasPrefix(">") { insert = ">" + insert }
            } else if insert.hasPrefix(">") {
                insert = String(insert.dropFirst())
            }
            let (ok, prefix) = prefixRank(insert, filter: session.filter)
            guard ok else { continue }
            ranked.append(Ranked(insertText: insert, displayText: builtin.display, prefixMatch: prefix,
                                 documentPriority: false, count: 0, lastOffset: -1))
        }
        return ranked
    }

    private static func transitionInsert(_ display: String, hasForced: Bool) -> String {
        hasForced ? ">" + display : display
    }

    // MARK: - Context

    private static func categoryForLine(_ line: String, source: String, lineStart: Int) -> Category? {
        let text = source as NSString
        let screenplay = FountainParser.parse(source)
        if let element = screenplay.elements.first(where: { NSLocationInRange(lineStart, $0.range) }) {
            switch element.kind {
            case .dialogue, .parenthetical, .titlePage, .note, .boneyard, .section, .synopsis, .centred, .pageBreak:
                return nil
            case .action:
                let visible = FountainParser.displayText(element)
                if !visible.trimmingCharacters(in: .whitespaces).isEmpty,
                   !line.hasPrefix("@"), !line.hasPrefix("."), !line.hasPrefix(">"),
                   !FountainParser.isSceneHeadingLine(line.trimmingCharacters(in: .whitespaces)),
                   !FountainParser.isCharacterCue(line.trimmingCharacters(in: .whitespaces)) {
                    return nil
                }
            default: break
            }
        }
        guard let probed = probedKind(at: lineStart, in: text, line: line) else { return nil }
        switch probed {
        case .character: return .character
        case .sceneHeading: return .sceneHeading
        case .transition: return .transition
        default: return nil
        }
    }

    private static func probedKind(at lineStart: Int, in text: NSString, line: String) -> FountainElement.Kind? {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
        let terminator = FountainEditingLineEnding.lineEnding(in: text, start: start, end: end, contentsEnd: contentsEnd)
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let probe = trimmed.isEmpty ? "Dialogue probe." : line
        let context = text.substring(to: start) + probe + terminator + "Dialogue probe."
        return FountainParser.parse(context).elements.first { $0.range.location == start }?.kind
    }

    private static func previousLineBlank(in text: NSString, before lineStart: Int) -> Bool {
        guard lineStart > 0 else { return true }
        var priorStart = 0, priorEnd = 0, priorContents = 0
        text.getLineStart(&priorStart, end: &priorEnd, contentsEnd: &priorContents,
                          for: NSRange(location: lineStart - 1, length: 0))
        let prior = text.substring(with: NSRange(location: priorStart, length: priorContents - priorStart))
        return prior.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isScreenplayBodyStart(in text: NSString, lineStart: Int) -> Bool {
        guard lineStart > 0 else { return true }
        let screenplay = FountainParser.parse(sourcePrefix(text, through: lineStart))
        guard let firstBody = screenplay.elements.first(where: {
            switch $0.kind {
            case .titlePage, .blank: return false
            default: return true
            }
        }) else { return true }
        return lineStart <= firstBody.range.location
    }

    private static func sourcePrefix(_ text: NSString, through offset: Int) -> String {
        text.substring(to: min(offset, text.length))
    }

    private static func selectionConfinedToLine(_ selection: NSRange, in text: NSString) -> Bool {
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd,
                          for: NSRange(location: selection.location, length: 0))
        let line = NSRange(location: start, length: contentsEnd - start)
        guard selection.location >= line.location, NSMaxRange(selection) <= NSMaxRange(line) else { return false }
        return true
    }

    private static func forcedPrefix(in line: String) -> String? {
        if line.hasPrefix("@") { return "@" }
        if line.hasPrefix(".") { return "." }
        if line.hasPrefix(">") { return ">" }
        return nil
    }

    private static func normalisedFilter(from typed: String, forced: String?, category: Category) -> String {
        var value = typed.trimmingCharacters(in: .whitespaces)
        if let forced, value.hasPrefix(forced) {
            value = String(value.dropFirst())
        }
        return value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func sceneBody(line: String, suffix: String?) -> String {
        var body = line.trimmingCharacters(in: .whitespaces)
        if let suffix { body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces) }
        return body
    }

    private static func splitCue(_ body: String) -> (String, String?) {
        guard let open = body.firstIndex(of: "(") else { return (body, nil) }
        let name = String(body[..<open]).trimmingCharacters(in: .whitespaces)
        let ext = String(body[open...]).trimmingCharacters(in: .whitespaces)
        return (name, ext.isEmpty ? nil : ext)
    }

    private static func cueName(from cue: String) -> String {
        cue.split(separator: "(", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? cue
    }

    private static func cueExtension(from cue: String, speaker: String) -> String? {
        let upperCue = cue.uppercased()
        let upperSpeaker = speaker.uppercased()
        guard upperCue.hasPrefix(upperSpeaker), let open = cue.firstIndex(of: "(") else { return nil }
        return String(cue[open...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isContinuation(_ value: String) -> Bool {
        value.range(of: continuationPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

enum FountainEditingLineEnding {
    static func lineEnding(in text: NSString, start: Int, end: Int, contentsEnd: Int) -> String {
        if end > contentsEnd {
            let current = text.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))
            if ["\n", "\r\n", "\r"].contains(current) { return current }
        }
        let preceding = NSRange(location: 0, length: start)
        let lf = text.range(of: "\n", options: .backwards, range: preceding)
        let cr = text.range(of: "\r", options: .backwards, range: preceding)
        if cr.location != NSNotFound, lf.location == NSNotFound || cr.location > lf.location { return "\r" }
        if lf.location != NSNotFound {
            return lf.location > 0 && text.character(at: lf.location - 1) == 13 ? "\r\n" : "\n"
        }
        return "\n"
    }
}
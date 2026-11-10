import Foundation

public enum ScreenplayPaper: String, CaseIterable, Sendable {
    case usLetter = "US Letter"
    case a4 = "A4"

    public var size: CGSize {
        switch self {
        case .usLetter: CGSize(width: 612, height: 792)
        case .a4: CGSize(width: 595.2756, height: 841.8898)
        }
    }

    public static func read(from source: String) -> Self {
        let value = FountainTitleField.read(from: source).first { $0.key == "paper" }?.value
        return allCases.first { $0.rawValue.lowercased() == value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } ?? .usLetter
    }

    /// Replace only paper metadata. Preserve all other bytes, including line endings.
    public func updating(_ source: String) -> String {
        let elements = FountainParser.parse(source).elements
        let ns = source as NSString
        let newline = source.contains("\r\n") ? "\r\n" : source.contains("\r") ? "\r" : "\n"
        var ranges: [NSRange] = []
        var readingPaper = false
        for element in elements where element.kind == .titlePage {
            let raw = element.text
            if raw.first?.isWhitespace != true, let colon = raw.firstIndex(of: ":") {
                readingPaper = raw[..<colon].trimmingCharacters(in: .whitespaces).lowercased() == "paper"
            }
            if readingPaper {
                var start = 0, end = 0, contents = 0
                ns.getLineStart(&start, end: &end, contentsEnd: &contents, for: element.range)
                ranges.append(NSRange(location: start, length: end - start))
            }
        }
        if let first = ranges.first {
            let result = NSMutableString(string: source)
            for range in ranges.reversed() {
                var start = 0, end = 0, contents = 0
                ns.getLineStart(&start, end: &end, contentsEnd: &contents, for: NSRange(location: range.location, length: 0))
                let ending = ns.substring(with: NSRange(location: contents, length: end - contents))
                let replacement = range == first ? "Paper: \(rawValue)" + ending : ""
                result.replaceCharacters(in: range, with: replacement)
            }
            return result as String
        }
        let separator = elements.contains { $0.kind == .titlePage } ? newline : newline + newline
        return "Paper: \(rawValue)" + separator + source
    }
}

public struct FountainTitleField: Equatable, Sendable {
    public let key: String
    public var value: String

    public static func read(from source: String) -> [Self] {
        var fields: [Self] = []
        for element in FountainParser.parse(source).elements where element.kind == .titlePage {
            let raw = FountainParser.displayText(element)
            if element.text.first?.isWhitespace != true, let colon = raw.firstIndex(of: ":") {
                fields.append(Self(key: raw[..<colon].trimmingCharacters(in: .whitespaces).lowercased(),
                                   value: raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)))
            } else if !fields.isEmpty {
                let value = raw.trimmingCharacters(in: .whitespaces)
                if !fields[fields.count - 1].value.isEmpty { fields[fields.count - 1].value += "\n" }
                fields[fields.count - 1].value += value
            }
        }
        return fields
    }
}

import Foundation

public enum FountainEditing {
    /// Return separates screenplay blocks, while character cues and dialogue
    /// continue on the next line. Probe text supplies lookahead for a cue that
    /// is still being typed, without changing the authoritative source.
    public static func returnInsertion(in source: String, selection: NSRange) -> String {
        let text = source as NSString
        guard selection.location != NSNotFound, selection.location >= 0, selection.length >= 0, selection.location <= text.length,
              selection.length <= text.length - selection.location else { return "\n\n" }
        var start = 0, end = 0, contentsEnd = 0
        text.getLineStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: selection.location, length: 0))
        let terminator = FountainEditingLineEnding.lineEnding(in: text, start: start, end: end, contentsEnd: contentsEnd)
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        let probe = line.trimmingCharacters(in: .whitespaces).isEmpty ? "Dialogue probe." : line
        let context = text.substring(to: start) + probe + terminator + "Dialogue probe."
        let kind = FountainParser.parse(context).elements.first { $0.range.location == start }?.kind
        let isDialogue = kind == .character || kind == .dialogue || kind == .parenthetical
        return isDialogue ? terminator : terminator + terminator
    }

}

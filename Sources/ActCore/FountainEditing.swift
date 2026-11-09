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
        let terminator = lineEnding(in: text, start: start, end: end, contentsEnd: contentsEnd)
        let line = text.substring(with: NSRange(location: start, length: contentsEnd - start))
        let probe = line.trimmingCharacters(in: .whitespaces).isEmpty ? "Dialogue probe." : line
        let context = text.substring(to: start) + probe + terminator + "Dialogue probe."
        let kind = FountainParser.parse(context).elements.first { $0.range.location == start }?.kind
        let isDialogue = kind == .character || kind == .dialogue || kind == .parenthetical
        return isDialogue ? terminator : terminator + terminator
    }

    private static func lineEnding(in text: NSString, start: Int, end: Int, contentsEnd: Int) -> String {
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

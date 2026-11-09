import Foundation

/// Screenplay presentation changes never alter the authoritative Fountain source.
public enum ScreenplayPresentation {
    /// Cue strings keyed by the source element's UTF-16 location.
    public static func characterCues(in screenplay: FountainScreenplay, settings: ScreenplaySettings = .standard) -> [Int: String] {
        let settings = settings.validated
        var cues: [Int: String] = [:]
        var previousSpeaker: String?
        var interruptedByAction = false
        for element in screenplay.elements {
            switch element.kind {
            case .sceneHeading:
                previousSpeaker = nil
                interruptedByAction = false
            case .character:
                let cue = FountainParser.displayText(element)
                let speaker = cue.split(separator: "(", maxSplits: 1).first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces).uppercased() ?? cue.uppercased()
                cues[element.range.location] = settings.dialogueContinuations && interruptedByAction && previousSpeaker == speaker
                    ? continuationCue(cue) : cue
                previousSpeaker = speaker
                interruptedByAction = false
            case .action:
                if !FountainParser.displayText(element).isEmpty { interruptedByAction = true }
            default: break
            }
        }
        return cues
    }

    /// Extra presentation lines required beyond the literal blank lines already in the source.
    /// The first heading on a page of otherwise empty body text needs no leading space.
    public static func missingBlankLinesBeforeSluglines(in screenplay: FountainScreenplay, settings: ScreenplaySettings = .standard) -> [Int: Int] {
        let desired = settings.validated.blankLinesBeforeSlugline
        var result: [Int: Int] = [:]
        var blanks = 0
        var hasBody = false
        for element in screenplay.elements {
            switch element.kind {
            case .blank: blanks += 1
            case .sceneHeading:
                result[element.range.location] = hasBody ? max(0, desired - blanks) : 0
                hasBody = true
                blanks = 0
            case .titlePage, .section, .synopsis, .note, .boneyard: break
            default:
                if !FountainParser.displayText(element).isEmpty { hasBody = true }
                blanks = 0
            }
        }
        return result
    }

    public static func continuationCue(_ cue: String) -> String {
        let explicit = cue.range(of: #"\(\s*CONT\s*['’]?\s*D\s*\)"#, options: [.regularExpression, .caseInsensitive])
        return explicit == nil ? cue + " (CONT'D)" : cue
    }
}

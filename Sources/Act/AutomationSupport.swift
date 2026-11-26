import ActCore

func automationText(_ key: String) -> String { L10n.string(key, table: "Automation") }

func automationJobTitle(_ targetKind: String) -> String {
    switch targetKind {
    case "shot": return automationText("Storyboard image")
    case "character": return automationText("Character image")
    default: return automationText("Local generation")
    }
}

func automationChangeHeadline(_ change: AutomationChange) -> String {
    switch change.kind {
    case "move":
        return automationText(change.role == "origin" ? "Moved from here" : "Moved here")
  default:
        return automationText(change.kind)
    }
}

func automationChangeSymbol(_ change: AutomationChange) -> String {
    change.kind == "move" ? "arrow.up.arrow.down" : (change.after.isEmpty ? "minus.circle" : "plus.circle")
}
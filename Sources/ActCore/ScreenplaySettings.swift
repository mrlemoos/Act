import Foundation

/// Presentation preferences never change the authoritative Fountain source.
public struct ScreenplaySettings: Codable, Equatable, Sendable {
    public var fontName: String
    public var fontSize: Double
    public var blankLinesBeforeSlugline: Int
    public var boldSluglines: Bool
    public var dialogueContinuations: Bool

    public static let standard = ScreenplaySettings()

    public init(fontName: String = "Courier", fontSize: Double = 12, blankLinesBeforeSlugline: Int = 2, boldSluglines: Bool = true, dialogueContinuations: Bool = true) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.blankLinesBeforeSlugline = blankLinesBeforeSlugline
        self.boldSluglines = boldSluglines
        self.dialogueContinuations = dialogueContinuations
    }

    public var validated: Self {
        var result = self
        if result.fontName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.fontName = "Courier" }
        result.fontSize = result.fontSize.isFinite ? min(24, max(8, result.fontSize)) : 12
        result.blankLinesBeforeSlugline = result.blankLinesBeforeSlugline == 1 ? 1 : 2
        return result
    }
}

public enum ScreenplaySettingsStore {
    public static let key = "Act.screenplaySettings.v1"

    public static func load(from defaults: UserDefaults = .standard) -> ScreenplaySettings {
        guard let data = defaults.data(forKey: key), let settings = try? JSONDecoder().decode(ScreenplaySettings.self, from: data) else { return .standard }
        return settings.validated
    }

    public static func save(_ settings: ScreenplaySettings, to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(settings.validated), forKey: key)
    }
}

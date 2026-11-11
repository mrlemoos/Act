import Foundation

/// Interface copy only. Never pass document text, persisted identifiers or model payloads through localisation.
public enum L10n {
    public static let supportedLocales = ["en-GB", "en-US", "pt-BR", "es-ES", "fr-FR", "de-DE", "it-IT"]
    public static let fallbackLocale = "en-GB"

    /// macOS supplies the app-specific language through the process's preferred languages at launch.
    public static var language: String { resolvedLanguage(preferences: Locale.preferredLanguages) }

    public static func resolvedLanguage(preferences: [String]) -> String {
        for preference in preferences {
            let normalised = preference.replacingOccurrences(of: "_", with: "-")
            if let exact = supportedLocales.first(where: { $0.caseInsensitiveCompare(normalised) == .orderedSame }) {
                return exact
            }
            let base = normalised.split(separator: "-").first.map(String.init)?.lowercased()
            if let matching = supportedLocales.first(where: { $0.split(separator: "-").first.map(String.init)?.lowercased() == base }) {
                return matching
            }
        }
        return fallbackLocale
    }

    public static func string(_ key: String, table: String = "Localizable", locale: String? = nil) -> String {
        let selected = locale.map { resolvedLanguage(preferences: [$0]) } ?? language
        let missing = "\u{1F}missing-localisation\u{1F}"
        if let bundle = bundle(for: selected) {
            let translated = bundle.localizedString(forKey: key, value: missing, table: table)
            if translated != missing { return translated }
        }
        return bundle(for: fallbackLocale)?.localizedString(forKey: key, value: key, table: table) ?? key
    }

    /// Positional placeholders allow translators to reorder values; stringsdict provides locale-specific plural rules.
    public static func format(_ key: String, _ arguments: CVarArg..., table: String = "Localizable", locale: String? = nil) -> String {
        let selected = locale.map { resolvedLanguage(preferences: [$0]) } ?? language
        return String(format: string(key, table: table, locale: selected), locale: Locale(identifier: selected), arguments: arguments)
    }

    static var resourceBundle: Bundle { .module }

    private static func bundle(for language: String) -> Bundle? {
        guard let path = resourceBundle.path(forResource: language, ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }
}

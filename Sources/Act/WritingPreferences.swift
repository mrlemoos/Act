import ActCore
import Foundation

@MainActor
final class WritingPreferences: ObservableObject {
    static let shared = WritingPreferences()
    private let defaults: UserDefaults

    @Published var settings: ScreenplaySettings {
        didSet {
            let validated = settings.validated
            if settings != validated { settings = validated }
            try? ScreenplaySettingsStore.save(validated, to: defaults)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = ScreenplaySettingsStore.load(from: defaults)
    }
}

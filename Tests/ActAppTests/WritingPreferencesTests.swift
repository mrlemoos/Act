import ActCore
import Foundation
import Testing
@testable import Act

@Suite(.serialized) @MainActor
struct WritingPreferencesTests {
    @Test func changingIndividualControlsPersistsThroughTheObservedModel() throws {
        let suite = "dev.act.tests.preferences." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WritingPreferences(defaults: defaults)
        model.settings.fontName = "Menlo"
        model.settings.fontSize = 14
        model.settings.blankLinesBeforeSlugline = 1
        model.settings.boldSluglines = false
        model.settings.dialogueContinuations = false
        let reopened = WritingPreferences(defaults: try #require(UserDefaults(suiteName: suite)))
        #expect(reopened.settings == ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false, dialogueContinuations: false))
    }

    @Test func invalidLivePreferencesAreNormalisedAndPersisted() throws {
        let suite = "dev.act.tests.preferences." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = WritingPreferences(defaults: defaults)
        model.settings = ScreenplaySettings(fontName: " ", fontSize: .infinity, blankLinesBeforeSlugline: -1, boldSluglines: false)
        #expect(model.settings.fontName == "Courier")
        #expect(model.settings.fontSize == 12)
        #expect(model.settings.blankLinesBeforeSlugline == 2)
        #expect(!model.settings.boldSluglines)
        #expect(ScreenplaySettingsStore.load(from: defaults) == model.settings)
    }
}

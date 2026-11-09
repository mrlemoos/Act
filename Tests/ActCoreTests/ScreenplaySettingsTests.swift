import Foundation
import XCTest
@testable import ActCore

final class ScreenplaySettingsTests: XCTestCase {
    func testPreferencesSurviveANewReader() throws {
        let suite = "ActSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ScreenplaySettings(fontName: "Menlo", fontSize: 14, blankLinesBeforeSlugline: 1, boldSluglines: false, dialogueContinuations: false)
        try ScreenplaySettingsStore.save(settings, to: defaults)
        let reader = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(ScreenplaySettingsStore.load(from: reader), settings)
    }

    func testCorruptPreferencesFallBackWithoutTouchingSavedData() throws {
        let suite = "ActSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let damaged = Data("not JSON".utf8)
        defaults.set(damaged, forKey: ScreenplaySettingsStore.key)
        XCTAssertEqual(ScreenplaySettingsStore.load(from: defaults), .standard)
        XCTAssertEqual(defaults.data(forKey: ScreenplaySettingsStore.key), damaged)
    }

    func testInvalidStoredValuesCannotBreakLayout() throws {
        let suite = "ActSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let invalid = ScreenplaySettings(fontName: " ", fontSize: 0, blankLinesBeforeSlugline: 99, boldSluglines: false)
        defaults.set(try JSONEncoder().encode(invalid), forKey: ScreenplaySettingsStore.key)
        let loaded = ScreenplaySettingsStore.load(from: defaults)
        XCTAssertEqual(loaded.fontName, "Courier")
        XCTAssertEqual(loaded.fontSize, 8)
        XCTAssertEqual(loaded.blankLinesBeforeSlugline, 2)
        XCTAssertFalse(loaded.boldSluglines)
        XCTAssertEqual(ScreenplaySettings(fontSize: .infinity).validated.fontSize, 12)
    }
    func testNonFiniteAndOversizedPreferencesAreValidatedBeforeSaving() throws {
        let suite = "ActSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for size in [Double.nan, .infinity, -.infinity] {
            try ScreenplaySettingsStore.save(ScreenplaySettings(fontSize: size), to: defaults)
            XCTAssertEqual(ScreenplaySettingsStore.load(from: defaults).fontSize, 12)
        }
        try ScreenplaySettingsStore.save(ScreenplaySettings(fontSize: 100, blankLinesBeforeSlugline: 0), to: defaults)
        let loaded = ScreenplaySettingsStore.load(from: defaults)
        XCTAssertEqual(loaded.fontSize, 24)
        XCTAssertEqual(loaded.blankLinesBeforeSlugline, 2)
    }

    func testIncompleteOrWrongTypedPreferencesFallBackWithoutRewritingThem() throws {
        let suite = "ActSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for json in ["{}", "{\"fontName\": 7}", "{\"fontName\":\"Menlo\"}"] {
            let data = Data(json.utf8)
            defaults.set(data, forKey: ScreenplaySettingsStore.key)
            XCTAssertEqual(ScreenplaySettingsStore.load(from: defaults), .standard)
            XCTAssertEqual(defaults.data(forKey: ScreenplaySettingsStore.key), data)
        }
    }

}

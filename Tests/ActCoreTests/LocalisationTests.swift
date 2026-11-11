import Foundation
import XCTest
@testable import ActCore

final class LocalisationTests: XCTestCase {
    func testRegionalEnglishAndSupportedLanguagesResolveIndependently() {
        XCTAssertEqual(L10n.resolvedLanguage(preferences: ["en-US"]), "en-US")
        XCTAssertEqual(L10n.resolvedLanguage(preferences: ["en-GB"]), "en-GB")
        XCTAssertEqual(L10n.resolvedLanguage(preferences: ["pt-BR"]), "pt-BR")
        XCTAssertEqual(L10n.resolvedLanguage(preferences: ["ja-JP", "fr-FR"]), "fr-FR")
        XCTAssertEqual(L10n.resolvedLanguage(preferences: ["ja-JP"]), "en-GB")
    }

    func testMenuResourcesProvideRealTranslationsAndBritishFallback() {
        XCTAssertEqual(L10n.string("Save", table: "Menus", locale: "pt-BR"), "Salvar")
        XCTAssertEqual(L10n.string("File", table: "Menus", locale: "de-DE"), "Ablage")
        XCTAssertEqual(L10n.string("Minimise", table: "Menus", locale: "en-US"), "Minimize")
        XCTAssertEqual(L10n.string("Minimise", table: "Menus", locale: "ja-JP"), "Minimise")
        XCTAssertEqual(L10n.string("Unknown interface key", table: "Menus", locale: "fr-FR"), "Unknown interface key")
    }

    func testFormatPreservesLiteralUserValuesAndSupportsPositionalArguments() {
        XCTAssertEqual(L10n.format("%2$@ · %1$lld", 12, "Café %@", table: "Menus", locale: "fr-FR"), "Café %@ · 12")
    }

    func testAllDeclaredLanguagesExistInResourceBundle() {
        for locale in L10n.supportedLocales {
            XCTAssertNotNil(L10n.resourceBundle.path(forResource: locale, ofType: "lproj"), locale)
            XCTAssertNotNil(L10n.resourceBundle.path(forResource: "Menus", ofType: "strings", inDirectory: "\(locale).lproj"), locale)
        }
    }

    func testEveryInterfaceTableHasMatchingKeysAndFormatArgumentsAcrossLocales() throws {
        let root = try XCTUnwrap(L10n.resourceBundle.resourceURL)
        let baseline = root.appendingPathComponent("en-GB.lproj")
        let tables = try FileManager.default.contentsOfDirectory(at: baseline, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "strings" || $0.pathExtension == "stringsdict" }
        XCTAssertFalse(tables.isEmpty)
        for table in tables {
            let original = try propertyList(table)
            for locale in L10n.supportedLocales {
                let translated = try propertyList(root.appendingPathComponent("\(locale).lproj/\(table.lastPathComponent)"))
                XCTAssertEqual(Set(original.keys), Set(translated.keys), "\(locale)/\(table.lastPathComponent)")
                if table.pathExtension == "strings" {
                    for (key, value) in original {
                        let source = try XCTUnwrap(value as? String)
                        let target = try XCTUnwrap(translated[key] as? String)
                        XCTAssertFalse(target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(locale)/\(key)")
                        XCTAssertEqual(try formatArguments(source), try formatArguments(target), "\(locale)/\(key)")
                    }
                } else {
                    for (key, value) in original {
                        let source = try XCTUnwrap(value as? [String: Any])
                        let target = try XCTUnwrap(translated[key] as? [String: Any])
                        XCTAssertEqual(Set(source.keys), Set(target.keys), "\(locale)/\(key)")
                        XCTAssertEqual(source["NSStringLocalizedFormatKey"] as? String, target["NSStringLocalizedFormatKey"] as? String)
                        for variable in source.keys where variable != "NSStringLocalizedFormatKey" {
                            let sourceRules = try XCTUnwrap(source[variable] as? [String: Any])
                            let targetRules = try XCTUnwrap(target[variable] as? [String: Any])
                            XCTAssertEqual(sourceRules["NSStringFormatSpecTypeKey"] as? String, targetRules["NSStringFormatSpecTypeKey"] as? String)
                            XCTAssertEqual(sourceRules["NSStringFormatValueTypeKey"] as? String, targetRules["NSStringFormatValueTypeKey"] as? String)
                            XCTAssertNotNil(targetRules["other"])
                            for rule in ["one", "other"] {
                                if let sourceText = sourceRules[rule] as? String, let targetText = targetRules[rule] as? String {
                                    XCTAssertEqual(try formatArguments(sourceText), try formatArguments(targetText), "\(locale)/\(key)/\(rule)")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func testDeclaredAppLanguagesAndDocumentTypeNamesHaveCompleteResources() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resources = repository.appendingPathComponent("Resources")
        let info = try propertyList(resources.appendingPathComponent("Info.plist"))
        XCTAssertEqual(Set(try XCTUnwrap(info["CFBundleLocalizations"] as? [String])), Set(L10n.supportedLocales))
        XCTAssertEqual(info["CFBundleDevelopmentRegion"] as? String, L10n.fallbackLocale)
        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let exportedTypes = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let names = Set(documentTypes.compactMap { $0["CFBundleTypeName"] as? String } + exportedTypes.compactMap { $0["UTTypeDescription"] as? String })
        for locale in L10n.supportedLocales {
            let namesTable = try propertyList(resources.appendingPathComponent("\(locale).lproj/InfoPlist.strings"))
            for name in names {
                XCTAssertFalse(try XCTUnwrap(namesTable[name] as? String).isEmpty, "\(locale)/\(name)")
            }
        }
    }

    private func propertyList(_ url: URL) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    private func formatArguments(_ string: String) throws -> [String] {
        let pattern = try NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(hh|ll|h|l|q|z|t|j)?([@diuoxXfFeEgGaAcCsSp])"#)
        let escaped = string.replacingOccurrences(of: "%%", with: "")
        let text = escaped as NSString
        return pattern.matches(in: escaped, range: NSRange(location: 0, length: text.length)).enumerated().map { index, match in
            let position = match.range(at: 1).location == NSNotFound ? String(index + 1) : text.substring(with: match.range(at: 1))
            let length = match.range(at: 2).location == NSNotFound ? "" : text.substring(with: match.range(at: 2))
            return position + ":" + length + text.substring(with: match.range(at: 3))
        }.sorted()
    }
}

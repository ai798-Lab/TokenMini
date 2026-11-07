import XCTest
@testable import MacPulse

final class LocalizationTests: XCTestCase {
    func testSystemLanguageMatchingAndFallback() {
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["zh-TW"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["zh-HK"]), .traditionalChinese)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["zh-Hans-CN"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["ar-SA"]), .arabic)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-FR", "ja-JP"]), .japanese)
        XCTAssertEqual(AppLanguage.resolve(.system, preferred: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(.korean, preferred: ["en-US"]), .korean)
    }

    func testOnlyArabicUsesRightToLeftLayout() {
        XCTAssertTrue(AppLanguage.arabic.isRightToLeft)
        XCTAssertFalse(AppLanguage.english.isRightToLeft)
        XCTAssertFalse(AppLanguage.traditionalChinese.isRightToLeft)
    }

    func testInterpolatedValuesAreKeptOutOfTranslationKeys() {
        let message: LocalizedMessage = "已选 \(3) 项 · \("2 GB")"
        XCTAssertEqual(message.key, "已选 {0} 项 · {1}")
        XCTAssertEqual(message.arguments, ["3", "2 GB"])
        XCTAssertEqual(L10n.render("{1}: {0}", arguments: ["GPT-5.6", "Model"]), "Model: GPT-5.6")
        XCTAssertEqual(L10n.render("{0} / {1}", arguments: ["{1}", "safe"]), "{1} / safe")
    }

    func testEveryCatalogEntryHasCompleteLanguagesAndPlaceholders() {
        XCTAssertGreaterThan(L10n.catalog.count, 600)
        for (source, translations) in L10n.catalog {
            for language in AppLanguage.translatedLanguages {
                let value = translations[language.rawValue]
                XCTAssertNotNil(value, "\(language): \(source)")
                XCTAssertFalse(value?.isEmpty ?? true, source)
                XCTAssertEqual(L10n.placeholders(in: source), L10n.placeholders(in: value ?? ""), source)
            }
        }
    }

    func testEnglishArabicAndTraditionalCoreLabels() {
        XCTAssertEqual(L10n.lookup("24 小时花费", language: .english), "Cost · Last 24h")
        XCTAssertNotEqual(L10n.lookup("查看说明", language: .arabic), "查看说明")
        XCTAssertEqual(L10n.lookup("语言", language: .traditionalChinese), "語言")
    }

    func testReimportIdentityDoesNotDependOnDisplayLanguage() throws {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AppLanguage.preferenceKey)
        defer {
            if let saved { defaults.set(saved, forKey: AppLanguage.preferenceKey) }
            else { defaults.removeObject(forKey: AppLanguage.preferenceKey) }
        }
        let data = Data(#"{"timestamp":"2026-09-22T00:00:00Z","model":"test-model","input":10,"output":5}"#.utf8)
        defaults.set("zh-Hans", forKey: AppLanguage.preferenceKey)
        let chinese = try XCTUnwrap(UsageImport.parse(data, format: "jsonl", tool: .cursor).first)
        defaults.set("ar", forKey: AppLanguage.preferenceKey)
        let arabic = try XCTUnwrap(UsageImport.parse(data, format: "jsonl", tool: .cursor).first)
        XCTAssertEqual(chinese.id, arabic.id)
        XCTAssertEqual(chinese.project, arabic.project)
    }
}

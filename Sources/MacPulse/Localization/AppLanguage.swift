import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case arabic = "ar"
    var id: String { rawValue }
    var nativeName: String {
        switch self {
        case .system: return L10n.text("跟随系统")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .arabic: return "العربية"
        }
    }
    var isRightToLeft: Bool { self == .arabic }
    static let preferenceKey = "tokenmini.language"
    static let translatedLanguages: [Self] = [.english, .traditionalChinese, .japanese, .korean, .arabic]

    // Read the system domain directly: Foundation may cache the app's AppleLanguages
    // override until relaunch, even after the user chooses “Follow System”.
    static var systemPreferredLanguages: [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
            ?? Locale.preferredLanguages
    }

    static func resolve(_ selection: Self, preferred: [String] = systemPreferredLanguages) -> Self {
        guard selection == .system else { return selection }
        for raw in preferred {
            let code = raw.lowercased().replacingOccurrences(of: "_", with: "-")
            if code.hasPrefix("zh") {
                return code.contains("hant") || code.hasPrefix("zh-tw") || code.hasPrefix("zh-hk") || code.hasPrefix("zh-mo")
                    ? .traditionalChinese : .simplifiedChinese
            }
            if code == "en" || code.hasPrefix("en-") { return .english }
            if code == "ja" || code.hasPrefix("ja-") { return .japanese }
            if code == "ko" || code.hasPrefix("ko-") { return .korean }
            if code == "ar" || code.hasPrefix("ar-") { return .arabic }
        }
        return .english
    }

    static var current: Self {
        resolve(Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "system") ?? .system)
    }

    /// Keep regional number/date conventions separate from the selected UI language.
    var locale: Locale {
        let region = Locale.current.region?.identifier ?? "US"
        return Locale(identifier: rawValue + "-" + region)
    }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()
    @Published var selection: AppLanguage {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: AppLanguage.preferenceKey)
            if selection == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([selection.rawValue], forKey: "AppleLanguages")
            }
        }
    }
    private init() {
        selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLanguage.preferenceKey) ?? "system") ?? .system
    }
    var resolved: AppLanguage { AppLanguage.resolve(selection) }
}

private struct LocalizedInterface: ViewModifier {
    @ObservedObject private var language = AppLanguageStore.shared
    func body(content: Content) -> some View {
        content
            .environment(\.locale, language.resolved.locale)
            .environment(\.layoutDirection, language.resolved.isRightToLeft ? .rightToLeft : .leftToRight)
            .id(language.resolved)
    }
}

extension View {
    func localizedInterface() -> some View { modifier(LocalizedInterface()) }
}

// Letter spacing and monospace fallback can split Arabic's connected glyphs.
extension Text {
    func localizedTracking(_ amount: CGFloat) -> Text {
        AppLanguage.current.isRightToLeft ? self : tracking(amount)
    }
    func localizedKerning(_ amount: CGFloat) -> Text {
        AppLanguage.current.isRightToLeft ? self : kerning(amount)
    }
}

extension AppLanguage {
    static var monospacedDesign: Font.Design {
        current.isRightToLeft ? .default : .monospaced
    }
}

import Foundation

enum L10n {
    struct LanguageOption: Identifiable {
        let code: String
        let title: String
        var id: String { code }
    }

    static let languageOverrideKey = "app_language_override"
    static let systemLanguageCode = "system"

    private static let supportedLanguageCodes = ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"]
    private static let fallbackLanguageCode = "en"

    static let languageOptions: [LanguageOption] = [
        LanguageOption(code: systemLanguageCode, title: "System"),
        LanguageOption(code: "en", title: "English"),
        LanguageOption(code: "zh-Hant", title: "繁體中文"),
        LanguageOption(code: "zh-Hans", title: "简体中文"),
        LanguageOption(code: "fr", title: "Français"),
        LanguageOption(code: "es", title: "Español"),
        LanguageOption(code: "ja", title: "日本語"),
        LanguageOption(code: "ko", title: "한국어")
    ]

    private static var selectedOverrideLanguageCode: String? {
        guard let value = UserDefaults.standard.string(forKey: languageOverrideKey),
              value != systemLanguageCode,
              supportedLanguageCodes.contains(value)
        else {
            return nil
        }
        return value
    }

    private static var resolvedLanguageCode: String {
        if let selectedOverrideLanguageCode {
            return selectedOverrideLanguageCode
        }

        for preferred in Locale.preferredLanguages {
            let lowercased = preferred.lowercased()
            if lowercased.hasPrefix("zh-hant") || lowercased.hasPrefix("zh-tw") || lowercased.hasPrefix("zh-hk") {
                return "zh-Hant"
            }
            if lowercased.hasPrefix("zh-hans") || lowercased.hasPrefix("zh-cn") || lowercased.hasPrefix("zh-sg") {
                return "zh-Hans"
            }

            let locale = Locale(identifier: preferred)
            if let languageCode = locale.language.languageCode?.identifier,
               supportedLanguageCodes.contains(languageCode) {
                return languageCode
            }
        }
        return fallbackLanguageCode
    }

    private static func localizedBundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    static func text(_ key: String) -> String {
        if let preferredBundle = localizedBundle(for: resolvedLanguageCode) {
            let localized = preferredBundle.localizedString(forKey: key, value: nil, table: nil)
            if localized != key {
                return localized
            }
        }

        if let fallbackBundle = localizedBundle(for: fallbackLanguageCode) {
            let fallback = fallbackBundle.localizedString(forKey: key, value: nil, table: nil)
            if fallback != key {
                return fallback
            }
        }

        return key
    }

    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = text(key)
        return String(format: format, locale: Locale(identifier: resolvedLanguageCode), arguments: arguments)
    }

    static func locale(for overrideCode: String? = nil) -> Locale {
        if let overrideCode, overrideCode != systemLanguageCode, supportedLanguageCodes.contains(overrideCode) {
            return Locale(identifier: overrideCode)
        }

        if let selectedOverrideLanguageCode {
            return Locale(identifier: selectedOverrideLanguageCode)
        }

        return Locale.autoupdatingCurrent
    }
}

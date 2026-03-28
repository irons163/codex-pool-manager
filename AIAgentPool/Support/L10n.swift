import Foundation

enum L10n {
    private static let supportedLanguageCodes = ["en", "zh-Hant", "zh-Hans", "fr", "es", "ja", "ko"]
    private static let fallbackLanguageCode = "en"

    private static var resolvedLanguageCode: String {
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
}

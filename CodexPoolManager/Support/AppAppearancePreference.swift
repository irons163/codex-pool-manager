import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    static let storageKey = "app_appearance_override"

    var id: String { rawValue }

    static func normalizedRawValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = AppAppearancePreference(rawValue: trimmed) {
            return exact.rawValue
        }

        switch trimmed.lowercased() {
        case "system", "follow system":
            return AppAppearancePreference.system.rawValue
        case "dark":
            return AppAppearancePreference.dark.rawValue
        case "light":
            return AppAppearancePreference.light.rawValue
        default:
            return AppAppearancePreference.system.rawValue
        }
    }

    static func preferredColorScheme(for rawValue: String) -> ColorScheme? {
        switch AppAppearancePreference(rawValue: rawValue) ?? .system {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

import SwiftUI

enum AppAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    static let storageKey = "app_appearance_override"

    var id: String { rawValue }

    static func normalizedRawValue(_ rawValue: String) -> String {
        AppAppearancePreference(rawValue: rawValue)?.rawValue ?? AppAppearancePreference.system.rawValue
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

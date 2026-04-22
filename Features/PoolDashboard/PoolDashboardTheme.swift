import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum PoolDashboardTheme {
    private static var forcedLightPalette: Bool?

    private static var systemPrefersDarkMode: Bool {
        #if canImport(AppKit)
        let style = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? ""
        return style.caseInsensitiveCompare("Dark") == .orderedSame
        #else
        return false
        #endif
    }

    static var isLightPalette: Bool {
        if let forcedLightPalette {
            return forcedLightPalette
        }
        let rawValue = UserDefaults.standard.string(forKey: AppAppearancePreference.storageKey) ?? ""
        let normalized = AppAppearancePreference.normalizedRawValue(rawValue)
        switch AppAppearancePreference(rawValue: normalized) ?? .system {
        case .light:
            return true
        case .dark:
            return false
        case .system:
            return !systemPrefersDarkMode
        }
    }

    @discardableResult
    static func forcePalette(isLight: Bool) -> Bool {
        let changed = forcedLightPalette != isLight
        forcedLightPalette = isLight
        return changed
    }

    static var canvasTop: Color {
        isLightPalette
            ? Color(red: 0.995, green: 0.985, blue: 0.952)
            : Color(red: 0.03, green: 0.08, blue: 0.16)
    }

    static var canvasBottom: Color {
        isLightPalette
            ? Color(red: 0.982, green: 0.962, blue: 0.905)
            : Color(red: 0.02, green: 0.03, blue: 0.06)
    }

    static var glowA: Color {
        isLightPalette
            ? Color(red: 0.27, green: 0.57, blue: 0.94)
            : Color(red: 0.20, green: 0.50, blue: 0.95)
    }

    static var glowB: Color {
        isLightPalette
            ? Color(red: 0.58, green: 0.74, blue: 0.56)
            : Color(red: 0.08, green: 0.78, blue: 0.68)
    }

    static var panelFill: Color {
        isLightPalette ? Color.white.opacity(0.94) : Color.white.opacity(0.07)
    }

    static var panelStroke: Color {
        isLightPalette ? Color(red: 0.67, green: 0.57, blue: 0.45).opacity(0.20) : Color.white.opacity(0.14)
    }

    static var panelInnerStroke: Color {
        isLightPalette ? Color(red: 0.67, green: 0.57, blue: 0.45).opacity(0.12) : Color.white.opacity(0.08)
    }

    static let panelBorderWidth: CGFloat = 1
    static let tileBorderWidth: CGFloat = 1
    static var panelMutedFill: Color {
        isLightPalette ? Color.white.opacity(0.92) : Color.white.opacity(0.04)
    }

    static var panelStrongFill: Color {
        isLightPalette ? Color.white.opacity(0.97) : Color.white.opacity(0.11)
    }

    // Opaque fill for modal dialogs to prevent background text bleeding through.
    static var modalSolidFill: Color {
        isLightPalette
            ? Color(red: 0.985, green: 0.975, blue: 0.94)
            : Color(red: 0.09, green: 0.13, blue: 0.20)
    }

    static let panelTopHighlightOpacity: Double = 0.09
    static let panelBottomShadeOpacity: Double = 0.14
    static let panelSpecularOpacity: Double = 0.22
    static var textPrimary: Color {
        isLightPalette ? Color(red: 0.17, green: 0.14, blue: 0.10) : Color.white
    }

    static var textSecondary: Color {
        isLightPalette ? Color(red: 0.22, green: 0.18, blue: 0.13).opacity(0.94) : Color.white.opacity(0.78)
    }

    static var textMuted: Color {
        isLightPalette ? Color(red: 0.28, green: 0.23, blue: 0.17).opacity(0.86) : Color.white.opacity(0.62)
    }

    static let groupLabelOpacity: Double = 0.92
    static var success: Color { Color(red: 0.22, green: 0.84, blue: 0.66) }
    static var warning: Color { Color(red: 0.98, green: 0.64, blue: 0.26) }
    static var danger: Color { Color(red: 0.95, green: 0.37, blue: 0.40) }

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                canvasTop,
                canvasBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glowAOpacity: Double { isLightPalette ? 0.045 : 0.30 }
    static var glowBOpacity: Double { isLightPalette ? 0.03 : 0.22 }
    static var vignetteEndColor: Color {
        isLightPalette ? Color(red: 0.52, green: 0.41, blue: 0.27).opacity(0.015) : Color.black.opacity(0.24)
    }
    static var sectionCardShadowColor: Color { isLightPalette ? Color.black.opacity(0.06) : Color.clear }
    static var sectionCardShadowRadius: CGFloat { isLightPalette ? 10 : 0 }
    static var sectionCardShadowYOffset: CGFloat { isLightPalette ? 2 : 0 }
    static var chromeStrongOpacity: Double { isLightPalette ? 0.90 : 0.78 }
    static var chromeBaseOpacity: Double { isLightPalette ? 0.82 : 0.52 }
    static var chromeSidebarOpacity: Double { isLightPalette ? 0.86 : 0.72 }
    static var chromeFooterOpacity: Double { isLightPalette ? 0.88 : 0.82 }

    static let sectionSpacing: CGFloat = 26
    static let sectionHeaderSpacing: CGFloat = 8
    static let panelPadding: CGFloat = 26
    static let panelCornerRadius: CGFloat = 20
    static let tileCornerRadius: CGFloat = 14
    static let controlCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 999
    static let sectionCardPadding: CGFloat = 12
    static let sectionCardInnerPadding: CGFloat = 10
    static let editorCornerRadius: CGFloat = 10
    static let calloutCornerRadius: CGFloat = 10
    static let calloutBorderWidth: CGFloat = 1
    static let infoCardCornerRadius: CGFloat = 11
    static let glowLargeSize: CGFloat = 420
    static let glowMediumSize: CGFloat = 360
    static let glowLargeBlur: CGFloat = 70
    static let glowMediumBlur: CGFloat = 60
    static let titleFont = Font.system(size: 34, weight: .bold, design: .rounded)
    static let subtitleFont = Font.system(size: 13, weight: .medium, design: .rounded)
    static let metadataFont = Font.system(size: 12, weight: .regular, design: .rounded)
    static let metadataTracking: CGFloat = 1.2

    static let contentWidth: CGFloat = 1180
    static let minWidth: CGFloat = 860
    static let minHeight: CGFloat = 680
    static let subtitleReadableWidth: CGFloat = 660
    static let standardAnimationDuration: Double = 0.24
    static let fastAnimationDuration: Double = 0.18
    static let listRowVerticalInset: CGFloat = 3
    static let scrollHorizontalPadding: CGFloat = 14
    static let pillVerticalPadding: CGFloat = 5
    static let pillHorizontalPadding: CGFloat = 10
    static let actionRowSpacing: CGFloat = 10
    static let compactFieldSpacing: CGFloat = 8
    static let dashboardVerticalPadding: CGFloat = 10
    static let toolbarPadding: CGFloat = 13
    static let syncBadgeMaxWidth: CGFloat = 360
    static let localBadgeMaxWidth: CGFloat = 380
    static let toolbarShadowRadius: CGFloat = 10
    static let panelShadowRadius: CGFloat = 28
    static let panelShadowYOffset: CGFloat = 16
    static let panelGlowShadowRadius: CGFloat = 20
    static let headerAccentRuleWidth: CGFloat = 180
    static let tileShadowRadius: CGFloat = 10
    static let cardShadowYOffset: CGFloat = 6
    static let headerTileVerticalPadding: CGFloat = 11
    static let headerTileHorizontalPadding: CGFloat = 12
    static let usageListMinHeight: CGFloat = 260
    static let activityListMinHeight: CGFloat = 200
    static let backupEditorMinHeight: CGFloat = 190
    static let debugEditorMinHeight: CGFloat = 140
    static let accountAddRowSpacing: CGFloat = 14
    static let localOAuthPanelSpacing: CGFloat = 14
    static let strategyPanelSpacing: CGFloat = 16
    static let oauthPanelSpacing: CGFloat = 16
    static let workspaceSidebarWidth: CGFloat = 240
    static let workspaceSidebarPadding: CGFloat = 12
    static let workspaceSidebarItemCornerRadius: CGFloat = 11
    static let workspaceContextWidth: CGFloat = 480
}

private struct SectionCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(PoolDashboardTheme.sectionCardPadding)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.isLightPalette ? Color.white.opacity(0.90) : PoolDashboardTheme.panelFill.opacity(0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(PoolDashboardTheme.isLightPalette ? 1 : 0.7), lineWidth: 0.8)
                    )
                    .shadow(
                        color: PoolDashboardTheme.sectionCardShadowColor,
                        radius: PoolDashboardTheme.sectionCardShadowRadius,
                        y: PoolDashboardTheme.sectionCardShadowYOffset
                    )
            )
    }
}

extension View {
    func sectionCardStyle() -> some View {
        modifier(SectionCardStyle())
    }

    func statusBadge(tone: Color) -> some View {
        self
            .font(.footnote.weight(.medium))
            .foregroundStyle(PoolDashboardTheme.textPrimary)
            .padding(.vertical, PoolDashboardTheme.pillVerticalPadding)
            .padding(.horizontal, PoolDashboardTheme.pillHorizontalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(tone)
            )
    }

    func dashboardInputFieldStyle() -> some View {
        self
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 13, weight: .medium, design: .rounded))
    }

    func calloutCard(fill: Color, border: Color = .clear) -> some View {
        self
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.calloutCornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.calloutCornerRadius, style: .continuous)
                            .stroke(border, lineWidth: PoolDashboardTheme.calloutBorderWidth)
                    )
            )
    }

    func dashboardInfoCard() -> some View {
        self
            .padding(PoolDashboardTheme.sectionCardInnerPadding)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.infoCardCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.isLightPalette ? Color.white.opacity(0.94) : PoolDashboardTheme.panelMutedFill.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.infoCardCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(PoolDashboardTheme.isLightPalette ? 0.9 : 0.65), lineWidth: 0.8)
                    )
                    .shadow(
                        color: PoolDashboardTheme.isLightPalette ? Color.black.opacity(0.04) : .clear,
                        radius: PoolDashboardTheme.isLightPalette ? 6 : 0,
                        y: PoolDashboardTheme.isLightPalette ? 1 : 0
                    )
            )
    }

    func dashboardListRowCard() -> some View {
        self
            .padding(.vertical, PoolDashboardTheme.listRowVerticalInset)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.isLightPalette ? Color.white.opacity(0.96) : PoolDashboardTheme.panelMutedFill.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(PoolDashboardTheme.isLightPalette ? 0.85 : 0.9), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.glowA.opacity(PoolDashboardTheme.isLightPalette ? 0.08 : 0.15), lineWidth: 0.6)
                            .padding(1)
                    )
                    .shadow(
                        color: PoolDashboardTheme.isLightPalette ? Color.black.opacity(0.035) : .clear,
                        radius: PoolDashboardTheme.isLightPalette ? 5 : 0,
                        y: PoolDashboardTheme.isLightPalette ? 1 : 0
                    )
            )
    }
}

struct DashboardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textPrimary.opacity(PoolDashboardTheme.groupLabelOpacity))
            configuration.content
        }
    }
}

struct DashboardPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(PoolDashboardTheme.glowA.opacity(configuration.isPressed ? 0.72 : 0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.28), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DashboardWarningButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .background(
                Capsule(style: .continuous)
                    .fill(PoolDashboardTheme.warning.opacity(configuration.isPressed ? 0.68 : 0.88))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct DashboardSubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(PoolDashboardTheme.panelMutedFill.opacity(configuration.isPressed ? 0.78 : 1))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
            )
            .foregroundStyle(PoolDashboardTheme.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

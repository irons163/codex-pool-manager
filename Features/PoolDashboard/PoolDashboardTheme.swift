import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum PoolDashboardTheme {
    private static var prefersLightPalette: Bool {
        switch AppAppearancePreference(rawValue: UserDefaults.standard.string(forKey: AppAppearancePreference.storageKey) ?? "") ?? .system {
        case .light:
            return true
        case .dark:
            return false
        case .system:
            #if canImport(AppKit)
            if let match = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) {
                return match == .aqua
            }
            #endif
            return false
        }
    }

    static var canvasTop: Color {
        prefersLightPalette
            ? Color(red: 0.97, green: 0.94, blue: 0.86)
            : Color(red: 0.03, green: 0.08, blue: 0.16)
    }

    static var canvasBottom: Color {
        prefersLightPalette
            ? Color(red: 0.92, green: 0.86, blue: 0.75)
            : Color(red: 0.02, green: 0.03, blue: 0.06)
    }

    static var glowA: Color {
        prefersLightPalette
            ? Color(red: 0.20, green: 0.50, blue: 0.95)
            : Color(red: 0.20, green: 0.50, blue: 0.95)
    }

    static var glowB: Color {
        prefersLightPalette
            ? Color(red: 0.35, green: 0.67, blue: 0.56)
            : Color(red: 0.08, green: 0.78, blue: 0.68)
    }

    static var panelFill: Color {
        prefersLightPalette ? Color.black.opacity(0.055) : Color.white.opacity(0.07)
    }

    static var panelStroke: Color {
        prefersLightPalette ? Color.black.opacity(0.16) : Color.white.opacity(0.14)
    }

    static var panelInnerStroke: Color {
        prefersLightPalette ? Color.black.opacity(0.10) : Color.white.opacity(0.08)
    }

    static let panelBorderWidth: CGFloat = 1
    static let tileBorderWidth: CGFloat = 1
    static var panelMutedFill: Color {
        prefersLightPalette ? Color.black.opacity(0.042) : Color.white.opacity(0.04)
    }

    static var panelStrongFill: Color {
        prefersLightPalette ? Color.black.opacity(0.085) : Color.white.opacity(0.11)
    }

    static let panelTopHighlightOpacity: Double = 0.09
    static let panelBottomShadeOpacity: Double = 0.14
    static let panelSpecularOpacity: Double = 0.22
    static var textPrimary: Color {
        prefersLightPalette ? Color(red: 0.14, green: 0.12, blue: 0.09) : Color.white
    }

    static var textSecondary: Color {
        prefersLightPalette ? Color(red: 0.22, green: 0.18, blue: 0.14).opacity(0.82) : Color.white.opacity(0.78)
    }

    static var textMuted: Color {
        prefersLightPalette ? Color(red: 0.25, green: 0.22, blue: 0.18).opacity(0.68) : Color.white.opacity(0.62)
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

    static var glowAOpacity: Double { prefersLightPalette ? 0.16 : 0.30 }
    static var glowBOpacity: Double { prefersLightPalette ? 0.12 : 0.22 }
    static var vignetteEndColor: Color {
        prefersLightPalette ? Color(red: 0.42, green: 0.32, blue: 0.20).opacity(0.10) : Color.black.opacity(0.24)
    }

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
                    .fill(PoolDashboardTheme.panelFill.opacity(0.34))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.7), lineWidth: 0.8)
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
                    .fill(PoolDashboardTheme.panelMutedFill.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.infoCardCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.65), lineWidth: 0.8)
                    )
            )
    }

    func dashboardListRowCard() -> some View {
        self
            .padding(.vertical, PoolDashboardTheme.listRowVerticalInset)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelMutedFill.opacity(0.78))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.9), lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.glowA.opacity(0.15), lineWidth: 0.6)
                            .padding(1)
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

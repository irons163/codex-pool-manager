import SwiftUI

struct PanelSectionHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .tracking(PoolDashboardTheme.metadataTracking)
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)
        }
    }
}

struct PanelStatusCalloutView: View {
    enum Tone {
        case info
        case success
        case warning
        case danger

        var fill: Color {
            switch self {
            case .info: PoolDashboardTheme.panelMutedFill
            case .success: PoolDashboardTheme.success.opacity(0.20)
            case .warning: PoolDashboardTheme.warning.opacity(0.18)
            case .danger: PoolDashboardTheme.danger.opacity(0.18)
            }
        }

        var border: Color {
            switch self {
            case .info: PoolDashboardTheme.panelInnerStroke
            case .success: PoolDashboardTheme.success.opacity(0.40)
            case .warning: PoolDashboardTheme.warning.opacity(0.36)
            case .danger: PoolDashboardTheme.danger.opacity(0.36)
            }
        }

        var foreground: Color {
            switch self {
            case .info: PoolDashboardTheme.textSecondary
            case .success: PoolDashboardTheme.success
            case .warning: PoolDashboardTheme.warning
            case .danger: PoolDashboardTheme.danger
            }
        }
    }

    let message: String
    let tone: Tone

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(tone.foreground)
            .calloutCard(fill: tone.fill, border: tone.border)
    }
}

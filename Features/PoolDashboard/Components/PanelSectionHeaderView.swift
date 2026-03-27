import SwiftUI

struct PanelSectionHeaderView: View {
    let title: String
    let subtitle: String
    let symbolName: String?

    init(title: String, subtitle: String, symbolName: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.symbolName = symbolName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PoolDashboardTheme.sectionHeaderSpacing) {
            HStack(spacing: 8) {
                if let symbolName {
                    Image(systemName: symbolName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
                Text(title.uppercased())
                    .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                    .tracking(PoolDashboardTheme.metadataTracking)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                Capsule(style: .continuous)
                    .fill(PoolDashboardTheme.panelInnerStroke)
                    .frame(height: 1)
            }
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

        var icon: String {
            switch self {
            case .info: "info.circle"
            case .success: "checkmark.circle"
            case .warning: "exclamationmark.triangle"
            case .danger: "xmark.octagon"
            }
        }
    }

    let message: String
    let title: String?
    let tone: Tone

    init(message: String, title: String? = nil, tone: Tone) {
        self.message = message
        self.title = title
        self.tone = tone
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: tone.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                if let title {
                    Text(title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(tone.foreground)
                }
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(tone.foreground)
            }
        }
        .calloutCard(fill: tone.fill, border: tone.border)
    }
}

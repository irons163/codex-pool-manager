import SwiftUI

struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(PoolDashboardTheme.panelPadding)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelStrongFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(PoolDashboardTheme.panelTopHighlightOpacity), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelStroke, lineWidth: PoolDashboardTheme.panelBorderWidth)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius - 1, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: PoolDashboardTheme.panelBorderWidth)
                            .padding(1)
                    )
            )
            .shadow(
                color: .black.opacity(0.34),
                radius: PoolDashboardTheme.panelShadowRadius,
                x: 0,
                y: PoolDashboardTheme.panelShadowYOffset
            )
            .shadow(color: PoolDashboardTheme.glowA.opacity(0.12), radius: PoolDashboardTheme.panelGlowShadowRadius, x: -6, y: -8)
    }
}

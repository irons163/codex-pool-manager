import SwiftUI

struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(PoolDashboardTheme.panelPadding)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.08), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .center
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelStroke, lineWidth: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.panelCornerRadius - 1, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            .padding(1)
                    )
            )
            .shadow(color: .black.opacity(0.30), radius: 24, x: 0, y: 14)
    }
}

import SwiftUI

struct PanelAdaptiveActionRowView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
                content
            }
            VStack(alignment: .leading, spacing: PoolDashboardTheme.actionRowSpacing) {
                content
            }
        }
    }
}

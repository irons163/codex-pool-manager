import SwiftUI

struct SectionCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                    .fill(PoolDashboardTheme.panelFill.opacity(0.58))
                    .overlay(
                        RoundedRectangle(cornerRadius: PoolDashboardTheme.tileCornerRadius, style: .continuous)
                            .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                    )
            )
    }
}

extension View {
    func sectionCardStyle() -> some View {
        modifier(SectionCardStyle())
    }
}

import SwiftUI

enum PoolDashboardTheme {
    static let canvasTop = Color(red: 0.03, green: 0.08, blue: 0.16)
    static let canvasBottom = Color(red: 0.02, green: 0.03, blue: 0.06)
    static let glowA = Color(red: 0.20, green: 0.50, blue: 0.95)
    static let glowB = Color(red: 0.08, green: 0.78, blue: 0.68)
    static let panelFill = Color.white.opacity(0.07)
    static let panelStroke = Color.white.opacity(0.14)
    static let panelInnerStroke = Color.white.opacity(0.08)

    static let backgroundGradient = LinearGradient(
        colors: [
            canvasTop,
            canvasBottom
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let sectionSpacing: CGFloat = 20
    static let panelPadding: CGFloat = 24
    static let panelCornerRadius: CGFloat = 20
    static let tileCornerRadius: CGFloat = 14
    static let glowLargeSize: CGFloat = 420
    static let glowMediumSize: CGFloat = 360
    static let glowLargeBlur: CGFloat = 70
    static let glowMediumBlur: CGFloat = 60
    static let titleFont = Font.system(size: 34, weight: .bold, design: .rounded)
    static let subtitleFont = Font.system(size: 13, weight: .medium, design: .rounded)
    static let metadataFont = Font.system(size: 12, weight: .regular, design: .rounded)

    static let contentWidth: CGFloat = 1180
    static let minWidth: CGFloat = 860
    static let minHeight: CGFloat = 640
}

private struct SectionCardStyle: ViewModifier {
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

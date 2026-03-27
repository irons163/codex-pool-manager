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

    static let contentWidth: CGFloat = 1180
    static let minWidth: CGFloat = 860
    static let minHeight: CGFloat = 620
}

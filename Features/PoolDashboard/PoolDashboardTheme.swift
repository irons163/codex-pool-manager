import SwiftUI

enum PoolDashboardTheme {
    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.10, blue: 0.18),
            Color(red: 0.05, green: 0.07, blue: 0.10)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let contentWidth: CGFloat = 1160
    static let minWidth: CGFloat = 900
    static let minHeight: CGFloat = 620
}

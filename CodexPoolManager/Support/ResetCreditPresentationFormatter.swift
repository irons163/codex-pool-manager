import Foundation

struct ResetCreditPresentation: Equatable {
    let detailLines: [String]
    let compactDetailLine: String
    let detailText: String
    let noteText: String?
    let accessibilityLabel: String
}

enum ResetCreditPresentationFormatter {
    static func presentation(for account: AgentAccount) -> ResetCreditPresentation? {
        guard account.supportsCodexUsageSync,
              let count = account.rateLimitResetCreditsAvailableCount,
              count > 0
        else {
            return nil
        }

        let expiries = resetCreditExpiries(for: account, count: count)
        guard let expiry = expiries.first else {
            return nil
        }

        let usesAPIExpiries = account.rateLimitResetCreditExpirySource == .api
        let detailFormatKey = usesAPIExpiries
            ? "menu_bar.reset_credit.actual_detail_format"
            : "menu_bar.reset_credit.detail_format"
        let accessibilityFormatKey = usesAPIExpiries
            ? "menu_bar.reset_credit.actual_accessibility_format"
            : "menu_bar.reset_credit.accessibility_format"
        let fullDate = preciseExpiryText(for: expiry)
        let baseDetailLines = L10n.text(detailFormatKey, count, fullDate)
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let perCreditExpiryLines = expiries.enumerated().map { index, expiry in
            L10n.text(
                "menu_bar.reset_credit.per_credit_expiry_format",
                index + 1,
                preciseExpiryText(for: expiry)
            )
        }
        let visibleDetailLines = Array(baseDetailLines.prefix(1)) + perCreditExpiryLines
        let fallbackDetailText = L10n.text(detailFormatKey, count, fullDate)
        let visibleDetailText = visibleDetailLines.isEmpty
            ? fallbackDetailText
            : visibleDetailLines.joined(separator: "\n")
        let noteText = baseDetailLines.dropFirst(2).joined(separator: "\n")
        let compactExpiryText = expiries
            .map { expiry in shortExpiryText(for: expiry) }
            .joined(separator: ", ")
        let countDetailLine = baseDetailLines.first ?? fallbackDetailText
        let compactDetailLine = compactExpiryText.isEmpty
            ? countDetailLine
            : "\(countDetailLine) · \(compactExpiryText)"

        return ResetCreditPresentation(
            detailLines: visibleDetailLines.isEmpty ? [fallbackDetailText] : visibleDetailLines,
            compactDetailLine: compactDetailLine,
            detailText: visibleDetailText,
            noteText: noteText.isEmpty ? nil : noteText,
            accessibilityLabel: L10n.text(accessibilityFormatKey, count, fullDate)
        )
    }

    private static func resetCreditExpiries(for account: AgentAccount, count: Int) -> [Date] {
        guard count > 0 else { return [] }

        var expiries = Array(account.rateLimitResetCreditEstimatedExpiries.prefix(count))
        if expiries.isEmpty,
           let legacyExpiry = account.rateLimitResetCreditsEstimatedExpiresAt {
            expiries = Array(repeating: legacyExpiry, count: count)
        } else if expiries.count < count,
                  let lastExpiry = expiries.last ?? account.rateLimitResetCreditsEstimatedExpiresAt {
            expiries.append(contentsOf: Array(repeating: lastExpiry, count: count - expiries.count))
        }
        return expiries
    }

    private static func preciseExpiryText(for expiry: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/M/d HH:mm:ss"
        return "\(formatter.string(from: expiry)) \(gmtOffsetText(for: formatter.timeZone, at: expiry))"
    }

    private static func shortExpiryText(for expiry: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale()
        formatter.timeZone = .current
        formatter.dateFormat = "M/d"
        return formatter.string(from: expiry)
    }

    private static func gmtOffsetText(for timeZone: TimeZone, at date: Date) -> String {
        let secondsFromGMT = timeZone.secondsFromGMT(for: date)
        let sign = secondsFromGMT >= 0 ? "+" : "-"
        let absoluteSeconds = abs(secondsFromGMT)
        let hours = absoluteSeconds / 3_600
        let minutes = (absoluteSeconds % 3_600) / 60

        if minutes == 0 {
            return "GMT\(sign)\(hours)"
        }

        return String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
}

import Foundation

struct UsageAnalyticsRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let accountKey: String
    let weeklyDeltaPercent: Int
    let fiveHourDeltaPercent: Int

    init(
        id: UUID = UUID(),
        timestamp: Date,
        accountKey: String,
        weeklyDeltaPercent: Int,
        fiveHourDeltaPercent: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.accountKey = accountKey
        self.weeklyDeltaPercent = weeklyDeltaPercent
        self.fiveHourDeltaPercent = fiveHourDeltaPercent
    }
}

struct UsageAnalyticsAccountSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let accountKey: String
    let lastWeeklyPercent: Int
    let lastFiveHourPercent: Int?
    let lastSeenAt: Date

    init(
        id: UUID = UUID(),
        accountKey: String,
        lastWeeklyPercent: Int,
        lastFiveHourPercent: Int?,
        lastSeenAt: Date
    ) {
        self.id = id
        self.accountKey = accountKey
        self.lastWeeklyPercent = lastWeeklyPercent
        self.lastFiveHourPercent = lastFiveHourPercent
        self.lastSeenAt = lastSeenAt
    }
}

struct UsageAnalyticsState: Codable, Equatable {
    var records: [UsageAnalyticsRecord] = []
    var snapshots: [UsageAnalyticsAccountSnapshot] = []
    var lastUpdatedAt: Date? = nil
}

struct UsageAnalyticsDailyTotal: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let totalWeeklyPercent: Int

    init(date: Date, totalWeeklyPercent: Int) {
        self.id = UUID()
        self.date = date
        self.totalWeeklyPercent = totalWeeklyPercent
    }
}

struct UsageAnalyticsWeeklyTotal: Identifiable, Equatable {
    let id: UUID
    let weekStartDate: Date
    let totalWeeklyPercent: Int

    init(weekStartDate: Date, totalWeeklyPercent: Int) {
        self.id = UUID()
        self.weekStartDate = weekStartDate
        self.totalWeeklyPercent = totalWeeklyPercent
    }
}

struct UsageAnalyticsSummary: Equatable {
    let todayWeeklyPercent: Int
    let weekWeeklyPercent: Int
    let todayFiveHourPercent: Int
    let weekFiveHourPercent: Int
    let peakHour: Int?
    let peakWeekday: Int?
    let topAccountKey: String?
    let topAccountWeeklyPercent: Int
}

enum UsageAnalyticsEngine {
    static let retentionDays: Int = 45

    static func update(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageAnalyticsState {
        let trimmedRecords = trim(records: state.records, now: now, calendar: calendar)
        let snapshotsByKey = state.snapshots.reduce(into: [String: UsageAnalyticsAccountSnapshot]()) { partial, snapshot in
            partial[snapshot.accountKey] = snapshot
        }
        let deduplicatedAccounts = deduplicatedAccountsByKey(accounts)
        var updatedSnapshots: [UsageAnalyticsAccountSnapshot] = []
        var newRecords: [UsageAnalyticsRecord] = []

        for account in deduplicatedAccounts {
            let accountKey = account.deduplicationKey
            let weeklyPercent = percentUsage(for: account)
            let fiveHourPercent = account.primaryUsagePercent

            if let snapshot = snapshotsByKey[accountKey] {
                let weeklyDelta = deltaPercent(current: weeklyPercent, previous: snapshot.lastWeeklyPercent)
                let fiveHourDelta = deltaPercent(current: fiveHourPercent, previous: snapshot.lastFiveHourPercent)

                if weeklyDelta > 0 || fiveHourDelta > 0 {
                    newRecords.append(
                        UsageAnalyticsRecord(
                            timestamp: now,
                            accountKey: accountKey,
                            weeklyDeltaPercent: weeklyDelta,
                            fiveHourDeltaPercent: fiveHourDelta
                        )
                    )
                }
            }

            updatedSnapshots.append(
                UsageAnalyticsAccountSnapshot(
                    accountKey: accountKey,
                    lastWeeklyPercent: weeklyPercent,
                    lastFiveHourPercent: fiveHourPercent,
                    lastSeenAt: now
                )
            )
        }

        var mergedRecords = trimmedRecords + newRecords
        mergedRecords.sort { $0.timestamp > $1.timestamp }

        var updatedState = UsageAnalyticsState(
            records: mergedRecords,
            snapshots: updatedSnapshots,
            lastUpdatedAt: now
        )
        updatedState.records = trim(records: updatedState.records, now: now, calendar: calendar)
        return updatedState
    }

    static func seed(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        now: Date
    ) -> UsageAnalyticsState {
        let deduplicatedAccounts = deduplicatedAccountsByKey(accounts)
        return UsageAnalyticsState(
            records: state.records,
            snapshots: deduplicatedAccounts.map { account in
                UsageAnalyticsAccountSnapshot(
                    accountKey: account.deduplicationKey,
                    lastWeeklyPercent: percentUsage(for: account),
                    lastFiveHourPercent: account.primaryUsagePercent,
                    lastSeenAt: now
                )
            },
            lastUpdatedAt: now
        )
    }

    static func summary(
        for state: UsageAnalyticsState,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageAnalyticsSummary {
        let todayStart = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart) else {
            return UsageAnalyticsSummary(
                todayWeeklyPercent: 0,
                weekWeeklyPercent: 0,
                todayFiveHourPercent: 0,
                weekFiveHourPercent: 0,
                peakHour: nil,
                peakWeekday: nil,
                topAccountKey: nil,
                topAccountWeeklyPercent: 0
            )
        }

        var todayWeekly = 0
        var weekWeekly = 0
        var todayFiveHour = 0
        var weekFiveHour = 0
        var hourlyTotals: [Int: Int] = [:]
        var weekdayTotals: [Int: Int] = [:]
        var accountTotals: [String: Int] = [:]

        for record in state.records {
            if record.timestamp < weekStart {
                continue
            }
            let weekly = max(0, record.weeklyDeltaPercent)
            let fiveHour = max(0, record.fiveHourDeltaPercent)
            weekWeekly += weekly
            weekFiveHour += fiveHour
            accountTotals[record.accountKey, default: 0] += weekly

            let components = calendar.dateComponents([.hour, .weekday], from: record.timestamp)
            if let hour = components.hour {
                hourlyTotals[hour, default: 0] += weekly
            }
            if let weekday = components.weekday {
                weekdayTotals[weekday, default: 0] += weekly
            }

            if record.timestamp >= todayStart {
                todayWeekly += weekly
                todayFiveHour += fiveHour
            }
        }

        let peakHour = hourlyTotals.max { $0.value < $1.value }?.key
        let peakWeekday = weekdayTotals.max { $0.value < $1.value }?.key
        let topAccount = accountTotals.max { $0.value < $1.value }

        return UsageAnalyticsSummary(
            todayWeeklyPercent: todayWeekly,
            weekWeeklyPercent: weekWeekly,
            todayFiveHourPercent: todayFiveHour,
            weekFiveHourPercent: weekFiveHour,
            peakHour: peakHour,
            peakWeekday: peakWeekday,
            topAccountKey: topAccount?.key,
            topAccountWeeklyPercent: topAccount?.value ?? 0
        )
    }

    static func dailyTotals(
        for state: UsageAnalyticsState,
        now: Date,
        days: Int,
        accountKey: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UsageAnalyticsDailyTotal] {
        guard days > 0 else { return [] }
        let todayStart = calendar.startOfDay(for: now)
        var totals: [UsageAnalyticsDailyTotal] = []

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: todayStart),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else { continue }

            let total = state.records
                .filter {
                    $0.timestamp >= dayStart
                    && $0.timestamp < dayEnd
                    && (accountKey == nil || $0.accountKey == accountKey)
                }
                .reduce(0) { $0 + max(0, $1.weeklyDeltaPercent) }

            totals.append(UsageAnalyticsDailyTotal(date: dayStart, totalWeeklyPercent: total))
        }

        return totals
    }

    static func weeklyTotals(
        for state: UsageAnalyticsState,
        now: Date,
        weeks: Int,
        accountKey: String? = nil,
        calendar: Calendar = .autoupdatingCurrent
    ) -> [UsageAnalyticsWeeklyTotal] {
        guard weeks > 0 else { return [] }
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        var totals: [UsageAnalyticsWeeklyTotal] = []

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let weekStart = calendar.date(
                byAdding: .weekOfYear,
                value: -weekOffset,
                to: currentWeek.start
            ),
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                continue
            }

            let total = state.records
                .filter {
                    $0.timestamp >= weekStart
                    && $0.timestamp < weekEnd
                    && (accountKey == nil || $0.accountKey == accountKey)
                }
                .reduce(0) { $0 + max(0, $1.weeklyDeltaPercent) }

            totals.append(
                UsageAnalyticsWeeklyTotal(
                    weekStartDate: weekStart,
                    totalWeeklyPercent: total
                )
            )
        }

        return totals
    }

    private static func trim(
        records: [UsageAnalyticsRecord],
        now: Date,
        calendar: Calendar
    ) -> [UsageAnalyticsRecord] {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: now) else {
            return records
        }
        return records.filter { $0.timestamp >= cutoff }
    }

    private static func percentUsage(for account: AgentAccount) -> Int {
        let ratio = max(0, min(1, account.usageRatio))
        return Int((ratio * 100).rounded())
    }

    private static func deduplicatedAccountsByKey(_ accounts: [AgentAccount]) -> [AgentAccount] {
        var seen: Set<String> = []
        var result: [AgentAccount] = []
        result.reserveCapacity(accounts.count)

        for account in accounts {
            let key = account.deduplicationKey
            if seen.insert(key).inserted {
                result.append(account)
            }
        }

        return result
    }

    private static func deltaPercent(current: Int, previous: Int) -> Int {
        if current >= previous {
            return current - previous
        }
        return max(0, current)
    }

    private static func deltaPercent(current: Int?, previous: Int?) -> Int {
        guard let current else { return 0 }
        let previousValue = previous ?? current
        return deltaPercent(current: current, previous: previousValue)
    }
}

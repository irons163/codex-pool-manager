import Foundation

struct UsageAnalyticsRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let accountKey: String
    let weeklyDeltaPercent: Int
    let fiveHourDeltaPercent: Int
    let weeklyAbsolutePercent: Int
    let fiveHourAbsolutePercent: Int?
    let weeklyRemainingPercent: Int
    let fiveHourRemainingPercent: Int?
    let weeklyWastedPercent: Int
    let fiveHourWastedPercent: Int
    let weeklyResetAt: Date?
    let fiveHourResetAt: Date?
    let activeAccountKeyAtSync: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        accountKey: String,
        weeklyDeltaPercent: Int,
        fiveHourDeltaPercent: Int,
        weeklyAbsolutePercent: Int? = nil,
        fiveHourAbsolutePercent: Int? = nil,
        weeklyRemainingPercent: Int? = nil,
        fiveHourRemainingPercent: Int? = nil,
        weeklyWastedPercent: Int = 0,
        fiveHourWastedPercent: Int = 0,
        weeklyResetAt: Date? = nil,
        fiveHourResetAt: Date? = nil,
        activeAccountKeyAtSync: String? = nil
    ) {
        let resolvedWeeklyAbsolute = weeklyAbsolutePercent ?? weeklyDeltaPercent
        let resolvedWeeklyRemaining = weeklyRemainingPercent ?? max(0, 100 - resolvedWeeklyAbsolute)
        let resolvedFiveHourRemaining: Int? = {
            if let fiveHourRemainingPercent {
                return fiveHourRemainingPercent
            }
            if let fiveHourAbsolutePercent {
                return max(0, 100 - fiveHourAbsolutePercent)
            }
            return nil
        }()

        self.id = id
        self.timestamp = timestamp
        self.accountKey = accountKey
        self.weeklyDeltaPercent = weeklyDeltaPercent
        self.fiveHourDeltaPercent = fiveHourDeltaPercent
        self.weeklyAbsolutePercent = resolvedWeeklyAbsolute
        self.fiveHourAbsolutePercent = fiveHourAbsolutePercent
        self.weeklyRemainingPercent = resolvedWeeklyRemaining
        self.fiveHourRemainingPercent = resolvedFiveHourRemaining
        self.weeklyWastedPercent = max(0, weeklyWastedPercent)
        self.fiveHourWastedPercent = max(0, fiveHourWastedPercent)
        self.weeklyResetAt = weeklyResetAt
        self.fiveHourResetAt = fiveHourResetAt
        self.activeAccountKeyAtSync = activeAccountKeyAtSync
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case accountKey
        case weeklyDeltaPercent
        case fiveHourDeltaPercent
        case weeklyAbsolutePercent
        case fiveHourAbsolutePercent
        case weeklyRemainingPercent
        case fiveHourRemainingPercent
        case weeklyWastedPercent
        case fiveHourWastedPercent
        case weeklyResetAt
        case fiveHourResetAt
        case activeAccountKeyAtSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        accountKey = try container.decode(String.self, forKey: .accountKey)
        weeklyDeltaPercent = try container.decodeIfPresent(Int.self, forKey: .weeklyDeltaPercent) ?? 0
        fiveHourDeltaPercent = try container.decodeIfPresent(Int.self, forKey: .fiveHourDeltaPercent) ?? 0

        let decodedWeeklyAbsolute = try container.decodeIfPresent(Int.self, forKey: .weeklyAbsolutePercent)
        weeklyAbsolutePercent = decodedWeeklyAbsolute ?? weeklyDeltaPercent
        fiveHourAbsolutePercent = try container.decodeIfPresent(Int.self, forKey: .fiveHourAbsolutePercent)

        let decodedWeeklyRemaining = try container.decodeIfPresent(Int.self, forKey: .weeklyRemainingPercent)
        weeklyRemainingPercent = decodedWeeklyRemaining ?? max(0, 100 - weeklyAbsolutePercent)

        let decodedFiveHourRemaining = try container.decodeIfPresent(Int.self, forKey: .fiveHourRemainingPercent)
        if let decodedFiveHourRemaining {
            fiveHourRemainingPercent = decodedFiveHourRemaining
        } else if let fiveHourAbsolutePercent {
            fiveHourRemainingPercent = max(0, 100 - fiveHourAbsolutePercent)
        } else {
            fiveHourRemainingPercent = nil
        }

        weeklyWastedPercent = max(0, try container.decodeIfPresent(Int.self, forKey: .weeklyWastedPercent) ?? 0)
        fiveHourWastedPercent = max(0, try container.decodeIfPresent(Int.self, forKey: .fiveHourWastedPercent) ?? 0)
        weeklyResetAt = try container.decodeIfPresent(Date.self, forKey: .weeklyResetAt)
        fiveHourResetAt = try container.decodeIfPresent(Date.self, forKey: .fiveHourResetAt)
        activeAccountKeyAtSync = try container.decodeIfPresent(String.self, forKey: .activeAccountKeyAtSync)
    }
}

struct UsageAnalyticsAccountSnapshot: Identifiable, Codable, Equatable {
    let id: UUID
    let accountKey: String
    let lastWeeklyPercent: Int
    let lastFiveHourPercent: Int?
    let lastWeeklyResetAt: Date?
    let lastFiveHourResetAt: Date?
    let lastSeenAt: Date

    init(
        id: UUID = UUID(),
        accountKey: String,
        lastWeeklyPercent: Int,
        lastFiveHourPercent: Int?,
        lastWeeklyResetAt: Date? = nil,
        lastFiveHourResetAt: Date? = nil,
        lastSeenAt: Date
    ) {
        self.id = id
        self.accountKey = accountKey
        self.lastWeeklyPercent = lastWeeklyPercent
        self.lastFiveHourPercent = lastFiveHourPercent
        self.lastWeeklyResetAt = lastWeeklyResetAt
        self.lastFiveHourResetAt = lastFiveHourResetAt
        self.lastSeenAt = lastSeenAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case accountKey
        case lastWeeklyPercent
        case lastFiveHourPercent
        case lastWeeklyResetAt
        case lastFiveHourResetAt
        case lastSeenAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        accountKey = try container.decode(String.self, forKey: .accountKey)
        lastWeeklyPercent = try container.decodeIfPresent(Int.self, forKey: .lastWeeklyPercent) ?? 0
        lastFiveHourPercent = try container.decodeIfPresent(Int.self, forKey: .lastFiveHourPercent)
        lastWeeklyResetAt = try container.decodeIfPresent(Date.self, forKey: .lastWeeklyResetAt)
        lastFiveHourResetAt = try container.decodeIfPresent(Date.self, forKey: .lastFiveHourResetAt)
        lastSeenAt = try container.decodeIfPresent(Date.self, forKey: .lastSeenAt) ?? .distantPast
    }
}

enum UsageAnalyticsThresholdKind: String, Codable, Equatable {
    case weekly
    case fiveHour
}

struct UsageAnalyticsThresholdEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let accountKey: String
    let kind: UsageAnalyticsThresholdKind
    let thresholdPercent: Int
    let previousRemainingPercent: Int
    let currentRemainingPercent: Int

    init(
        id: UUID = UUID(),
        timestamp: Date,
        accountKey: String,
        kind: UsageAnalyticsThresholdKind,
        thresholdPercent: Int,
        previousRemainingPercent: Int,
        currentRemainingPercent: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.accountKey = accountKey
        self.kind = kind
        self.thresholdPercent = thresholdPercent
        self.previousRemainingPercent = previousRemainingPercent
        self.currentRemainingPercent = currentRemainingPercent
    }
}

struct UsageAnalyticsSwitchEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let fromAccountKey: String?
    let toAccountKey: String
    let fromRemainingPercent: Int?
    let toRemainingPercent: Int?
    let trigger: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        fromAccountKey: String?,
        toAccountKey: String,
        fromRemainingPercent: Int?,
        toRemainingPercent: Int?,
        trigger: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.fromAccountKey = fromAccountKey
        self.toAccountKey = toAccountKey
        self.fromRemainingPercent = fromRemainingPercent
        self.toRemainingPercent = toRemainingPercent
        self.trigger = trigger
    }
}

struct UsageAnalyticsState: Codable, Equatable {
    var records: [UsageAnalyticsRecord] = []
    var snapshots: [UsageAnalyticsAccountSnapshot] = []
    var thresholdEvents: [UsageAnalyticsThresholdEvent] = []
    var switchEvents: [UsageAnalyticsSwitchEvent] = []
    var lastActiveAccountKey: String? = nil
    var lastUpdatedAt: Date? = nil

    private enum CodingKeys: String, CodingKey {
        case records
        case snapshots
        case thresholdEvents
        case switchEvents
        case lastActiveAccountKey
        case lastUpdatedAt
    }

    init(
        records: [UsageAnalyticsRecord] = [],
        snapshots: [UsageAnalyticsAccountSnapshot] = [],
        thresholdEvents: [UsageAnalyticsThresholdEvent] = [],
        switchEvents: [UsageAnalyticsSwitchEvent] = [],
        lastActiveAccountKey: String? = nil,
        lastUpdatedAt: Date? = nil
    ) {
        self.records = records
        self.snapshots = snapshots
        self.thresholdEvents = thresholdEvents
        self.switchEvents = switchEvents
        self.lastActiveAccountKey = lastActiveAccountKey
        self.lastUpdatedAt = lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = try container.decodeIfPresent([UsageAnalyticsRecord].self, forKey: .records) ?? []
        snapshots = try container.decodeIfPresent([UsageAnalyticsAccountSnapshot].self, forKey: .snapshots) ?? []
        thresholdEvents = try container.decodeIfPresent([UsageAnalyticsThresholdEvent].self, forKey: .thresholdEvents) ?? []
        switchEvents = try container.decodeIfPresent([UsageAnalyticsSwitchEvent].self, forKey: .switchEvents) ?? []
        lastActiveAccountKey = try container.decodeIfPresent(String.self, forKey: .lastActiveAccountKey)
        lastUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .lastUpdatedAt)
    }
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

struct UsageAnalyticsSummary: Codable, Equatable {
    let todayWeeklyPercent: Int
    let weekWeeklyPercent: Int
    let todayFiveHourPercent: Int
    let weekFiveHourPercent: Int
    let todayWastedWeeklyPercent: Int
    let weekWastedWeeklyPercent: Int
    let todayWastedFiveHourPercent: Int
    let weekWastedFiveHourPercent: Int
    let weekWastedResetEvents: Int
    let peakHour: Int?
    let peakWeekday: Int?
    let topAccountKey: String?
    let topAccountWeeklyPercent: Int
}

struct UsageAnalyticsETA: Codable, Equatable {
    let accountKey: String
    let remainingPercent: Int
    let burnPerHour: Double
    let etaHours: Double?
}

struct UsageAnalyticsCoverageSummary: Codable, Equatable {
    let coveredRatio: Double
    let uncoveredSlots: Int
    let collisionRatio: Double
    let totalSlots: Int
}

struct UsageAnalyticsSwitchEffectiveness: Codable, Equatable {
    let switchCount: Int
    let averageRemainingGain: Double
    let improvedRate: Double
}

struct UsageAnalyticsAnomaly: Identifiable, Codable, Equatable {
    enum Severity: String, Codable {
        case info
        case warning
        case critical
    }

    let id: UUID
    let timestamp: Date
    let severity: Severity
    let title: String
    let detail: String

    init(
        id: UUID = UUID(),
        timestamp: Date,
        severity: Severity,
        title: String,
        detail: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

struct UsageAnalyticsRecommendation: Codable, Equatable {
    let targetAccountKey: String?
    let reason: String
}

struct UsageAnalyticsExportPayload: Codable, Equatable {
    let generatedAt: Date
    let summary: UsageAnalyticsSummary
    let coverage: UsageAnalyticsCoverageSummary
    let anomalies: [UsageAnalyticsAnomaly]
    let recommendation: UsageAnalyticsRecommendation
    let records: [UsageAnalyticsRecord]
    let thresholdEvents: [UsageAnalyticsThresholdEvent]
    let switchEvents: [UsageAnalyticsSwitchEvent]
}

enum UsageAnalyticsEngine {
    static let retentionDays: Int = 45
    static let eventRetentionDays: Int = 90
    private static let thresholdLevels: [Int] = [50, 30, 20, 10, 5, 0]
    private static let weeklyWindowSeconds: TimeInterval = 7 * 24 * 3600
    private static let resetDelayNoiseSeconds: TimeInterval = 60

    static func update(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageAnalyticsState {
        update(
            state: state,
            accounts: accounts,
            activeAccountKey: nil,
            now: now,
            calendar: calendar
        )
    }

    static func update(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        activeAccountKey: String?,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageAnalyticsState {
        let trimmedRecords = trim(records: state.records, now: now, calendar: calendar)
        let snapshotsByKey = state.snapshots.reduce(into: [String: UsageAnalyticsAccountSnapshot]()) { partial, snapshot in
            partial[snapshot.accountKey] = snapshot
        }
        let deduplicatedAccounts = deduplicatedAccountsByKey(accounts)
        let accountByKey = Dictionary(uniqueKeysWithValues: deduplicatedAccounts.map { ($0.deduplicationKey, $0) })

        var updatedSnapshots: [UsageAnalyticsAccountSnapshot] = []
        var newRecords: [UsageAnalyticsRecord] = []
        var newThresholdEvents: [UsageAnalyticsThresholdEvent] = []

        for account in deduplicatedAccounts {
            let accountKey = account.deduplicationKey
            let weeklyAbsolute = percentUsage(for: account)
            let weeklyRemaining = max(0, 100 - weeklyAbsolute)
            let fiveHourAbsolute = account.primaryUsagePercent
            let fiveHourRemaining = fiveHourAbsolute.map { max(0, 100 - min(max($0, 0), 100)) }

            if let snapshot = snapshotsByKey[accountKey] {
                let weeklyDelta = deltaPercent(current: weeklyAbsolute, previous: snapshot.lastWeeklyPercent)
                let fiveHourDelta = deltaPercent(current: fiveHourAbsolute, previous: snapshot.lastFiveHourPercent)
                let previousWeeklyRemaining = max(0, 100 - snapshot.lastWeeklyPercent)
                let weeklyWastedFromReset = wastedPercentOnReset(
                    previousRemaining: previousWeeklyRemaining,
                    previousResetAt: snapshot.lastWeeklyResetAt,
                    currentResetAt: account.usageWindowResetAt,
                    cycleHours: 168
                )
                let weeklyWastedFromNoUsageDelay = wastedPercentOnNoUsageResetDelay(
                    previousWeeklyPercent: snapshot.lastWeeklyPercent,
                    currentWeeklyPercent: weeklyAbsolute,
                    previousResetAt: snapshot.lastWeeklyResetAt,
                    currentResetAt: account.usageWindowResetAt
                )
                let weeklyWasted = max(weeklyWastedFromReset, weeklyWastedFromNoUsageDelay)
                let previousFiveHourRemaining = snapshot.lastFiveHourPercent.map { max(0, 100 - $0) }
                let fiveHourWasted = wastedPercentOnReset(
                    previousRemaining: previousFiveHourRemaining,
                    previousResetAt: snapshot.lastFiveHourResetAt,
                    currentResetAt: account.primaryUsageResetAt,
                    cycleHours: 5
                )

                if weeklyDelta > 0 || fiveHourDelta > 0 || weeklyWasted > 0 || fiveHourWasted > 0 {
                    newRecords.append(
                        UsageAnalyticsRecord(
                            timestamp: now,
                            accountKey: accountKey,
                            weeklyDeltaPercent: weeklyDelta,
                            fiveHourDeltaPercent: fiveHourDelta,
                            weeklyAbsolutePercent: weeklyAbsolute,
                            fiveHourAbsolutePercent: fiveHourAbsolute,
                            weeklyRemainingPercent: weeklyRemaining,
                            fiveHourRemainingPercent: fiveHourRemaining,
                            weeklyWastedPercent: weeklyWasted,
                            fiveHourWastedPercent: fiveHourWasted,
                            weeklyResetAt: account.usageWindowResetAt,
                            fiveHourResetAt: account.primaryUsageResetAt,
                            activeAccountKeyAtSync: activeAccountKey
                        )
                    )
                }

                newThresholdEvents += thresholdCrossingEvents(
                    accountKey: accountKey,
                    kind: .weekly,
                    previousRemaining: previousWeeklyRemaining,
                    currentRemaining: weeklyRemaining,
                    timestamp: now
                )

                if let previousFiveHourPercent = snapshot.lastFiveHourPercent,
                   let fiveHourRemaining {
                    newThresholdEvents += thresholdCrossingEvents(
                        accountKey: accountKey,
                        kind: .fiveHour,
                        previousRemaining: max(0, 100 - previousFiveHourPercent),
                        currentRemaining: fiveHourRemaining,
                        timestamp: now
                    )
                }
            }

            updatedSnapshots.append(
                UsageAnalyticsAccountSnapshot(
                    accountKey: accountKey,
                    lastWeeklyPercent: weeklyAbsolute,
                    lastFiveHourPercent: fiveHourAbsolute,
                    lastWeeklyResetAt: account.usageWindowResetAt,
                    lastFiveHourResetAt: account.primaryUsageResetAt,
                    lastSeenAt: now
                )
            )
        }

        var mergedRecords = trimmedRecords + newRecords
        mergedRecords.sort { $0.timestamp > $1.timestamp }

        var mergedThresholdEvents = trim(events: state.thresholdEvents, now: now, calendar: calendar)
        mergedThresholdEvents = Array((newThresholdEvents + mergedThresholdEvents).prefix(300))

        var mergedSwitchEvents = trim(events: state.switchEvents, now: now, calendar: calendar)
        if let activeAccountKey,
           let previousActiveKey = state.lastActiveAccountKey,
           previousActiveKey != activeAccountKey {
            let fromRemaining = accountByKey[previousActiveKey]?.smartSwitchRemainingPercent
            let toRemaining = accountByKey[activeAccountKey]?.smartSwitchRemainingPercent
            mergedSwitchEvents.insert(
                UsageAnalyticsSwitchEvent(
                    timestamp: now,
                    fromAccountKey: previousActiveKey,
                    toAccountKey: activeAccountKey,
                    fromRemainingPercent: fromRemaining,
                    toRemainingPercent: toRemaining,
                    trigger: "sync"
                ),
                at: 0
            )
            mergedSwitchEvents = Array(mergedSwitchEvents.prefix(200))
        }

        var updatedState = UsageAnalyticsState(
            records: mergedRecords,
            snapshots: updatedSnapshots,
            thresholdEvents: mergedThresholdEvents,
            switchEvents: mergedSwitchEvents,
            lastActiveAccountKey: activeAccountKey ?? state.lastActiveAccountKey,
            lastUpdatedAt: now
        )
        updatedState.records = trim(records: updatedState.records, now: now, calendar: calendar)
        return updatedState
    }

    static func seed(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        activeAccountKey: String? = nil,
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
                    lastWeeklyResetAt: account.usageWindowResetAt,
                    lastFiveHourResetAt: account.primaryUsageResetAt,
                    lastSeenAt: now
                )
            },
            thresholdEvents: state.thresholdEvents,
            switchEvents: state.switchEvents,
            lastActiveAccountKey: activeAccountKey,
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
                todayWastedWeeklyPercent: 0,
                weekWastedWeeklyPercent: 0,
                todayWastedFiveHourPercent: 0,
                weekWastedFiveHourPercent: 0,
                weekWastedResetEvents: 0,
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
        var todayWastedWeekly = 0
        var weekWastedWeekly = 0
        var todayWastedFiveHour = 0
        var weekWastedFiveHour = 0
        var weekWastedResetEvents = 0
        var hourlyTotals: [Int: Int] = [:]
        var weekdayTotals: [Int: Int] = [:]
        var accountTotals: [String: Int] = [:]

        for record in state.records where record.timestamp >= weekStart {
            let weekly = max(0, record.weeklyDeltaPercent)
            let fiveHour = max(0, record.fiveHourDeltaPercent)
            let wastedWeekly = max(0, record.weeklyWastedPercent)
            let wastedFiveHour = max(0, record.fiveHourWastedPercent)
            weekWeekly += weekly
            weekFiveHour += fiveHour
            weekWastedWeekly += wastedWeekly
            weekWastedFiveHour += wastedFiveHour
            if wastedWeekly > 0 {
                weekWastedResetEvents += 1
            }
            if wastedFiveHour > 0 {
                weekWastedResetEvents += 1
            }
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
                todayWastedWeekly += wastedWeekly
                todayWastedFiveHour += wastedFiveHour
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
            todayWastedWeeklyPercent: todayWastedWeekly,
            weekWastedWeeklyPercent: weekWastedWeekly,
            todayWastedFiveHourPercent: todayWastedFiveHour,
            weekWastedFiveHourPercent: weekWastedFiveHour,
            weekWastedResetEvents: weekWastedResetEvents,
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

    static func thresholdTimeline(
        for state: UsageAnalyticsState,
        accountKey: String? = nil,
        limit: Int = 30
    ) -> [UsageAnalyticsThresholdEvent] {
        state.thresholdEvents
            .filter { accountKey == nil || $0.accountKey == accountKey }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    static func switchEffectiveness(
        for state: UsageAnalyticsState,
        limit: Int = 60
    ) -> UsageAnalyticsSwitchEffectiveness {
        let recent = state.switchEvents.prefix(limit)
        guard !recent.isEmpty else {
            return UsageAnalyticsSwitchEffectiveness(
                switchCount: 0,
                averageRemainingGain: 0,
                improvedRate: 0
            )
        }

        var totalGain = 0.0
        var improvedCount = 0
        var measurableCount = 0

        for event in recent {
            guard let from = event.fromRemainingPercent,
                  let to = event.toRemainingPercent else {
                continue
            }
            measurableCount += 1
            let gain = Double(to - from)
            totalGain += gain
            if gain > 0 {
                improvedCount += 1
            }
        }

        let avgGain = measurableCount > 0 ? totalGain / Double(measurableCount) : 0
        let improvedRate = measurableCount > 0 ? Double(improvedCount) / Double(measurableCount) : 0

        return UsageAnalyticsSwitchEffectiveness(
            switchCount: recent.count,
            averageRemainingGain: avgGain,
            improvedRate: improvedRate
        )
    }

    static func projectedCoverage(
        accounts: [AgentAccount],
        now: Date,
        horizonHours: Int = 24,
        slotMinutes: Int = 30,
        calendar: Calendar = .autoupdatingCurrent
    ) -> UsageAnalyticsCoverageSummary {
        let tracked = deduplicatedAccountsByKey(accounts)
        guard !tracked.isEmpty, horizonHours > 0, slotMinutes > 0 else {
            return UsageAnalyticsCoverageSummary(coveredRatio: 1, uncoveredSlots: 0, collisionRatio: 0, totalSlots: 0)
        }

        let slotCount = max(1, (horizonHours * 60) / slotMinutes)
        let slotLength = TimeInterval(slotMinutes * 60)
        var uncovered = 0
        var collisions = 0

        for slotIndex in 0..<slotCount {
            let slotStart = now.addingTimeInterval(TimeInterval(slotIndex) * slotLength)
            let slotEnd = slotStart.addingTimeInterval(slotLength)

            var resetting = 0
            for account in tracked {
                if hasResetEvent(in: account, slotStart: slotStart, slotEnd: slotEnd, calendar: calendar) {
                    resetting += 1
                }
            }

            let available = max(0, tracked.count - resetting)
            if available == 0 {
                uncovered += 1
            }
            if resetting > 1 {
                collisions += 1
            }
        }

        let totalSlots = max(1, slotCount)
        return UsageAnalyticsCoverageSummary(
            coveredRatio: Double(totalSlots - uncovered) / Double(totalSlots),
            uncoveredSlots: uncovered,
            collisionRatio: Double(collisions) / Double(totalSlots),
            totalSlots: totalSlots
        )
    }

    static func etas(
        accounts: [AgentAccount],
        state: UsageAnalyticsState,
        now: Date,
        windowHours: Double = 24
    ) -> [String: UsageAnalyticsETA] {
        let deduplicated = deduplicatedAccountsByKey(accounts)
        let windowStart = now.addingTimeInterval(-windowHours * 3600)

        return deduplicated.reduce(into: [String: UsageAnalyticsETA]()) { partial, account in
            let key = account.deduplicationKey
            let consumed = state.records
                .filter { $0.accountKey == key && $0.timestamp >= windowStart }
                .reduce(0) { $0 + max(0, $1.weeklyDeltaPercent) }

            let burn = max(0, Double(consumed) / max(1, windowHours))
            let remaining = account.smartSwitchRemainingPercent
            let eta = burn > 0.01 ? Double(remaining) / burn : nil

            partial[key] = UsageAnalyticsETA(
                accountKey: key,
                remainingPercent: remaining,
                burnPerHour: burn,
                etaHours: eta
            )
        }
    }

    static func anomalies(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        now: Date
    ) -> [UsageAnalyticsAnomaly] {
        var anomalies: [UsageAnalyticsAnomaly] = []

        let lastHourStart = now.addingTimeInterval(-3600)
        let lastDayStart = now.addingTimeInterval(-24 * 3600)

        let lastHourUsage = state.records
            .filter { $0.timestamp >= lastHourStart }
            .reduce(0) { $0 + max(0, $1.weeklyDeltaPercent) }
        let lastDayUsage = state.records
            .filter { $0.timestamp >= lastDayStart }
            .reduce(0) { $0 + max(0, $1.weeklyDeltaPercent) }

        let hourlyBaseline = Double(lastDayUsage) / 24.0
        if Double(lastHourUsage) > max(10, hourlyBaseline * 3) {
            anomalies.append(
                UsageAnalyticsAnomaly(
                    timestamp: now,
                    severity: .warning,
                    title: "Usage Spike",
                    detail: "Last hour consumption is significantly higher than the 24h baseline."
                )
            )
        }

        let snapshotsByKey = state.snapshots.reduce(into: [String: UsageAnalyticsAccountSnapshot]()) { partial, snapshot in
            partial[snapshot.accountKey] = snapshot
        }

        for account in deduplicatedAccountsByKey(accounts) {
            let key = account.deduplicationKey
            let recentRecords = state.records
                .filter { $0.accountKey == key && $0.timestamp >= lastDayStart }
            if recentRecords.isEmpty {
                anomalies.append(
                    UsageAnalyticsAnomaly(
                        timestamp: now,
                        severity: .info,
                        title: "No Recent Activity",
                        detail: "Account \(account.name) had no recorded usage updates in the last 24 hours."
                    )
                )
            }

            if let snapshot = snapshotsByKey[key],
               let previousReset = snapshot.lastWeeklyResetAt,
               let currentReset = account.usageWindowResetAt {
                let shiftHours = abs(currentReset.timeIntervalSince(previousReset)) / 3600
                if shiftHours >= 3 {
                    anomalies.append(
                        UsageAnalyticsAnomaly(
                            timestamp: now,
                            severity: .warning,
                            title: "Reset Drift",
                            detail: "Account \(account.name) weekly reset shifted by about \(Int(shiftHours.rounded())) hours."
                        )
                    )
                }
            }
        }

        return Array(anomalies.prefix(12))
    }

    static func recommendation(
        accounts: [AgentAccount],
        activeAccountKey: String?,
        etasByAccountKey: [String: UsageAnalyticsETA]
    ) -> UsageAnalyticsRecommendation {
        let deduplicated = deduplicatedAccountsByKey(accounts)
        guard !deduplicated.isEmpty else {
            return UsageAnalyticsRecommendation(targetAccountKey: nil, reason: "No accounts available.")
        }

        let ranked = deduplicated.sorted { lhs, rhs in
            if lhs.smartSwitchRemainingPercent != rhs.smartSwitchRemainingPercent {
                return lhs.smartSwitchRemainingPercent > rhs.smartSwitchRemainingPercent
            }
            let lhsETA = etasByAccountKey[lhs.deduplicationKey]?.etaHours ?? -1
            let rhsETA = etasByAccountKey[rhs.deduplicationKey]?.etaHours ?? -1
            return lhsETA > rhsETA
        }

        guard let best = ranked.first else {
            return UsageAnalyticsRecommendation(targetAccountKey: nil, reason: "No recommendation available.")
        }

        if activeAccountKey == best.deduplicationKey {
            return UsageAnalyticsRecommendation(
                targetAccountKey: best.deduplicationKey,
                reason: "Current account already has the strongest remaining capacity."
            )
        }

        let currentRemaining = ranked.first(where: { $0.deduplicationKey == activeAccountKey })?.smartSwitchRemainingPercent ?? 0
        let gain = best.smartSwitchRemainingPercent - currentRemaining
        let reason = "Switch to \(best.name): remaining improves by \(gain)% (\(currentRemaining)% -> \(best.smartSwitchRemainingPercent)%)."

        return UsageAnalyticsRecommendation(targetAccountKey: best.deduplicationKey, reason: reason)
    }

    static func csvReport(state: UsageAnalyticsState, accounts: [AgentAccount]) -> String {
        let accountNameByKey = Dictionary(uniqueKeysWithValues: deduplicatedAccountsByKey(accounts).map { ($0.deduplicationKey, $0.name) })

        var lines: [String] = [
            "timestamp,account_key,account_name,weekly_delta_percent,five_hour_delta_percent,weekly_abs_percent,five_hour_abs_percent,weekly_remaining_percent,five_hour_remaining_percent,weekly_wasted_percent,five_hour_wasted_percent"
        ]

        for record in state.records.sorted(by: { $0.timestamp < $1.timestamp }) {
            let accountName = escapeCSV(accountNameByKey[record.accountKey] ?? "")
            let fiveHourAbs = record.fiveHourAbsolutePercent.map(String.init) ?? ""
            let fiveHourRemain = record.fiveHourRemainingPercent.map(String.init) ?? ""
            lines.append(
                "\(iso8601(record.timestamp)),\(escapeCSV(record.accountKey)),\(accountName),\(record.weeklyDeltaPercent),\(record.fiveHourDeltaPercent),\(record.weeklyAbsolutePercent),\(fiveHourAbs),\(record.weeklyRemainingPercent),\(fiveHourRemain),\(record.weeklyWastedPercent),\(record.fiveHourWastedPercent)"
            )
        }

        return lines.joined(separator: "\n")
    }

    static func jsonReport(
        state: UsageAnalyticsState,
        accounts: [AgentAccount],
        activeAccountKey: String?,
        now: Date
    ) -> String {
        let summaryValue = summary(for: state, now: now)
        let coverageValue = projectedCoverage(accounts: accounts, now: now)
        let etaMap = etas(accounts: accounts, state: state, now: now)
        let recommendationValue = recommendation(
            accounts: accounts,
            activeAccountKey: activeAccountKey,
            etasByAccountKey: etaMap
        )
        let anomaliesValue = anomalies(state: state, accounts: accounts, now: now)

        let payload = UsageAnalyticsExportPayload(
            generatedAt: now,
            summary: summaryValue,
            coverage: coverageValue,
            anomalies: anomaliesValue,
            recommendation: recommendationValue,
            records: state.records,
            thresholdEvents: state.thresholdEvents,
            switchEvents: state.switchEvents
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func hasResetEvent(
        in account: AgentAccount,
        slotStart: Date,
        slotEnd: Date,
        calendar: Calendar
    ) -> Bool {
        let candidateDates = [account.usageWindowResetAt, account.primaryUsageResetAt].compactMap { $0 }
        for resetAt in candidateDates {
            if resetAt >= slotStart && resetAt < slotEnd {
                return true
            }

            // Also check recurring occurrence for short horizons.
            if let weeklyRecurrence = nextOccurrence(of: resetAt, intervalHours: 168, after: slotStart, calendar: calendar),
               weeklyRecurrence < slotEnd {
                return true
            }
            if let fiveHourRecurrence = nextOccurrence(of: resetAt, intervalHours: 5, after: slotStart, calendar: calendar),
               fiveHourRecurrence < slotEnd {
                return true
            }
        }
        return false
    }

    private static func nextOccurrence(
        of date: Date,
        intervalHours: Int,
        after lowerBound: Date,
        calendar: Calendar
    ) -> Date? {
        guard intervalHours > 0 else { return nil }
        let intervalSeconds = TimeInterval(intervalHours * 3600)
        if date >= lowerBound {
            return date
        }

        let elapsed = lowerBound.timeIntervalSince(date)
        let steps = Int(elapsed / intervalSeconds)
        guard let candidate = calendar.date(byAdding: .hour, value: intervalHours * (steps + 1), to: date) else {
            return nil
        }
        return candidate
    }

    private static func thresholdCrossingEvents(
        accountKey: String,
        kind: UsageAnalyticsThresholdKind,
        previousRemaining: Int,
        currentRemaining: Int,
        timestamp: Date
    ) -> [UsageAnalyticsThresholdEvent] {
        guard currentRemaining < previousRemaining else { return [] }

        return thresholdLevels.compactMap { threshold in
            guard previousRemaining > threshold, currentRemaining <= threshold else {
                return nil
            }
            return UsageAnalyticsThresholdEvent(
                timestamp: timestamp,
                accountKey: accountKey,
                kind: kind,
                thresholdPercent: threshold,
                previousRemainingPercent: previousRemaining,
                currentRemainingPercent: currentRemaining
            )
        }
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

    private static func trim(
        events: [UsageAnalyticsThresholdEvent],
        now: Date,
        calendar: Calendar
    ) -> [UsageAnalyticsThresholdEvent] {
        guard let cutoff = calendar.date(byAdding: .day, value: -eventRetentionDays, to: now) else {
            return events
        }
        return events.filter { $0.timestamp >= cutoff }
    }

    private static func trim(
        events: [UsageAnalyticsSwitchEvent],
        now: Date,
        calendar: Calendar
    ) -> [UsageAnalyticsSwitchEvent] {
        guard let cutoff = calendar.date(byAdding: .day, value: -eventRetentionDays, to: now) else {
            return events
        }
        return events.filter { $0.timestamp >= cutoff }
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

    private static func wastedPercentOnReset(
        previousRemaining: Int?,
        previousResetAt: Date?,
        currentResetAt: Date?,
        cycleHours: Int
    ) -> Int {
        guard let previousRemaining, previousRemaining > 0 else { return 0 }
        guard didResetAdvance(
            previousResetAt: previousResetAt,
            currentResetAt: currentResetAt,
            cycleHours: cycleHours
        ) else {
            return 0
        }
        return previousRemaining
    }

    private static func didResetAdvance(
        previousResetAt: Date?,
        currentResetAt: Date?,
        cycleHours: Int
    ) -> Bool {
        guard cycleHours > 0,
              let previousResetAt,
              let currentResetAt,
              currentResetAt > previousResetAt else {
            return false
        }
        let minimumResetJump = TimeInterval(cycleHours) * 3600 * 0.5
        return currentResetAt.timeIntervalSince(previousResetAt) >= minimumResetJump
    }

    private static func wastedPercentOnNoUsageResetDelay(
        previousWeeklyPercent: Int,
        currentWeeklyPercent: Int,
        previousResetAt: Date?,
        currentResetAt: Date?
    ) -> Int {
        // If weekly usage never started (still 0%), but reset time keeps moving later,
        // treat the delayed window as wasted potential.
        guard previousWeeklyPercent == 0, currentWeeklyPercent == 0 else { return 0 }
        guard let previousResetAt, let currentResetAt, currentResetAt > previousResetAt else { return 0 }

        let delaySeconds = currentResetAt.timeIntervalSince(previousResetAt)
        guard delaySeconds >= resetDelayNoiseSeconds else { return 0 }

        let normalizedDelay = min(1, delaySeconds / weeklyWindowSeconds)
        let wastedPercent = Int((normalizedDelay * 100).rounded())
        return max(1, min(100, wastedPercent))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private static func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}

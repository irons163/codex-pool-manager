import Foundation

struct AgentAccount: Identifiable, Equatable, Codable {
    let id: UUID
    var createdAt: Date
    var name: String
    var usedUnits: Int
    var quota: Int
    var apiToken: String
    var chatGPTAccountID: String?
    var usageWindowName: String?
    var usageWindowResetAt: Date?
    var isUsageSyncExcluded: Bool
    var usageSyncError: String?

    init(
        id: UUID,
        createdAt: Date = .now,
        name: String,
        usedUnits: Int,
        quota: Int,
        apiToken: String = "",
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        isUsageSyncExcluded: Bool = false,
        usageSyncError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.usedUnits = usedUnits
        self.quota = quota
        self.apiToken = apiToken
        self.chatGPTAccountID = chatGPTAccountID
        self.usageWindowName = usageWindowName
        self.usageWindowResetAt = usageWindowResetAt
        self.isUsageSyncExcluded = isUsageSyncExcluded
        self.usageSyncError = usageSyncError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        name = try container.decode(String.self, forKey: .name)
        usedUnits = try container.decodeIfPresent(Int.self, forKey: .usedUnits) ?? 0
        quota = try container.decodeIfPresent(Int.self, forKey: .quota) ?? 100
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        chatGPTAccountID = try container.decodeIfPresent(String.self, forKey: .chatGPTAccountID)
        usageWindowName = try container.decodeIfPresent(String.self, forKey: .usageWindowName)
        usageWindowResetAt = try container.decodeIfPresent(Date.self, forKey: .usageWindowResetAt)
        isUsageSyncExcluded = try container.decodeIfPresent(Bool.self, forKey: .isUsageSyncExcluded) ?? false
        usageSyncError = try container.decodeIfPresent(String.self, forKey: .usageSyncError)
    }

    var remainingUnits: Int {
        max(0, quota - usedUnits)
    }

    var usageRatio: Double {
        guard quota > 0 else { return 1 }
        return Double(usedUnits) / Double(quota)
    }

    var remainingRatio: Double {
        guard quota > 0 else { return 0 }
        return Double(remainingUnits) / Double(quota)
    }

    func redactingAPIToken() -> AgentAccount {
        AgentAccount(
            id: id,
            createdAt: createdAt,
            name: name,
            usedUnits: usedUnits,
            quota: quota,
            apiToken: "",
            chatGPTAccountID: chatGPTAccountID,
            usageWindowName: usageWindowName,
            usageWindowResetAt: usageWindowResetAt,
            isUsageSyncExcluded: isUsageSyncExcluded,
            usageSyncError: usageSyncError
        )
    }
}

struct PoolActivity: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
}

enum SwitchMode: String, CaseIterable, Identifiable, Codable {
    case intelligent = "智能切換"
    case manual = "手動切換"
    case focus = "專注模式"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case SwitchMode.intelligent.rawValue, "intelligent":
            self = .intelligent
        case SwitchMode.manual.rawValue, "manual":
            self = .manual
        case SwitchMode.focus.rawValue, "focus":
            self = .focus
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize SwitchMode from invalid value \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct LowUsageAlertPolicy {
    private var lowWarningWasActive = false

    mutating func shouldTriggerAlert(mode: SwitchMode, hasLowUsageWarning: Bool) -> Bool {
        let isCurrentlyLow = (mode == .focus) && hasLowUsageWarning
        defer { lowWarningWasActive = isCurrentlyLow }
        return isCurrentlyLow && !lowWarningWasActive
    }
}

struct DestructiveActionLatch {
    private(set) var isArmed = false

    mutating func confirmOrArm() -> Bool {
        if isArmed {
            isArmed = false
            return true
        }
        isArmed = true
        return false
    }

    mutating func reset() {
        isArmed = false
    }
}

struct AccountPoolSnapshot: Codable, Equatable {
    var accounts: [AgentAccount]
    var activities: [PoolActivity]
    var mode: SwitchMode
    var activeAccountID: UUID?
    var manualAccountID: UUID?
    var focusLockedAccountID: UUID?
    var minSwitchInterval: TimeInterval
    var lowUsageThresholdRatio: Double
    var minUsageRatioDeltaToSwitch: Double
    var lastSwitchAt: Date?
    var lastUsageSyncAt: Date?

    init(
        accounts: [AgentAccount],
        activities: [PoolActivity],
        mode: SwitchMode,
        activeAccountID: UUID?,
        manualAccountID: UUID?,
        focusLockedAccountID: UUID?,
        minSwitchInterval: TimeInterval,
        lowUsageThresholdRatio: Double,
        minUsageRatioDeltaToSwitch: Double,
        lastSwitchAt: Date?,
        lastUsageSyncAt: Date? = nil
    ) {
        self.accounts = accounts
        self.activities = activities
        self.mode = mode
        self.activeAccountID = activeAccountID
        self.manualAccountID = manualAccountID
        self.focusLockedAccountID = focusLockedAccountID
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
        self.minUsageRatioDeltaToSwitch = minUsageRatioDeltaToSwitch
        self.lastSwitchAt = lastSwitchAt
        self.lastUsageSyncAt = lastUsageSyncAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AgentAccount].self, forKey: .accounts)
        activities = try container.decodeIfPresent([PoolActivity].self, forKey: .activities) ?? []
        mode = try container.decode(SwitchMode.self, forKey: .mode)
        activeAccountID = try container.decodeIfPresent(UUID.self, forKey: .activeAccountID)
        manualAccountID = try container.decodeIfPresent(UUID.self, forKey: .manualAccountID)
        focusLockedAccountID = try container.decodeIfPresent(UUID.self, forKey: .focusLockedAccountID)
        minSwitchInterval = try container.decode(TimeInterval.self, forKey: .minSwitchInterval)
        lowUsageThresholdRatio = try container.decode(Double.self, forKey: .lowUsageThresholdRatio)
        minUsageRatioDeltaToSwitch = try container.decodeIfPresent(Double.self, forKey: .minUsageRatioDeltaToSwitch) ?? 0
        lastSwitchAt = try container.decodeIfPresent(Date.self, forKey: .lastSwitchAt)
        lastUsageSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastUsageSyncAt)
    }

    func redactingAPITokens() -> AccountPoolSnapshot {
        AccountPoolSnapshot(
            accounts: accounts.map { $0.redactingAPIToken() },
            activities: activities,
            mode: mode,
            activeAccountID: activeAccountID,
            manualAccountID: manualAccountID,
            focusLockedAccountID: focusLockedAccountID,
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch,
            lastSwitchAt: lastSwitchAt,
            lastUsageSyncAt: lastUsageSyncAt
        )
    }
}

struct AccountPoolState {
    private(set) var accounts: [AgentAccount]
    private(set) var activities: [PoolActivity]
    private(set) var mode: SwitchMode
    private(set) var activeAccountID: UUID?
    private(set) var manualAccountID: UUID?

    private var focusLockedAccountID: UUID?
    private var lastSwitchAt: Date?
    private(set) var lastUsageSyncAt: Date?

    private(set) var minSwitchInterval: TimeInterval
    private(set) var lowUsageThresholdRatio: Double
    private(set) var minUsageRatioDeltaToSwitch: Double

    init(
        accounts: [AgentAccount],
        mode: SwitchMode = .intelligent,
        minSwitchInterval: TimeInterval = 300,
        lowUsageThresholdRatio: Double = 0.15,
        minUsageRatioDeltaToSwitch: Double = 0
    ) {
        self.accounts = accounts
        self.activities = []
        self.mode = mode
        self.activeAccountID = nil
        self.manualAccountID = accounts.first?.id
        self.focusLockedAccountID = nil
        self.lastSwitchAt = nil
        self.lastUsageSyncAt = nil
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
        self.minUsageRatioDeltaToSwitch = max(0, min(0.5, minUsageRatioDeltaToSwitch))
    }

    init(snapshot: AccountPoolSnapshot) {
        self.accounts = snapshot.accounts
        self.activities = snapshot.activities
        self.mode = snapshot.mode
        self.activeAccountID = snapshot.activeAccountID
        self.manualAccountID = snapshot.manualAccountID
        self.focusLockedAccountID = snapshot.focusLockedAccountID
        self.lastSwitchAt = snapshot.lastSwitchAt
        self.lastUsageSyncAt = snapshot.lastUsageSyncAt
        self.minSwitchInterval = max(30, snapshot.minSwitchInterval)
        self.lowUsageThresholdRatio = min(0.9, max(0.01, snapshot.lowUsageThresholdRatio))
        self.minUsageRatioDeltaToSwitch = min(0.5, max(0, snapshot.minUsageRatioDeltaToSwitch))
        evaluate(now: .now)
    }

    var activeAccount: AgentAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first(where: { $0.id == activeAccountID })
    }

    var hasLowUsageWarning: Bool {
        guard let activeAccount else { return false }
        return activeAccount.remainingRatio <= lowUsageThresholdRatio
    }

    var totalUsedUnits: Int {
        syncIncludedAccounts.reduce(0) { $0 + $1.usedUnits }
    }

    var totalQuota: Int {
        syncIncludedAccounts.reduce(0) { $0 + $1.quota }
    }

    var overallUsageRatio: Double {
        guard totalQuota > 0 else { return 0 }
        return Double(totalUsedUnits) / Double(totalQuota)
    }

    var availableAccountsCount: Int {
        syncIncludedAccounts.filter { $0.remainingUnits > 0 }.count
    }

    var isPoolExhausted: Bool {
        !syncIncludedAccounts.isEmpty && availableAccountsCount == 0
    }

    var intelligentCandidateID: UUID? {
        intelligentCandidateAccountID()
    }

    var focusLockedID: UUID? {
        focusLockedAccountID
    }

    var isFocusLockActive: Bool {
        mode == .focus && focusLockedAccountID != nil
    }

    var snapshot: AccountPoolSnapshot {
        AccountPoolSnapshot(
            accounts: accounts,
            activities: activities,
            mode: mode,
            activeAccountID: activeAccountID,
            manualAccountID: manualAccountID,
            focusLockedAccountID: focusLockedAccountID,
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch,
            lastSwitchAt: lastSwitchAt,
            lastUsageSyncAt: lastUsageSyncAt
        )
    }

    mutating func updateSwitchSettings(
        minSwitchInterval: TimeInterval? = nil,
        lowUsageThresholdRatio: Double? = nil,
        minUsageRatioDeltaToSwitch: Double? = nil,
        now: Date = .now
    ) {
        if let minSwitchInterval {
            self.minSwitchInterval = max(30, minSwitchInterval)
        }
        if let lowUsageThresholdRatio {
            self.lowUsageThresholdRatio = min(0.9, max(0.01, lowUsageThresholdRatio))
        }
        if let minUsageRatioDeltaToSwitch {
            self.minUsageRatioDeltaToSwitch = min(0.5, max(0, minUsageRatioDeltaToSwitch))
        }
        evaluate(now: now)
    }

    func canIntelligentSwitch(now: Date = .now) -> Bool {
        guard mode == .intelligent else { return false }
        return canSwitch(now: now)
    }

    func intelligentSwitchCooldownRemaining(now: Date = .now) -> Int {
        guard mode == .intelligent, let lastSwitchAt else { return 0 }
        let remaining = minSwitchInterval - now.timeIntervalSince(lastSwitchAt)
        return max(0, Int(ceil(remaining)))
    }

    mutating func setMode(_ newMode: SwitchMode, now: Date = .now) {
        if mode != newMode {
            mode = newMode
            if newMode != .focus {
                focusLockedAccountID = nil
            }
        }
        evaluate(now: now)
    }

    mutating func selectManualAccount(_ accountID: UUID, now: Date = .now) {
        manualAccountID = accountID
        if mode == .manual {
            switchActive(to: accountID, now: now)
        }
    }

    mutating func recordUsage(units: Int, now: Date = .now) {
        guard units > 0, let activeAccountID else { return }
        guard let index = accounts.firstIndex(where: { $0.id == activeAccountID }) else { return }

        let nextUsage = min(accounts[index].quota, accounts[index].usedUnits + units)
        accounts[index].usedUnits = nextUsage
        evaluate(now: now)
    }

    @discardableResult
    mutating func addAccount(
        name: String,
        quota: Int,
        usedUnits: Int = 0,
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        now: Date = .now
    ) -> UUID {
        let normalizedQuota = max(1, quota)
        let normalizedUsedUnits = max(0, min(usedUnits, normalizedQuota))
        let account = AgentAccount(
            id: UUID(),
            name: name.isEmpty ? L10n.text("account.unnamed") : name,
            usedUnits: normalizedUsedUnits,
            quota: normalizedQuota,
            chatGPTAccountID: chatGPTAccountID,
            usageWindowName: usageWindowName,
            usageWindowResetAt: usageWindowResetAt
        )
        accounts.append(account)
        appendActivity(String(format: L10n.text("activity.account_added_format"), account.name), now: now)

        if manualAccountID == nil {
            manualAccountID = account.id
        }
        evaluate(now: now)
        return account.id
    }

    mutating func removeAccount(_ accountID: UUID, now: Date = .now) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts.remove(at: index)

        if activeAccountID == accountID {
            activeAccountID = nil
        }
        if manualAccountID == accountID {
            manualAccountID = accounts.first?.id
        }
        if focusLockedAccountID == accountID {
            focusLockedAccountID = nil
        }

        evaluate(now: now)
    }

    mutating func updateAccount(
        _ accountID: UUID,
        name: String? = nil,
        quota: Int? = nil,
        usedUnits: Int? = nil,
        apiToken: String? = nil,
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        now: Date = .now
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        if let name {
            accounts[index].name = name.isEmpty ? L10n.text("account.unnamed") : name
        }
        if let quota {
            accounts[index].quota = max(1, quota)
        }
        if let usedUnits {
            accounts[index].usedUnits = max(0, usedUnits)
        }
        if let apiToken {
            accounts[index].apiToken = apiToken
        }
        if let chatGPTAccountID {
            accounts[index].chatGPTAccountID = chatGPTAccountID
        }
        if let usageWindowName {
            accounts[index].usageWindowName = usageWindowName
        }
        if let usageWindowResetAt {
            accounts[index].usageWindowResetAt = usageWindowResetAt
        }

        accounts[index].usedUnits = min(accounts[index].usedUnits, accounts[index].quota)
        evaluate(now: now)
    }

    mutating func resetUsage(for accountID: UUID, now: Date = .now) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].usedUnits = 0
        appendActivity(
            String(format: L10n.text("activity.account_reset_usage_format"), accounts[index].name),
            now: now
        )
        evaluate(now: now)
    }

    mutating func resetAllUsage(now: Date = .now) {
        for index in accounts.indices {
            accounts[index].usedUnits = 0
        }
        appendActivity(L10n.text("activity.reset_all_usage"), now: now)
        evaluate(now: now)
    }

    mutating func clearActivities() {
        activities.removeAll()
    }

    mutating func markUsageSynced(at now: Date = .now) {
        lastUsageSyncAt = now
    }

    mutating func setUsageSyncExclusion(
        for accountID: UUID,
        reason: String?,
        now: Date = .now
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].isUsageSyncExcluded = (reason != nil)
        accounts[index].usageSyncError = reason
        evaluate(now: now)
    }

    mutating func evaluate(now: Date = .now) {
        guard !accounts.isEmpty else {
            activeAccountID = nil
            return
        }

        switch mode {
        case .manual:
            let fallbackID = accounts[0].id
            switchActive(to: manualAccountID ?? fallbackID, now: now)

        case .focus:
            if focusLockedAccountID == nil {
                focusLockedAccountID = bestRemainingAccountID()
            }
            if let focusLockedAccountID {
                switchActive(to: focusLockedAccountID, now: now)
            }

        case .intelligent:
            focusLockedAccountID = nil
            guard let candidateID = intelligentCandidateAccountID() else {
                activeAccountID = nil
                return
            }

            guard let current = activeAccount else {
                switchActive(to: candidateID, now: now)
                return
            }

            if current.remainingUnits == 0 {
                switchActive(to: candidateID, now: now)
                return
            }

            if current.id == candidateID {
                return
            }

            if let candidate = accounts.first(where: { $0.id == candidateID }) {
                let improvement = current.usageRatio - candidate.usageRatio
                if improvement < minUsageRatioDeltaToSwitch {
                    return
                }
            }

            guard canSwitch(now: now) else { return }
            switchActive(to: candidateID, now: now)
        }
    }

    private func canSwitch(now: Date) -> Bool {
        guard let lastSwitchAt else { return true }
        return now.timeIntervalSince(lastSwitchAt) >= minSwitchInterval
    }

    private func intelligentCandidateAccountID() -> UUID? {
        let availableAccounts = syncIncludedAccounts.filter { $0.remainingUnits > 0 }
        guard !availableAccounts.isEmpty else { return nil }

        return availableAccounts
            .sorted {
                if $0.usageRatio == $1.usageRatio {
                    return $0.remainingUnits > $1.remainingUnits
                }
                return $0.usageRatio < $1.usageRatio
            }
            .first?
            .id
    }

    private func bestRemainingAccountID() -> UUID? {
        syncIncludedAccounts.max(by: { $0.remainingUnits < $1.remainingUnits })?.id
    }

    private var syncIncludedAccounts: [AgentAccount] {
        accounts.filter { !$0.isUsageSyncExcluded }
    }

    private mutating func switchActive(to accountID: UUID, now: Date) {
        let availableIDs = Set(syncIncludedAccounts.map(\.id))
        guard !availableIDs.isEmpty else {
            activeAccountID = nil
            return
        }
        let fallbackID = syncIncludedAccounts[0].id
        let validID = availableIDs.contains(accountID) ? accountID : fallbackID
        if activeAccountID != validID {
            let previousName = accounts.first(where: { $0.id == activeAccountID })?.name
            activeAccountID = validID
            lastSwitchAt = now
            let targetName = accounts.first(where: { $0.id == validID })?.name ?? L10n.text("account.unknown")
            if let previousName {
                appendActivity(
                    String(
                        format: L10n.text("activity.switch_account_from_to_format"),
                        previousName,
                        targetName
                    ),
                    now: now
                )
            } else {
                appendActivity(String(format: L10n.text("activity.switch_account_to_format"), targetName), now: now)
            }
        }
    }

    private mutating func appendActivity(_ message: String, now: Date) {
        activities.insert(
            PoolActivity(id: UUID(), timestamp: now, message: message),
            at: 0
        )
        if activities.count > 100 {
            activities.removeLast(activities.count - 100)
        }
    }
}

import Foundation

struct AgentAccount: Identifiable, Equatable, Codable {
    static let defaultGroupName = "Default"

    let id: UUID
    var createdAt: Date
    var name: String
    var groupName: String
    var usedUnits: Int
    var quota: Int
    var apiToken: String
    var email: String?
    var chatGPTAccountID: String?
    var usageWindowName: String?
    var usageWindowResetAt: Date?
    var primaryUsagePercent: Int?
    var primaryUsageResetAt: Date?
    var secondaryUsagePercent: Int?
    var secondaryUsageResetAt: Date?
    var isPaid: Bool
    var isUsageSyncExcluded: Bool
    var usageSyncError: String?

    init(
        id: UUID,
        createdAt: Date = .now,
        name: String,
        groupName: String = AgentAccount.defaultGroupName,
        usedUnits: Int,
        quota: Int,
        apiToken: String = "",
        email: String? = nil,
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        primaryUsagePercent: Int? = nil,
        primaryUsageResetAt: Date? = nil,
        secondaryUsagePercent: Int? = nil,
        secondaryUsageResetAt: Date? = nil,
        isPaid: Bool = false,
        isUsageSyncExcluded: Bool = false,
        usageSyncError: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.name = name
        self.groupName = AgentAccount.normalizedGroupName(groupName)
        self.usedUnits = usedUnits
        self.quota = quota
        self.apiToken = apiToken
        self.email = email
        self.chatGPTAccountID = chatGPTAccountID
        self.usageWindowName = usageWindowName
        self.usageWindowResetAt = usageWindowResetAt
        self.primaryUsagePercent = primaryUsagePercent
        self.primaryUsageResetAt = primaryUsageResetAt
        self.secondaryUsagePercent = secondaryUsagePercent
        self.secondaryUsageResetAt = secondaryUsageResetAt
        self.isPaid = isPaid
        self.isUsageSyncExcluded = isUsageSyncExcluded
        self.usageSyncError = usageSyncError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        name = try container.decode(String.self, forKey: .name)
        groupName = AgentAccount.normalizedGroupName(
            try container.decodeIfPresent(String.self, forKey: .groupName) ?? AgentAccount.defaultGroupName
        )
        usedUnits = try container.decodeIfPresent(Int.self, forKey: .usedUnits) ?? 0
        quota = try container.decodeIfPresent(Int.self, forKey: .quota) ?? 100
        apiToken = try container.decodeIfPresent(String.self, forKey: .apiToken) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        chatGPTAccountID = try container.decodeIfPresent(String.self, forKey: .chatGPTAccountID)
        usageWindowName = try container.decodeIfPresent(String.self, forKey: .usageWindowName)
        usageWindowResetAt = try container.decodeIfPresent(Date.self, forKey: .usageWindowResetAt)
        primaryUsagePercent = try container.decodeIfPresent(Int.self, forKey: .primaryUsagePercent)
        primaryUsageResetAt = try container.decodeIfPresent(Date.self, forKey: .primaryUsageResetAt)
        secondaryUsagePercent = try container.decodeIfPresent(Int.self, forKey: .secondaryUsagePercent)
        secondaryUsageResetAt = try container.decodeIfPresent(Date.self, forKey: .secondaryUsageResetAt)
        isPaid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
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
            groupName: groupName,
            usedUnits: usedUnits,
            quota: quota,
            apiToken: "",
            email: email,
            chatGPTAccountID: chatGPTAccountID,
            usageWindowName: usageWindowName,
            usageWindowResetAt: usageWindowResetAt,
            primaryUsagePercent: primaryUsagePercent,
            primaryUsageResetAt: primaryUsageResetAt,
            secondaryUsagePercent: secondaryUsagePercent,
            secondaryUsageResetAt: secondaryUsageResetAt,
            isPaid: isPaid,
            isUsageSyncExcluded: isUsageSyncExcluded,
            usageSyncError: usageSyncError
        )
    }

    static func normalizedGroupName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultGroupName : trimmed
    }
}

struct PoolActivity: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
}

enum SwitchMode: String, CaseIterable, Identifiable, Codable {
    case intelligent = "intelligent"
    case manual = "manual"
    case focus = "focus"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case SwitchMode.intelligent.rawValue, "Intelligent", "智能切換":
            self = .intelligent
        case SwitchMode.manual.rawValue, "Manual", "手動切換":
            self = .manual
        case SwitchMode.focus.rawValue, "Focus", "專注模式":
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
        let isManagedMode = mode == .focus || mode == .intelligent
        let isCurrentlyLow = isManagedMode && hasLowUsageWarning
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
    var groups: [String]
    var activities: [PoolActivity]
    var mode: SwitchMode
    var activeAccountID: UUID?
    var manualAccountID: UUID?
    var focusLockedAccountID: UUID?
    var minSwitchInterval: TimeInterval
    var lowUsageThresholdRatio: Double
    var lowUsageAlertThresholdRatio: Double
    var minUsageRatioDeltaToSwitch: Double
    var lastSwitchAt: Date?
    var lastUsageSyncAt: Date?
    var switchWithoutLaunching: Bool
    var autoSyncEnabled: Bool
    var autoSyncIntervalSeconds: TimeInterval

    init(
        accounts: [AgentAccount],
        groups: [String],
        activities: [PoolActivity],
        mode: SwitchMode,
        activeAccountID: UUID?,
        manualAccountID: UUID?,
        focusLockedAccountID: UUID?,
        minSwitchInterval: TimeInterval,
        lowUsageThresholdRatio: Double,
        lowUsageAlertThresholdRatio: Double? = nil,
        minUsageRatioDeltaToSwitch: Double,
        lastSwitchAt: Date?,
        lastUsageSyncAt: Date? = nil,
        switchWithoutLaunching: Bool = false,
        autoSyncEnabled: Bool = true,
        autoSyncIntervalSeconds: TimeInterval = 30
    ) {
        self.accounts = accounts
        self.groups = groups
        self.activities = activities
        self.mode = mode
        self.activeAccountID = activeAccountID
        self.manualAccountID = manualAccountID
        self.focusLockedAccountID = focusLockedAccountID
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
        self.lowUsageAlertThresholdRatio = lowUsageAlertThresholdRatio ?? lowUsageThresholdRatio
        self.minUsageRatioDeltaToSwitch = minUsageRatioDeltaToSwitch
        self.lastSwitchAt = lastSwitchAt
        self.lastUsageSyncAt = lastUsageSyncAt
        self.switchWithoutLaunching = switchWithoutLaunching
        self.autoSyncEnabled = autoSyncEnabled
        self.autoSyncIntervalSeconds = autoSyncIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([AgentAccount].self, forKey: .accounts)
        groups = try container.decodeIfPresent([String].self, forKey: .groups) ?? []
        activities = try container.decodeIfPresent([PoolActivity].self, forKey: .activities) ?? []
        mode = try container.decode(SwitchMode.self, forKey: .mode)
        activeAccountID = try container.decodeIfPresent(UUID.self, forKey: .activeAccountID)
        manualAccountID = try container.decodeIfPresent(UUID.self, forKey: .manualAccountID)
        focusLockedAccountID = try container.decodeIfPresent(UUID.self, forKey: .focusLockedAccountID)
        minSwitchInterval = try container.decode(TimeInterval.self, forKey: .minSwitchInterval)
        lowUsageThresholdRatio = try container.decode(Double.self, forKey: .lowUsageThresholdRatio)
        lowUsageAlertThresholdRatio = try container.decodeIfPresent(Double.self, forKey: .lowUsageAlertThresholdRatio) ?? lowUsageThresholdRatio
        minUsageRatioDeltaToSwitch = try container.decodeIfPresent(Double.self, forKey: .minUsageRatioDeltaToSwitch) ?? 0
        lastSwitchAt = try container.decodeIfPresent(Date.self, forKey: .lastSwitchAt)
        lastUsageSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastUsageSyncAt)
        switchWithoutLaunching = try container.decodeIfPresent(Bool.self, forKey: .switchWithoutLaunching) ?? false
        autoSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        autoSyncIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .autoSyncIntervalSeconds) ?? 30
    }

    func redactingAPITokens() -> AccountPoolSnapshot {
        AccountPoolSnapshot(
            accounts: accounts.map { $0.redactingAPIToken() },
            groups: groups,
            activities: activities,
            mode: mode,
            activeAccountID: activeAccountID,
            manualAccountID: manualAccountID,
            focusLockedAccountID: focusLockedAccountID,
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            lowUsageAlertThresholdRatio: lowUsageAlertThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch,
            lastSwitchAt: lastSwitchAt,
            lastUsageSyncAt: lastUsageSyncAt,
            switchWithoutLaunching: switchWithoutLaunching,
            autoSyncEnabled: autoSyncEnabled,
            autoSyncIntervalSeconds: autoSyncIntervalSeconds
        )
    }
}

struct AccountPoolState {
    private(set) var accounts: [AgentAccount]
    private(set) var groups: [String]
    private(set) var activities: [PoolActivity]
    private(set) var mode: SwitchMode
    private(set) var activeAccountID: UUID?
    private(set) var manualAccountID: UUID?

    private var focusLockedAccountID: UUID?
    private var lastSwitchAt: Date?
    private(set) var lastUsageSyncAt: Date?

    private(set) var minSwitchInterval: TimeInterval
    private(set) var lowUsageThresholdRatio: Double
    private(set) var lowUsageAlertThresholdRatio: Double
    private(set) var minUsageRatioDeltaToSwitch: Double
    private(set) var switchWithoutLaunching: Bool
    private(set) var autoSyncEnabled: Bool
    private(set) var autoSyncIntervalSeconds: TimeInterval

    init(
        accounts: [AgentAccount],
        mode: SwitchMode = .intelligent,
        minSwitchInterval: TimeInterval = 300,
        lowUsageThresholdRatio: Double = 0.15,
        lowUsageAlertThresholdRatio: Double? = nil,
        minUsageRatioDeltaToSwitch: Double = 0,
        switchWithoutLaunching: Bool = false,
        autoSyncEnabled: Bool = true,
        autoSyncIntervalSeconds: TimeInterval = 30
    ) {
        self.accounts = accounts
        self.groups = []
        self.activities = []
        self.mode = mode
        self.activeAccountID = nil
        self.manualAccountID = accounts.first?.id
        self.focusLockedAccountID = nil
        self.lastSwitchAt = nil
        self.lastUsageSyncAt = nil
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
        self.lowUsageAlertThresholdRatio = lowUsageAlertThresholdRatio ?? lowUsageThresholdRatio
        self.minUsageRatioDeltaToSwitch = max(0, min(0.5, minUsageRatioDeltaToSwitch))
        self.switchWithoutLaunching = switchWithoutLaunching
        self.autoSyncEnabled = autoSyncEnabled
        self.autoSyncIntervalSeconds = max(5, min(300, autoSyncIntervalSeconds))
        rebuildGroups()
    }

    init(snapshot: AccountPoolSnapshot) {
        self.accounts = snapshot.accounts
        self.groups = snapshot.groups
        self.activities = snapshot.activities
        self.mode = snapshot.mode
        self.activeAccountID = snapshot.activeAccountID
        self.manualAccountID = snapshot.manualAccountID
        self.focusLockedAccountID = snapshot.focusLockedAccountID
        self.lastSwitchAt = snapshot.lastSwitchAt
        self.lastUsageSyncAt = snapshot.lastUsageSyncAt
        self.switchWithoutLaunching = snapshot.switchWithoutLaunching
        self.autoSyncEnabled = snapshot.autoSyncEnabled
        self.autoSyncIntervalSeconds = max(5, min(300, snapshot.autoSyncIntervalSeconds))
        self.minSwitchInterval = max(30, snapshot.minSwitchInterval)
        self.lowUsageThresholdRatio = min(0.9, max(0.01, snapshot.lowUsageThresholdRatio))
        self.lowUsageAlertThresholdRatio = min(0.9, max(0.01, snapshot.lowUsageAlertThresholdRatio))
        self.minUsageRatioDeltaToSwitch = min(0.5, max(0, snapshot.minUsageRatioDeltaToSwitch))
        rebuildGroups()
        evaluate(now: .now)
    }

    var activeAccount: AgentAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first(where: { $0.id == activeAccountID })
    }

    var hasLowUsageWarning: Bool {
        guard let activeAccount else { return false }
        return intelligentRemainingRatio(for: activeAccount) <= lowUsageAlertThresholdRatio
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
            groups: groups,
            activities: activities,
            mode: mode,
            activeAccountID: activeAccountID,
            manualAccountID: manualAccountID,
            focusLockedAccountID: focusLockedAccountID,
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            lowUsageAlertThresholdRatio: lowUsageAlertThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch,
            lastSwitchAt: lastSwitchAt,
            lastUsageSyncAt: lastUsageSyncAt,
            switchWithoutLaunching: switchWithoutLaunching,
            autoSyncEnabled: autoSyncEnabled,
            autoSyncIntervalSeconds: autoSyncIntervalSeconds
        )
    }

    mutating func updateSwitchSettings(
        minSwitchInterval: TimeInterval? = nil,
        lowUsageThresholdRatio: Double? = nil,
        lowUsageAlertThresholdRatio: Double? = nil,
        minUsageRatioDeltaToSwitch: Double? = nil,
        now: Date = .now
    ) {
        if let minSwitchInterval {
            self.minSwitchInterval = max(30, minSwitchInterval)
        }
        if let lowUsageThresholdRatio {
            self.lowUsageThresholdRatio = min(0.9, max(0.01, lowUsageThresholdRatio))
        }
        if let lowUsageAlertThresholdRatio {
            self.lowUsageAlertThresholdRatio = min(0.9, max(0.01, lowUsageAlertThresholdRatio))
        }
        if let minUsageRatioDeltaToSwitch {
            self.minUsageRatioDeltaToSwitch = min(0.5, max(0, minUsageRatioDeltaToSwitch))
        }
        evaluate(now: now)
    }

    mutating func setSwitchWithoutLaunching(_ value: Bool, now: Date = .now) {
        switchWithoutLaunching = value
        evaluate(now: now)
    }

    mutating func setAutoSyncEnabled(_ value: Bool, now: Date = .now) {
        autoSyncEnabled = value
        evaluate(now: now)
    }

    mutating func setAutoSyncIntervalSeconds(_ value: TimeInterval, now: Date = .now) {
        autoSyncIntervalSeconds = max(5, min(300, value))
        evaluate(now: now)
    }

    @discardableResult
    mutating func createGroup(_ name: String) -> String? {
        let normalized = AgentAccount.normalizedGroupName(name)
        if groups.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            return nil
        }
        groups.append(normalized)
        return normalized
    }

    mutating func renameGroup(from oldName: String, to newName: String, now: Date = .now) {
        let normalizedOld = AgentAccount.normalizedGroupName(oldName)
        let normalizedNew = AgentAccount.normalizedGroupName(newName)
        guard normalizedOld.caseInsensitiveCompare(normalizedNew) != .orderedSame else { return }
        guard !groups.contains(where: { $0.caseInsensitiveCompare(normalizedNew) == .orderedSame }) else { return }
        guard let index = groups.firstIndex(where: { $0.caseInsensitiveCompare(normalizedOld) == .orderedSame }) else { return }
        groups[index] = normalizedNew
        for accountIndex in accounts.indices where accounts[accountIndex].groupName.caseInsensitiveCompare(normalizedOld) == .orderedSame {
            accounts[accountIndex].groupName = normalizedNew
        }
        evaluate(now: now)
    }

    func canIntelligentSwitch(now: Date = .now) -> Bool {
        guard mode == .intelligent else { return false }
        guard let candidateID = intelligentCandidateAccountID(),
              let candidate = accounts.first(where: { $0.id == candidateID })
        else {
            return false
        }

        guard let current = activeAccount else {
            return true
        }

        guard current.id != candidate.id else { return false }

        let currentRemainingRatio = intelligentRemainingRatio(for: current)
        let candidateRemainingRatio = intelligentRemainingRatio(for: candidate)

        if currentRemainingRatio <= 0 {
            return true
        }

        guard currentRemainingRatio <= lowUsageThresholdRatio else {
            return false
        }

        guard candidateRemainingRatio > currentRemainingRatio else {
            return false
        }

        return switchCooldownRemaining(now: now) == 0
    }

    func intelligentSwitchCooldownRemaining(now: Date = .now) -> Int {
        guard mode == .intelligent else { return 0 }
        guard let candidateID = intelligentCandidateAccountID(),
              let candidate = accounts.first(where: { $0.id == candidateID }),
              let current = activeAccount
        else {
            return 0
        }

        guard current.id != candidate.id else { return 0 }
        let currentRemainingRatio = intelligentRemainingRatio(for: current)
        let candidateRemainingRatio = intelligentRemainingRatio(for: candidate)
        guard currentRemainingRatio > 0 else { return 0 }
        guard currentRemainingRatio <= lowUsageThresholdRatio else { return 0 }
        guard candidateRemainingRatio > currentRemainingRatio else { return 0 }

        return switchCooldownRemaining(now: now)
    }

    mutating func setMode(_ newMode: SwitchMode, now: Date = .now) {
        if mode != newMode {
            let previousActiveAccountID = activeAccountID
            mode = newMode
            if newMode == .focus {
                // Preserve the current account when entering focus mode so the UI
                // doesn't unexpectedly jump to a different account.
                focusLockedAccountID = previousActiveAccountID
            } else {
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

    mutating func markActiveAccountForSwitchLaunch(_ accountID: UUID, now: Date = .now) {
        switchActive(to: accountID, now: now)
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
        groupName: String = AgentAccount.defaultGroupName,
        quota: Int,
        usedUnits: Int = 0,
        email: String? = nil,
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        now: Date = .now
    ) -> UUID {
        let normalizedQuota = max(1, quota)
        let normalizedUsedUnits = max(0, min(usedUnits, normalizedQuota))
        let normalizedGroupName = ensureGroupExists(groupName)
        let account = AgentAccount(
            id: UUID(),
            name: name.isEmpty ? L10n.text("account.unnamed") : name,
            groupName: normalizedGroupName,
            usedUnits: normalizedUsedUnits,
            quota: normalizedQuota,
            email: email,
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

        rebuildGroups()
        evaluate(now: now)
    }

    mutating func updateAccount(
        _ accountID: UUID,
        name: String? = nil,
        groupName: String? = nil,
        quota: Int? = nil,
        usedUnits: Int? = nil,
        apiToken: String? = nil,
        email: String? = nil,
        chatGPTAccountID: String? = nil,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        primaryUsagePercent: Int? = nil,
        primaryUsageResetAt: Date? = nil,
        secondaryUsagePercent: Int? = nil,
        secondaryUsageResetAt: Date? = nil,
        isPaid: Bool? = nil,
        now: Date = .now
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        if let name {
            accounts[index].name = name.isEmpty ? L10n.text("account.unnamed") : name
        }
        if let groupName {
            accounts[index].groupName = ensureGroupExists(groupName)
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
        if let email {
            accounts[index].email = email
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
        if let primaryUsagePercent {
            accounts[index].primaryUsagePercent = min(max(primaryUsagePercent, 0), 100)
        }
        if let primaryUsageResetAt {
            accounts[index].primaryUsageResetAt = primaryUsageResetAt
        }
        if let secondaryUsagePercent {
            accounts[index].secondaryUsagePercent = min(max(secondaryUsagePercent, 0), 100)
        }
        if let secondaryUsageResetAt {
            accounts[index].secondaryUsageResetAt = secondaryUsageResetAt
        }
        if let isPaid {
            accounts[index].isPaid = isPaid
        }

        accounts[index].usedUnits = min(accounts[index].usedUnits, accounts[index].quota)
        evaluate(now: now)
    }

    @discardableResult
    mutating func duplicateAccount(
        _ accountID: UUID,
        intoGroup targetGroupName: String? = nil,
        now: Date = .now
    ) -> UUID? {
        guard let source = accounts.first(where: { $0.id == accountID }) else { return nil }
        let resolvedGroupName = targetGroupName.map { ensureGroupExists($0) } ?? source.groupName
        let copy = AgentAccount(
            id: UUID(),
            createdAt: now,
            name: source.name,
            groupName: resolvedGroupName,
            usedUnits: source.usedUnits,
            quota: source.quota,
            apiToken: source.apiToken,
            email: source.email,
            chatGPTAccountID: source.chatGPTAccountID,
            usageWindowName: source.usageWindowName,
            usageWindowResetAt: source.usageWindowResetAt,
            primaryUsagePercent: source.primaryUsagePercent,
            primaryUsageResetAt: source.primaryUsageResetAt,
            secondaryUsagePercent: source.secondaryUsagePercent,
            secondaryUsageResetAt: source.secondaryUsageResetAt,
            isPaid: source.isPaid,
            isUsageSyncExcluded: source.isUsageSyncExcluded,
            usageSyncError: source.usageSyncError
        )
        accounts.append(copy)
        appendActivity(String(format: L10n.text("activity.account_added_format"), copy.name), now: now)
        evaluate(now: now)
        return copy.id
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
            guard let candidateID = intelligentCandidateAccountID(),
                  let candidate = accounts.first(where: { $0.id == candidateID })
            else {
                // Keep the current active account when candidates are temporarily unavailable.
                // This prevents a later recovery cycle from forcing a switch without threshold checks.
                if let activeAccountID,
                   accounts.contains(where: { $0.id == activeAccountID }) {
                    return
                }
                activeAccountID = nil
                return
            }

            guard let current = activeAccount else {
                switchActive(to: candidate.id, now: now)
                return
            }

            let currentRemainingRatio = intelligentRemainingRatio(for: current)
            let candidateRemainingRatio = intelligentRemainingRatio(for: candidate)

            if currentRemainingRatio <= 0 {
                switchActive(to: candidate.id, now: now)
                return
            }

            guard current.id != candidate.id else {
                return
            }

            guard currentRemainingRatio <= lowUsageThresholdRatio else {
                return
            }

            guard candidateRemainingRatio > currentRemainingRatio else {
                return
            }

            guard switchCooldownRemaining(now: now) == 0 else {
                return
            }

            switchActive(to: candidate.id, now: now)
        }
    }

    private func intelligentCandidateAccountID() -> UUID? {
        let availableAccounts = syncIncludedAccounts.filter { intelligentRemainingRatio(for: $0) > 0 }
        guard !availableAccounts.isEmpty else { return nil }

        return availableAccounts
            .sorted {
                let lhsRemainingRatio = intelligentRemainingRatio(for: $0)
                let rhsRemainingRatio = intelligentRemainingRatio(for: $1)
                if lhsRemainingRatio == rhsRemainingRatio {
                    if $0.usageRatio == $1.usageRatio {
                        return $0.remainingUnits > $1.remainingUnits
                    }
                    return $0.usageRatio < $1.usageRatio
                }
                return lhsRemainingRatio > rhsRemainingRatio
            }
            .first?
            .id
    }

    private func intelligentRemainingRatio(for account: AgentAccount) -> Double {
        if account.isPaid, let primaryUsagePercent = account.primaryUsagePercent {
            let clampedUsagePercent = min(max(primaryUsagePercent, 0), 100)
            return Double(100 - clampedUsagePercent) / 100
        }
        return account.remainingRatio
    }

    private func bestRemainingAccountID() -> UUID? {
        syncIncludedAccounts.max(by: { $0.remainingUnits < $1.remainingUnits })?.id
    }

    private var syncIncludedAccounts: [AgentAccount] {
        accounts.filter { !$0.isUsageSyncExcluded }
    }

    private func switchCooldownRemaining(now: Date) -> Int {
        guard let lastSwitchAt else { return 0 }
        let elapsed = now.timeIntervalSince(lastSwitchAt)
        let remaining = minSwitchInterval - elapsed
        guard remaining > 0 else { return 0 }
        return Int(ceil(remaining))
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

    @discardableResult
    private mutating func ensureGroupExists(_ name: String) -> String {
        let normalized = AgentAccount.normalizedGroupName(name)
        if !groups.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
            groups.append(normalized)
        }
        return normalized
    }

    private mutating func rebuildGroups() {
        var nextGroups = groups.map { AgentAccount.normalizedGroupName($0) }
        if !nextGroups.contains(where: { $0.caseInsensitiveCompare(AgentAccount.defaultGroupName) == .orderedSame }) {
            nextGroups.append(AgentAccount.defaultGroupName)
        }
        for account in accounts {
            let normalized = AgentAccount.normalizedGroupName(account.groupName)
            if !nextGroups.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                nextGroups.append(normalized)
            }
        }
        groups = nextGroups
    }
}

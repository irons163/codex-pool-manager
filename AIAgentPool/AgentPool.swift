import Foundation

struct AgentAccount: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var usedUnits: Int
    var quota: Int

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
}

enum SwitchMode: String, CaseIterable, Identifiable, Codable {
    case intelligent = "智能切換"
    case manual = "手動切換"
    case focus = "專注模式"

    var id: String { rawValue }
}

struct LowUsageAlertPolicy {
    private var lowWarningWasActive = false

    mutating func shouldTriggerAlert(mode: SwitchMode, hasLowUsageWarning: Bool) -> Bool {
        let isCurrentlyLow = (mode == .focus) && hasLowUsageWarning
        defer { lowWarningWasActive = isCurrentlyLow }
        return isCurrentlyLow && !lowWarningWasActive
    }
}

struct AccountPoolSnapshot: Codable, Equatable {
    var accounts: [AgentAccount]
    var mode: SwitchMode
    var activeAccountID: UUID?
    var manualAccountID: UUID?
    var focusLockedAccountID: UUID?
    var minSwitchInterval: TimeInterval
    var lowUsageThresholdRatio: Double
    var minUsageRatioDeltaToSwitch: Double
}

struct AccountPoolState {
    private(set) var accounts: [AgentAccount]
    private(set) var mode: SwitchMode
    private(set) var activeAccountID: UUID?
    private(set) var manualAccountID: UUID?

    private var focusLockedAccountID: UUID?
    private var lastSwitchAt: Date?

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
        self.mode = mode
        self.activeAccountID = nil
        self.manualAccountID = accounts.first?.id
        self.focusLockedAccountID = nil
        self.lastSwitchAt = nil
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
        self.minUsageRatioDeltaToSwitch = max(0, min(0.5, minUsageRatioDeltaToSwitch))
    }

    init(snapshot: AccountPoolSnapshot) {
        self.accounts = snapshot.accounts
        self.mode = snapshot.mode
        self.activeAccountID = snapshot.activeAccountID
        self.manualAccountID = snapshot.manualAccountID
        self.focusLockedAccountID = snapshot.focusLockedAccountID
        self.lastSwitchAt = nil
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

    var snapshot: AccountPoolSnapshot {
        AccountPoolSnapshot(
            accounts: accounts,
            mode: mode,
            activeAccountID: activeAccountID,
            manualAccountID: manualAccountID,
            focusLockedAccountID: focusLockedAccountID,
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch
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
        now: Date = .now
    ) -> UUID {
        let normalizedQuota = max(1, quota)
        let normalizedUsedUnits = max(0, min(usedUnits, normalizedQuota))
        let account = AgentAccount(
            id: UUID(),
            name: name.isEmpty ? "未命名帳號" : name,
            usedUnits: normalizedUsedUnits,
            quota: normalizedQuota
        )
        accounts.append(account)

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
        now: Date = .now
    ) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }

        if let name {
            accounts[index].name = name.isEmpty ? "未命名帳號" : name
        }
        if let quota {
            accounts[index].quota = max(1, quota)
        }
        if let usedUnits {
            accounts[index].usedUnits = max(0, usedUnits)
        }

        accounts[index].usedUnits = min(accounts[index].usedUnits, accounts[index].quota)
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
        let availableAccounts = accounts.filter { $0.remainingUnits > 0 }
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
        accounts.max(by: { $0.remainingUnits < $1.remainingUnits })?.id
    }

    private mutating func switchActive(to accountID: UUID, now: Date) {
        let validID = accounts.contains(where: { $0.id == accountID }) ? accountID : accounts[0].id
        if activeAccountID != validID {
            activeAccountID = validID
            lastSwitchAt = now
        }
    }
}

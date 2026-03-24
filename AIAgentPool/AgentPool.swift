import Foundation

struct AgentAccount: Identifiable, Equatable {
    let id: UUID
    var name: String
    var usedUnits: Int
    let quota: Int

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

enum SwitchMode: String, CaseIterable, Identifiable {
    case intelligent = "智能切換"
    case manual = "手動切換"
    case focus = "專注模式"

    var id: String { rawValue }
}

struct AccountPoolState {
    private(set) var accounts: [AgentAccount]
    private(set) var mode: SwitchMode
    private(set) var activeAccountID: UUID?
    private(set) var manualAccountID: UUID?

    private var focusLockedAccountID: UUID?
    private var lastSwitchAt: Date?

    let minSwitchInterval: TimeInterval
    let lowUsageThresholdRatio: Double

    init(
        accounts: [AgentAccount],
        mode: SwitchMode = .intelligent,
        minSwitchInterval: TimeInterval = 300,
        lowUsageThresholdRatio: Double = 0.15
    ) {
        self.accounts = accounts
        self.mode = mode
        self.activeAccountID = nil
        self.manualAccountID = accounts.first?.id
        self.focusLockedAccountID = nil
        self.lastSwitchAt = nil
        self.minSwitchInterval = minSwitchInterval
        self.lowUsageThresholdRatio = lowUsageThresholdRatio
    }

    var activeAccount: AgentAccount? {
        guard let activeAccountID else { return nil }
        return accounts.first(where: { $0.id == activeAccountID })
    }

    var hasLowUsageWarning: Bool {
        guard let activeAccount else { return false }
        return activeAccount.remainingRatio <= lowUsageThresholdRatio
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

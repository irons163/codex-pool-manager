import SwiftUI

struct PoolDashboardAccountBindingAdapter {
    let state: Binding<AccountPoolState>

    func nameBinding(for accountID: UUID) -> Binding<String> {
        Binding(
            get: { account(for: accountID)?.name ?? "" },
            set: { newName in
                state.wrappedValue.updateAccount(accountID, name: newName)
            }
        )
    }

    func quotaBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: { account(for: accountID)?.quota ?? 100 },
            set: { newQuota in
                state.wrappedValue.updateAccount(accountID, quota: newQuota)
            }
        )
    }

    func usedBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: { account(for: accountID)?.usedUnits ?? 0 },
            set: { newUsed in
                state.wrappedValue.updateAccount(accountID, usedUnits: newUsed)
            }
        )
    }

    private func account(for accountID: UUID) -> AgentAccount? {
        state.wrappedValue.accounts.first(where: { $0.id == accountID })
    }
}

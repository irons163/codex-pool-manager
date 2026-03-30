import SwiftUI

struct PoolDashboardAccountBindingAdapter {
    let state: Binding<AccountPoolState>

    func nameBinding(for accountID: UUID) -> Binding<String> {
        Binding(
            get: {
                accountValue(for: accountID, defaultValue: "") { $0.name }
            },
            set: { newName in
                state.wrappedValue.updateAccount(accountID, name: newName)
            }
        )
    }

    func quotaBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                accountValue(for: accountID, defaultValue: 100) { $0.quota }
            },
            set: { newQuota in
                state.wrappedValue.updateAccount(accountID, quota: newQuota)
            }
        )
    }

    func groupNameBinding(for accountID: UUID) -> Binding<String> {
        Binding(
            get: {
                accountValue(for: accountID, defaultValue: AgentAccount.defaultGroupName) { $0.groupName }
            },
            set: { newGroupName in
                state.wrappedValue.updateAccount(accountID, groupName: newGroupName)
            }
        )
    }

    func usedBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                accountValue(for: accountID, defaultValue: 0) { $0.usedUnits }
            },
            set: { newUsed in
                state.wrappedValue.updateAccount(accountID, usedUnits: newUsed)
            }
        )
    }

    private func accountValue<T>(
        for accountID: UUID,
        defaultValue: T,
        transform: (AgentAccount) -> T
    ) -> T {
        guard let account = state.wrappedValue.accounts.first(where: { $0.id == accountID }) else {
            return defaultValue
        }
        return transform(account)
    }
}

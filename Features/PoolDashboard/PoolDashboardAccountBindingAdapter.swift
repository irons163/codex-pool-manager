import SwiftUI

struct PoolDashboardAccountBindingAdapter {
    let state: Binding<AccountPoolState>

    func nameBinding(for accountID: UUID) -> Binding<String> {
        Binding(
            get: {
                state.wrappedValue.accounts.first(where: { $0.id == accountID })?.name ?? ""
            },
            set: { newName in
                state.wrappedValue.updateAccount(accountID, name: newName)
            }
        )
    }

    func quotaBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                state.wrappedValue.accounts.first(where: { $0.id == accountID })?.quota ?? 100
            },
            set: { newQuota in
                state.wrappedValue.updateAccount(accountID, quota: newQuota)
            }
        )
    }

    func usedBinding(for accountID: UUID) -> Binding<Int> {
        Binding(
            get: {
                state.wrappedValue.accounts.first(where: { $0.id == accountID })?.usedUnits ?? 0
            },
            set: { newUsed in
                state.wrappedValue.updateAccount(accountID, usedUnits: newUsed)
            }
        )
    }
}

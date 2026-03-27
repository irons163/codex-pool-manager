import Foundation

struct PoolDashboardAccountFormFlowCoordinator {
    struct AddAccountOutput {
        let state: AccountPoolState
        let formState: PoolDashboardFormState
    }

    private let actionFlowCoordinator = PoolDashboardActionFlowCoordinator()

    func addAccount(
        from state: AccountPoolState,
        formState: PoolDashboardFormState,
        name: String,
        quota: Int,
        defaultQuota: Int = PoolDashboardFormState.defaultQuota
    ) -> AddAccountOutput {
        let nextState = actionFlowCoordinator.addAccount(to: state, name: name, quota: quota)
        var nextFormState = formState
        nextFormState.resetNewAccountInput(defaultQuota: defaultQuota)
        return makeAddAccountOutput(state: nextState, formState: nextFormState)
    }

    private func makeAddAccountOutput(
        state: AccountPoolState,
        formState: PoolDashboardFormState
    ) -> AddAccountOutput {
        AddAccountOutput(state: state, formState: formState)
    }
}

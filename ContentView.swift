import SwiftUI

struct ContentView: View {
    var body: some View {
        if AppRuntimeStorage.isRunningXCTest {
            PoolDashboardView(store: AppRuntimeStorage.accountPoolStore)
        } else {
            PoolDashboardView()
        }
    }
}

#Preview {
    PoolDashboardView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}

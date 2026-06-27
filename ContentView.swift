import SwiftUI

struct ContentView: View {
    @ObservedObject var runtimeModel: AppPoolRuntimeModel

    var body: some View {
        if AppRuntimeStorage.isRunningXCTest {
            PoolDashboardView(
                store: AppRuntimeStorage.accountPoolStore,
                runtimeModel: runtimeModel
            )
        } else {
            PoolDashboardView(runtimeModel: runtimeModel)
        }
    }
}

#Preview {
    let store = UserDefaultsAccountPoolStore(
        defaults: .standard,
        key: "preview_account_pool_snapshot"
    )
    let runtimeModel = AppPoolRuntimeModel(store: store)
    ContentView(runtimeModel: runtimeModel)
}

import SwiftUI

struct ContentView: View {
    private let store: AccountPoolStoring

    init(store: AccountPoolStoring = DeveloperAwareAccountPoolStore()) {
        self.store = store
    }

    var body: some View {
        PoolDashboardView(store: store)
    }
}

#Preview {
    ContentView(store: UserDefaultsAccountPoolStore(defaults: .standard, key: "preview_account_pool_snapshot"))
}

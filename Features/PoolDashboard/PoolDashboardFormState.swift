import Foundation

struct PoolDashboardFormState {
    var newAccountName = ""
    var newAccountQuota = 1000

    var oauthAccountName = ""
    var oauthAccountQuota = 1000

    mutating func resetNewAccountInput(defaultQuota: Int = 1000) {
        newAccountName = ""
        newAccountQuota = defaultQuota
    }

    mutating func applyOAuthAccountName(_ name: String) {
        oauthAccountName = name
    }
}

import Foundation

struct PoolDashboardFormState {
    static let defaultQuota = 1000

    var newAccountName = ""
    var newAccountQuota = Self.defaultQuota

    var oauthAccountName = ""
    var oauthAccountQuota = Self.defaultQuota

    mutating func resetNewAccountInput(defaultQuota: Int = Self.defaultQuota) {
        newAccountName = ""
        newAccountQuota = defaultQuota
    }

    mutating func applyOAuthAccountName(_ name: String) {
        oauthAccountName = name
    }
}

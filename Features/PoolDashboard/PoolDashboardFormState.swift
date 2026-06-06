import Foundation

struct PoolDashboardFormState {
    static let defaultQuota = 1000
    static let defaultRelayProviderID = "mirror"
    static let defaultRelayBaseURL = ""

    var newAccountName = ""
    var newAccountQuota = Self.defaultQuota

    var oauthAccountName = ""
    var oauthAccountQuota = Self.defaultQuota

    var relayAccountName = ""
    var relayProviderID = Self.defaultRelayProviderID
    var relayProviderName = Self.defaultRelayProviderID
    var relayBaseURL = Self.defaultRelayBaseURL
    var relayWireAPI = AgentAccount.defaultRelayWireAPI
    var relayAPIKey = ""

    mutating func resetNewAccountInput(defaultQuota: Int = Self.defaultQuota) {
        newAccountName = ""
        newAccountQuota = defaultQuota
    }

    mutating func applyOAuthAccountName(_ name: String) {
        oauthAccountName = name
    }

    mutating func resetRelayInput() {
        relayAccountName = ""
        relayProviderID = Self.defaultRelayProviderID
        relayProviderName = Self.defaultRelayProviderID
        relayBaseURL = Self.defaultRelayBaseURL
        relayWireAPI = AgentAccount.defaultRelayWireAPI
        relayAPIKey = ""
    }
}

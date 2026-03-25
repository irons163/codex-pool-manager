import Foundation

struct PoolDashboardViewState {
    var showLowUsageAlert = false
    var isSyncingUsage = false
    var isSigningInOAuth = false

    var backupJSON = ""
    var backupError: String?

    var syncError: String?
    var lastUsageRawJSON = ""
    var showUsageRawJSON = false

    var oauthError: String?
    var oauthSuccessMessage: String?

    var lastSwitchLaunchLog = ""
    var showSwitchLaunchLog = false
}

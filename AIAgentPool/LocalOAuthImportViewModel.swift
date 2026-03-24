import Foundation

struct LocalOAuthImportViewModel {
    enum ImportDecision: Equatable {
        case importAccount(name: String, accessToken: String, chatGPTAccountID: String)
        case missingAccountID
        case duplicate
    }

    var accounts: [LocalCodexOAuthAccount] = []
    var errorMessage: String?

    mutating func applyAutomaticScanResult(_ discovered: [LocalCodexOAuthAccount]) {
        accounts = discovered
        if discovered.isEmpty {
            errorMessage = "自動掃描沒有讀到帳號，可能是 macOS Sandbox 限制。請按「選擇 auth.json」授權。"
        } else {
            errorMessage = nil
        }
    }

    mutating func applyLoadedAccountsFromFile(_ loadedAccounts: [LocalCodexOAuthAccount]) {
        accounts = loadedAccounts
        if loadedAccounts.isEmpty {
            errorMessage = "檔案格式可讀，但未找到 access token"
        } else {
            errorMessage = nil
        }
    }

    mutating func applyReadFailure(_ error: Error) {
        errorMessage = "讀取失敗：\(error.localizedDescription)"
    }

    mutating func applyBookmarkSaveFailure(_ error: Error) {
        errorMessage = "儲存授權失敗：\(error.localizedDescription)"
    }

    mutating func applyBookmarkInvalid() {
        errorMessage = "授權已失效，請重新選擇 auth.json"
    }

    mutating func prepareImport(
        _ account: LocalCodexOAuthAccount,
        existingAccessTokens: Set<String>
    ) -> ImportDecision {
        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            errorMessage = "auth.json 缺少 ChatGPT Account ID，無法查詢用量"
            return .missingAccountID
        }
        if existingAccessTokens.contains(account.accessToken) {
            errorMessage = "此帳號已在帳號池"
            return .duplicate
        }

        errorMessage = nil
        let name = account.email ?? account.displayName
        return .importAccount(name: name, accessToken: account.accessToken, chatGPTAccountID: chatGPTAccountID)
    }
}

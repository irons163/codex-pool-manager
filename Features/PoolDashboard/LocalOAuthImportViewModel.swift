import Foundation

struct LocalOAuthImportViewModel {
    enum ImportDecision: Equatable {
        case importAccount(name: String, accessToken: String, chatGPTAccountID: String)
        case missingAccountID
    }

    var accounts: [LocalCodexOAuthAccount] = []
    var errorMessage: String?

    mutating func applyAutomaticScanResult(_ discovered: [LocalCodexOAuthAccount]) {
        accounts = discovered
        if discovered.isEmpty {
            errorMessage = L10n.text("local_import.auto_scan_empty")
        } else {
            errorMessage = nil
        }
    }

    mutating func applyLoadedAccountsFromFile(_ loadedAccounts: [LocalCodexOAuthAccount]) {
        accounts = loadedAccounts
        if loadedAccounts.isEmpty {
            errorMessage = L10n.text("local_import.file_readable_but_no_token")
        } else {
            errorMessage = nil
        }
    }

    mutating func applyReadFailure(_ error: Error) {
        errorMessage = L10n.text("local_import.read_failure_format", error.localizedDescription)
    }

    mutating func applyBookmarkSaveFailure(_ error: Error) {
        errorMessage = L10n.text("local_import.bookmark_save_failure_format", error.localizedDescription)
    }

    mutating func applyBookmarkInvalid() {
        errorMessage = L10n.text("local_import.bookmark_invalid")
    }

    mutating func prepareImport(
        _ account: LocalCodexOAuthAccount,
        existingAccessTokens: Set<String>
    ) -> ImportDecision {
        _ = existingAccessTokens
        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            errorMessage = L10n.text("auth.missing_chatgpt_account_id")
            return .missingAccountID
        }
        // Duplicates are resolved by upsert in ContentView import flow.
        errorMessage = nil
        let name = account.email ?? account.displayName
        return .importAccount(name: name, accessToken: account.accessToken, chatGPTAccountID: chatGPTAccountID)
    }
}

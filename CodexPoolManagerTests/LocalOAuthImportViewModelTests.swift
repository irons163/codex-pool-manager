import Foundation
import Testing
@testable import CodexPoolManager

struct LocalOAuthImportViewModelTests {
    @Test
    func automaticScanEmptyShowsSandboxHint() {
        var viewModel = LocalOAuthImportViewModel()
        viewModel.successMessage = "old-success"

        viewModel.applyAutomaticScanResult([])

        #expect(viewModel.accounts.isEmpty)
        #expect(viewModel.successMessage == nil)
        #expect(viewModel.errorMessage == L10n.text("local_import.auto_scan_empty"))
    }

    @Test
    func loadedAccountsFromFileClearsError() {
        var viewModel = LocalOAuthImportViewModel()
        viewModel.errorMessage = "old"

        viewModel.applyLoadedAccountsFromFile([sampleAccount(email: "user@example.com", token: "sk-abc123456")])

        #expect(viewModel.accounts.count == 1)
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func loadedEmptyAccountsFromFileShowsFormatError() {
        var viewModel = LocalOAuthImportViewModel()

        viewModel.applyLoadedAccountsFromFile([])

        #expect(viewModel.errorMessage == L10n.text("local_import.file_readable_but_no_token"))
    }

    @Test
    func prepareImportDuplicateTokenStillReturnsImportDecisionForUpsert() {
        var viewModel = LocalOAuthImportViewModel()
        let account = sampleAccount(email: "dup@example.com", token: "sk-dup-token")

        let decision = viewModel.prepareImport(account, existingAccessTokens: ["sk-dup-token"])

        #expect(
            decision == .importAccount(
                name: "dup@example.com",
                accessToken: "sk-dup-token",
                chatGPTAccountID: "account-123"
            )
        )
        #expect(viewModel.errorMessage == nil)
    }

    @Test
    func prepareImportNewAccountReturnsImportDecision() {
        var viewModel = LocalOAuthImportViewModel()
        viewModel.errorMessage = "old"
        viewModel.successMessage = "old-success"
        let account = sampleAccount(email: "new@example.com", token: "sk-new-token")

        let decision = viewModel.prepareImport(account, existingAccessTokens: [])

        #expect(
            decision == .importAccount(
                name: "new@example.com",
                accessToken: "sk-new-token",
                chatGPTAccountID: "account-123"
            )
        )
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.successMessage == nil)
    }

    @Test
    func prepareImportMissingAccountIDReturnsMissingDecision() {
        var viewModel = LocalOAuthImportViewModel()
        viewModel.successMessage = "old-success"
        let account = LocalCodexOAuthAccount(
            id: UUID().uuidString,
            displayName: "Codex User",
            email: "missing@example.com",
            source: "~/.codex/auth.json",
            accessToken: "sk-missing-id",
            chatGPTAccountID: nil
        )

        let decision = viewModel.prepareImport(account, existingAccessTokens: [])

        #expect(decision == .missingAccountID)
        #expect(viewModel.successMessage == nil)
        #expect(viewModel.errorMessage == L10n.text("auth.missing_chatgpt_account_id"))
    }

    private func sampleAccount(email: String, token: String) -> LocalCodexOAuthAccount {
        LocalCodexOAuthAccount(
            id: UUID().uuidString,
            displayName: "Codex User",
            email: email,
            source: "~/.codex/auth.json",
            accessToken: token,
            chatGPTAccountID: "account-123"
        )
    }
}

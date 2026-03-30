import Foundation

struct PoolAccountUpsertCoordinator {
    func applyOAuthSignIn(
        state: inout AccountPoolState,
        tokens: OAuthTokens,
        claims: OAuthIDTokenClaims?,
        usage: CodexUsage?,
        accountNameInput: String,
        fallbackQuota: Int,
        now: Date = .now
    ) -> String {
        var resolvedAccountID = claims?.accountID ?? claims?.subject
        var resolvedEmail = claims?.email
        var resolvedQuota = fallbackQuota
        var resolvedUsedUnits = 0
        var resolvedWindowName: String?
        var resolvedWindowResetAt: Date?

        if let usage {
            resolvedAccountID = usage.accountID ?? resolvedAccountID
            resolvedEmail = usage.accountEmail ?? resolvedEmail
            resolvedQuota = usage.quota
            resolvedUsedUnits = usage.usedUnits
            resolvedWindowName = usage.usageWindowName
            resolvedWindowResetAt = usage.usageWindowResetAt
        }

        let trimmedInput = accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultOAuthAccountName = L10n.text("account.default_oauth_name")
        let resolvedAccountName = trimmedInput.isEmpty
            ? (resolvedEmail ?? defaultOAuthAccountName)
            : trimmedInput

        let existingAccountID = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: state.accounts,
            chatGPTAccountID: resolvedAccountID,
            accessToken: tokens.accessToken,
            email: resolvedEmail
        )

        if let existingAccountID {
            let existingAccount = state.accounts.first(where: { $0.id == existingAccountID })
            let shouldReplacePlaceholderName = trimmedInput.isEmpty
                && (
                    existingAccount?.name == L10n.text("account.default_oauth_name")
                    || existingAccount?.name == "OAuth Account"
                    || existingAccount?.name == "Codex OAuth"
                    || existingAccount?.name.isEmpty == true
                )
            let updatedName = trimmedInput.isEmpty
                ? (shouldReplacePlaceholderName ? resolvedAccountName : (existingAccount?.name ?? resolvedAccountName))
                : resolvedAccountName

            state.updateAccount(
                existingAccountID,
                name: updatedName,
                quota: resolvedQuota,
                usedUnits: resolvedUsedUnits,
                apiToken: tokens.accessToken,
                email: resolvedEmail,
                chatGPTAccountID: resolvedAccountID,
                usageWindowName: resolvedWindowName,
                usageWindowResetAt: resolvedWindowResetAt,
                now: now
            )
            return L10n.text("auth.sign_in_success_updated")
        }

        let newAccountID = state.addAccount(
            name: resolvedAccountName,
            quota: resolvedQuota,
            usedUnits: resolvedUsedUnits,
            email: resolvedEmail,
            chatGPTAccountID: resolvedAccountID,
            usageWindowName: resolvedWindowName,
            usageWindowResetAt: resolvedWindowResetAt,
            now: now
        )
        state.updateAccount(
            newAccountID,
            apiToken: tokens.accessToken,
            email: resolvedEmail,
            chatGPTAccountID: resolvedAccountID,
            usageWindowName: resolvedWindowName,
            usageWindowResetAt: resolvedWindowResetAt,
            now: now
        )
        return L10n.text("auth.sign_in_success_added")
    }

    func applyLocalImport(
        state: inout AccountPoolState,
        usage: CodexUsage,
        fallbackName: String,
        accessToken: String,
        chatGPTAccountID: String,
        now: Date = .now
    ) {
        let normalizedEmail = usage.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (normalizedEmail?.isEmpty == false) ? (normalizedEmail ?? fallbackName) : fallbackName
        let resolvedAccountID = usage.accountID ?? chatGPTAccountID

        let existingAccountID = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: state.accounts,
            chatGPTAccountID: resolvedAccountID,
            accessToken: accessToken,
            email: normalizedEmail
        )

        if let existingAccountID {
            state.updateAccount(
                existingAccountID,
                name: resolvedName,
                quota: usage.quota,
                usedUnits: usage.usedUnits,
                apiToken: accessToken,
                email: normalizedEmail,
                chatGPTAccountID: resolvedAccountID,
                usageWindowName: usage.usageWindowName,
                usageWindowResetAt: usage.usageWindowResetAt,
                now: now
            )
            return
        }

        let newAccountID = state.addAccount(
            name: resolvedName,
            quota: usage.quota,
            usedUnits: usage.usedUnits,
            email: normalizedEmail,
            chatGPTAccountID: resolvedAccountID,
            usageWindowName: usage.usageWindowName,
            usageWindowResetAt: usage.usageWindowResetAt,
            now: now
        )
        state.updateAccount(
            newAccountID,
            apiToken: accessToken,
            email: normalizedEmail,
            chatGPTAccountID: resolvedAccountID,
            usageWindowName: usage.usageWindowName,
            usageWindowResetAt: usage.usageWindowResetAt,
            now: now
        )
    }
}

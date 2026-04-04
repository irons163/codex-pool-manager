import Foundation

protocol OAuthLoginServicing {
    func signIn(configuration: OAuthClientConfiguration) async throws -> OAuthTokens
}

extension OAuthLoginService: OAuthLoginServicing {}

protocol CodexUsageFetching {
    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage
}

extension OpenAICodexUsageClient: CodexUsageFetching {}

enum PoolDashboardAuthFlowError: LocalizedError {
    case invalidConfiguration
    case invalidImportDecision

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return L10n.text("auth.invalid_configuration")
        case .invalidImportDecision:
            return L10n.text("auth.missing_chatgpt_account_id")
        }
    }
}

struct PoolDashboardAuthFlowCoordinator {
    private let accountUpsertCoordinator = PoolAccountUpsertCoordinator()

    struct OAuthSignInContext {
        let tokens: OAuthTokens
        let claims: OAuthIDTokenClaims?
        let usage: CodexUsage?
    }

    struct LocalImportContext {
        let name: String
        let accessToken: String
        let chatGPTAccountID: String
        let usage: CodexUsage
    }

    func buildConfiguration(
        issuer: String,
        clientID: String,
        scopes: String,
        redirectURI: String,
        originator: String,
        workspaceID: String
    ) throws -> OAuthClientConfiguration {
        guard
            let issuerURL = URL(string: issuer.trimmingCharacters(in: .whitespacesAndNewlines)),
            !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !scopes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !redirectURI.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw PoolDashboardAuthFlowError.invalidConfiguration
        }

        let normalizedWorkspaceID = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return OAuthClientConfiguration(
            issuer: issuerURL,
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            scopes: scopes.trimmingCharacters(in: .whitespacesAndNewlines),
            redirectURI: redirectURI.trimmingCharacters(in: .whitespacesAndNewlines),
            originator: originator.trimmingCharacters(in: .whitespacesAndNewlines),
            forcedWorkspaceID: normalizedWorkspaceID.isEmpty ? nil : normalizedWorkspaceID
        )
    }

    func fetchOAuthSignInContext(
        configuration: OAuthClientConfiguration,
        loginService: OAuthLoginServicing,
        usageClient: CodexUsageFetching
    ) async throws -> OAuthSignInContext {
        let tokens = try await loginService.signIn(configuration: configuration)
        return await makeOAuthSignInContext(
            tokens: tokens,
            usageClient: usageClient
        )
    }

    func makeOAuthSignInContext(
        tokens: OAuthTokens,
        usageClient: CodexUsageFetching
    ) async -> OAuthSignInContext {
        let claims = OAuthIDTokenClaimsParser.parse(tokens.idToken)

        var usage: CodexUsage?
        if let accountID = (claims?.accountID ?? claims?.subject), !accountID.isEmpty {
            do {
                usage = try await usageClient.fetchUsage(
                    accessToken: tokens.accessToken,
                    accountID: accountID
                )
            } catch {
                // Account should still be created and can be synced later.
            }
        }

        return OAuthSignInContext(
            tokens: tokens,
            claims: claims,
            usage: usage
        )
    }

    func applyOAuthSignIn(
        state: inout AccountPoolState,
        context: OAuthSignInContext,
        accountNameInput: String,
        fallbackQuota: Int
    ) -> String {
        accountUpsertCoordinator.applyOAuthSignIn(
            state: &state,
            tokens: context.tokens,
            claims: context.claims,
            usage: context.usage,
            accountNameInput: accountNameInput,
            fallbackQuota: fallbackQuota
        )
    }

    func fetchLocalImportContext(
        decision: LocalOAuthImportViewModel.ImportDecision,
        usageClient: CodexUsageFetching
    ) async throws -> LocalImportContext {
        guard case let .importAccount(name, accessToken, chatGPTAccountID) = decision else {
            throw PoolDashboardAuthFlowError.invalidImportDecision
        }

        let usage = try await usageClient.fetchUsage(
            accessToken: accessToken,
            accountID: chatGPTAccountID
        )
        return LocalImportContext(
            name: name,
            accessToken: accessToken,
            chatGPTAccountID: chatGPTAccountID,
            usage: usage
        )
    }

    func applyLocalImport(
        state: inout AccountPoolState,
        context: LocalImportContext
    ) {
        accountUpsertCoordinator.applyLocalImport(
            state: &state,
            usage: context.usage,
            fallbackName: context.name,
            accessToken: context.accessToken,
            chatGPTAccountID: context.chatGPTAccountID
        )
    }

    func localizedSyncError(_ error: Error) -> String {
        if let syncError = error as? CodexSyncError {
            return syncError.localizedDescription
        }

        if let http = error as? CodexClientHTTPError {
            if http.statusCode == 401 || http.statusCode == 403 {
                return CodexSyncError.unauthorized.localizedDescription
            }
            if http.statusCode == 429 {
                return CodexSyncError.rateLimited.localizedDescription
            }
            return CodexSyncError.unknown.localizedDescription
        }

        if error is URLError {
            return CodexSyncError.network.localizedDescription
        }

        return CodexSyncError.unknown.localizedDescription
    }
}

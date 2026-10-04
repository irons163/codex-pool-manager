import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct OAuthTokenRefreshRegressionTests {
    private let accountID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-000000000019")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let freshTokens = OAuthTokens(
        accessToken: "fresh-access",
        refreshToken: "fresh-refresh",
        idToken: "fresh-id"
    )

    private func makeState() -> AccountPoolState {
        AccountPoolState(
            accounts: [AgentAccount(
                id: accountID,
                name: "Refresh regression",
                usedUnits: 15,
                quota: 100,
                apiToken: "old-access",
                chatGPTAccountID: "acct-refresh",
                oauthRefreshToken: "old-refresh",
                oauthIDToken: "old-id"
            )],
            mode: .manual
        )
    }

    @Test(arguments: [
        "invalid_grant", "invalid_refresh_token", "token_expired",
        "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"
    ])
    func confirmedRefreshFailuresRequireSignIn(code: String) async throws {
        var state = makeState()
        let refreshRequests = LockedValue<[(refreshToken: String, clientID: String)]>([])
        let service = CodexUsageSyncService(
            client: MockCodexUsageClient(responseByToken: [:], shouldThrowError: CodexClientHTTPError(statusCode: 401)),
            oauthRefreshClient: StubOAuthTokenRefreshClient(
                requests: refreshRequests,
                result: .failure(OAuthTokenRefreshError.http(statusCode: 400, code: code))
            ),
            oauthConfiguration: .codexDefault
        )

        try await service.sync(state: &state, now: now)

        #expect(refreshRequests.value.count == 1)
        #expect(state.accounts[0].usageSyncError == CodexSyncError.oauthLoginExpired.localizedDescription)
        #expect(state.accounts[0].apiToken == "old-access")
        #expect(state.accounts[0].oauthRefreshToken == "old-refresh")
    }

    @Test(arguments: [URLError.Code.timedOut, .notConnectedToInternet, .networkConnectionLost])
    func refreshNetworkFailuresAreNotExpiredLogin(code: URLError.Code) async throws {
        var state = makeState()
        let service = CodexUsageSyncService(
            client: MockCodexUsageClient(responseByToken: [:], shouldThrowError: CodexClientHTTPError(statusCode: 401)),
            oauthRefreshClient: StubOAuthTokenRefreshClient(
                requests: LockedValue([]),
                result: .failure(URLError(code))
            ),
            oauthConfiguration: .codexDefault
        )

        try await service.sync(state: &state, now: now)

        #expect(state.accounts[0].usageSyncError == CodexSyncError.network.localizedDescription)
        #expect(state.accounts[0].oauthRefreshToken == "old-refresh")
        #expect(state.accounts[0].oauthLastRefreshAt == nil)
    }

    @Test(arguments: [400, 401, 403, 429, 500, 503])
    func nonTerminalRefreshHTTPFailuresPreserveTheirCategory(statusCode: Int) async throws {
        var state = makeState()
        let error = OAuthTokenRefreshError.http(statusCode: statusCode, code: "invalid_client")
        let service = CodexUsageSyncService(
            client: MockCodexUsageClient(responseByToken: [:], shouldThrowError: CodexClientHTTPError(statusCode: 401)),
            oauthRefreshClient: StubOAuthTokenRefreshClient(requests: LockedValue([]), result: .failure(error)),
            oauthConfiguration: .codexDefault
        )

        try await service.sync(state: &state, now: now)

        let expected: CodexSyncError = statusCode == 429
            ? .rateLimited
            : statusCode >= 500 ? .serviceUnavailable : .oauthRefreshFailed(error)
        #expect(state.accounts[0].usageSyncError == expected.localizedDescription)
        #expect(state.accounts[0].usageSyncError != CodexSyncError.oauthLoginExpired.localizedDescription)
        #expect(state.accounts[0].oauthRefreshToken == "old-refresh")
    }

    @Test(arguments: [401, 403, 429, 500, 503])
    func rotatedCredentialsSurviveUsageFailureAndAreUsedOnNextSync(statusCode: Int) async throws {
        var state = makeState()
        let usageRequests = LockedValue<[(token: String, accountID: String)]>([])
        let responses = LockedValue<[String: Result<CodexUsage, Error>]>([
            "old-access": .failure(CodexClientHTTPError(statusCode: 401)),
            "fresh-access": .failure(CodexClientHTTPError(statusCode: statusCode))
        ])
        let refreshRequests = LockedValue<[(refreshToken: String, clientID: String)]>([])
        let store = AppPoolRuntimeModelTests.SpyStore()
        let model = AppPoolRuntimeModel(store: store, initialState: state, widgetPublisher: { _ in })
        let service = CodexUsageSyncService(
            client: SequencedCodexUsageClient(requests: usageRequests, responses: responses),
            oauthRefreshClient: StubOAuthTokenRefreshClient(requests: refreshRequests, result: .success(freshTokens)),
            oauthConfiguration: .codexDefault,
            onOAuthTokenRefreshed: { original, tokens, date in
                #expect(usageRequests.value.count == 1)
                #expect(model.preserveRefreshedOAuthCredential(for: original, tokens: tokens, refreshedAt: date))
            }
        )

        try await service.sync(state: &state, now: now)

        let expected: CodexSyncError = statusCode == 429
            ? .rateLimited : statusCode >= 500 ? .serviceUnavailable : .unauthorized
        #expect(state.accounts[0].apiToken == "fresh-access")
        #expect(state.accounts[0].oauthRefreshToken == "fresh-refresh")
        #expect(state.accounts[0].oauthIDToken == "fresh-id")
        #expect(state.accounts[0].oauthLastRefreshAt == now)
        #expect(state.accounts[0].usedUnits == 15)
        #expect(state.accounts[0].usageSyncError == expected.localizedDescription)
        #expect(store.loadedSnapshot?.accounts[0].oauthRefreshToken == "fresh-refresh")

        responses.withLock { $0["fresh-access"] = .success(CodexUsage(usedUnits: 23, quota: 100)) }
        try await service.sync(state: &state, now: now.addingTimeInterval(30))

        #expect(refreshRequests.value.count == 1)
        #expect(usageRequests.value.map(\.token) == ["old-access", "fresh-access", "fresh-access"])
        #expect(state.accounts[0].usedUnits == 23)
        #expect(!state.accounts[0].isUsageSyncExcluded)
    }

    @Test
    func rotatedCredentialsSurviveUsageNetworkFailure() async throws {
        var state = makeState()
        var checkpoint: OAuthTokens?
        let service = CodexUsageSyncService(
            client: SequencedCodexUsageClient(
                requests: LockedValue([]),
                responses: LockedValue([
                    "old-access": .failure(CodexClientHTTPError(statusCode: 401)),
                    "fresh-access": .failure(URLError(.timedOut))
                ])
            ),
            oauthRefreshClient: StubOAuthTokenRefreshClient(requests: LockedValue([]), result: .success(freshTokens)),
            oauthConfiguration: .codexDefault,
            onOAuthTokenRefreshed: { _, tokens, _ in checkpoint = tokens }
        )

        try await service.sync(state: &state, now: now)

        #expect(checkpoint == freshTokens)
        #expect(state.accounts[0].oauthRefreshToken == "fresh-refresh")
        #expect(state.accounts[0].usageSyncError == CodexSyncError.network.localizedDescription)
    }

    @Test
    func refreshedCredentialsAreSavedBeforeUsageCancellation() async throws {
        var state = makeState()
        state.setUsageSyncExclusion(for: accountID, reason: CodexSyncError.oauthLoginExpired.localizedDescription, now: now)
        let store = AppPoolRuntimeModelTests.SpyStore()
        let model = AppPoolRuntimeModel(store: store, initialState: state, widgetPublisher: { _ in })
        let service = CodexUsageSyncService(
            client: SequencedCodexUsageClient(
                requests: LockedValue([]),
                responses: LockedValue([
                    "old-access": .failure(CodexClientHTTPError(statusCode: 401)),
                    "fresh-access": .failure(CancellationError())
                ])
            ),
            oauthRefreshClient: StubOAuthTokenRefreshClient(requests: LockedValue([]), result: .success(freshTokens)),
            oauthConfiguration: .codexDefault,
            onOAuthTokenRefreshed: { original, tokens, date in
                model.preserveRefreshedOAuthCredential(for: original, tokens: tokens, refreshedAt: date)
            }
        )

        await #expect(throws: CancellationError.self) {
            try await service.sync(state: &state, now: now)
        }

        #expect(state.accounts[0].oauthRefreshToken == "fresh-refresh")
        #expect(model.state.accounts[0].oauthRefreshToken == "fresh-refresh")
        #expect(store.loadedSnapshot?.accounts[0].oauthRefreshToken == "fresh-refresh")
        #expect(store.savedSnapshots.count == 1)
        #expect(state.accounts[0].usageSyncError == L10n.text("usage.sync.excluded.refreshed_pending_usage"))
        #expect(model.state.accounts[0].usageSyncError == L10n.text("usage.sync.excluded.refreshed_pending_usage"))
    }

    @Test
    func delayedRefreshDoesNotOverwriteReimportedCredentials() {
        let originalState = makeState()
        let store = AppPoolRuntimeModelTests.SpyStore()
        let model = AppPoolRuntimeModel(store: store, initialState: originalState, widgetPublisher: { _ in })
        var reimportedState = originalState
        reimportedState.updateAccount(accountID, apiToken: "reimported-access", oauthRefreshToken: "reimported-refresh", now: now)
        model.replaceStateFromDashboard(reimportedState)

        #expect(!model.preserveRefreshedOAuthCredential(for: originalState.accounts[0], tokens: freshTokens, refreshedAt: now))
        #expect(model.state.accounts[0].apiToken == "reimported-access")
        #expect(model.state.accounts[0].oauthRefreshToken == "reimported-refresh")
        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func delayedRefreshDoesNotRestoreDeletedAccounts() {
        let originalState = makeState()
        let store = AppPoolRuntimeModelTests.SpyStore()
        let model = AppPoolRuntimeModel(store: store, initialState: originalState, widgetPublisher: { _ in })
        model.replaceStateFromDashboard(AccountPoolState(accounts: [], mode: .manual))

        #expect(!model.preserveRefreshedOAuthCredential(for: originalState.accounts[0], tokens: freshTokens, refreshedAt: now))
        #expect(model.state.accounts.isEmpty)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test(arguments: [
        #"{"error":"invalid_grant","error_description":"secret-access-token"}"#,
        #"{"error":{"code":"refresh_token_reused","message":"secret-refresh-token"}}"#
    ])
    func refreshHTTPResponseRetainsOnlySafeStatusAndCode(body: String) async throws {
        let expectedCode = body.contains("invalid_grant") ? "invalid_grant" : "refresh_token_reused"
        let hostLabel = expectedCode.replacingOccurrences(of: "_", with: "-")
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://refresh-\(hostLabel).example.com")!,
            scopes: "openid offline_access",
            redirectURI: "test://callback"
        )
        let session = makeMockedURLSession(endpoint: configuration.tokenEndpoint, statusCode: 400, data: Data(body.utf8))
        defer { session.invalidateAndCancel() }
        let service = OAuthTokenRefreshService(session: session)

        do {
            _ = try await service.refreshTokens(refreshToken: "request-secret", configuration: configuration)
            Issue.record("Expected an OAuth refresh HTTP error")
        } catch let error as OAuthTokenRefreshError {
            #expect(error == .http(statusCode: 400, code: expectedCode))
            #expect(error.requiresReauthentication)
            #expect(!error.localizedDescription.contains("secret"))
        }
    }

    @Test(arguments: [#"{"error":"<html>login denied</html>"}"#, #"{"error":{"message":"secret-token"}}"#, "not JSON"])
    func responseTextIsNotTreatedAsAnOAuthErrorCode(body: String) {
        #expect(OAuthTokenRefreshError.responseCode(from: Data(body.utf8)) == nil)
    }
}

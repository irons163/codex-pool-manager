import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct WorkspaceCredentialSyncTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func token(accountID: String, issuedAt: Double) throws -> String {
        let payload: [String: Any] = [
            "sub": "shared-user",
            "email": "dual@example.com",
            "iat": issuedAt,
            "https://api.openai.com/auth": [
                "chatgpt_account_id": accountID,
                "organizations": [["id": "shared-org", "is_default": true]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func account(accountID: String, issuedAt: Double = 100) throws -> AgentAccount {
        AgentAccount(
            id: UUID(),
            name: "dual@example.com",
            usedUnits: 12,
            quota: 100,
            apiToken: try token(accountID: accountID, issuedAt: issuedAt),
            email: "dual@example.com",
            chatGPTAccountID: accountID,
            identityScope: "org:shared-org",
            oauthRefreshToken: "pool-refresh-\(accountID)",
            isPaid: true,
            planType: accountID == "personal" ? "plus" : "team"
        )
    }

    private func local(accountID: String, issuedAt: Double = 200) throws -> LocalCodexOAuthAccount {
        let accessToken = try token(accountID: accountID, issuedAt: issuedAt)
        return LocalCodexOAuthAccount(
            id: "local-\(accountID)-\(issuedAt)",
            displayName: "dual@example.com",
            email: "dual@example.com",
            source: "fixture/auth.json",
            accessToken: accessToken,
            refreshToken: "local-refresh-\(accountID)-\(issuedAt)",
            idToken: accessToken,
            chatGPTAccountID: accountID
        )
    }

    @Test
    func usageSyncRecoversBusinessCredentialWithoutBorrowingItForPersonalAccount() async throws {
        let personal = try account(accountID: "personal")
        let business = try account(accountID: "business")
        let recovered = try local(accountID: "business")
        let requests = LockedValue<[(String, String)]>([])
        let savedAccountIDs = LockedValue<[UUID]>([])
        var state = AccountPoolState(accounts: [personal, business], mode: .manual)
        let service = CodexUsageSyncService(
            client: WorkspaceUsageClient(
                acceptedToken: recovered.accessToken,
                requests: requests
            ),
            onOAuthTokenRefreshed: { account, _, _ in
                savedAccountIDs.withLock { $0.append(account.id) }
            },
            localAccounts: [recovered]
        )

        try await service.sync(state: &state, now: now)

        #expect(requests.value.map { $0.0 } == [personal.apiToken, recovered.accessToken])
        #expect(requests.value.map { $0.1 } == ["personal", "business"])
        #expect(savedAccountIDs.value == [business.id])
        #expect(state.accounts[0].apiToken == personal.apiToken)
        #expect(state.accounts[0].oauthRefreshToken == personal.oauthRefreshToken)
        #expect(state.accounts[0].planType == "plus")
        #expect(state.accounts[0].isUsageSyncExcluded)
        #expect(state.accounts[1].apiToken == recovered.accessToken)
        #expect(state.accounts[1].oauthRefreshToken == recovered.refreshToken)
        #expect(state.accounts[1].usedUnits == 24)
        #expect(state.accounts[1].primaryUsagePercent == 54)
        #expect(state.accounts[1].planType == "team")
        #expect(!state.accounts[1].isUsageSyncExcluded)
    }

    @Test
    func verifiedCredentialSurvivesCancellationWhileSyncingAnotherAccount() async throws {
        let business = try account(accountID: "business")
        let personal = try account(accountID: "personal")
        let recovered = try local(accountID: "business")
        let store = AppPoolRuntimeModelTests.SpyStore()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: AccountPoolState(accounts: [business, personal], mode: .manual),
            widgetPublisher: { _ in }
        )
        var state = model.state
        let service = CodexUsageSyncService(
            client: WorkspaceUsageClient(
                acceptedToken: recovered.accessToken,
                requests: LockedValue([]),
                cancelOtherRequests: true
            ),
            onOAuthTokenRefreshed: { account, tokens, refreshedAt in
                model.preserveRefreshedOAuthCredential(for: account, tokens: tokens, refreshedAt: refreshedAt)
            },
            localAccounts: [recovered]
        )

        do {
            try await service.sync(state: &state, now: now)
            Issue.record("Expected usage sync cancellation")
        } catch is CancellationError {}

        #expect(model.state.accounts[0].apiToken == recovered.accessToken)
        #expect(model.state.accounts[0].oauthRefreshToken == recovered.refreshToken)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func revokedNewerCacheCannotReplaceAWorkingPoolCredential() async throws {
        let business = try account(accountID: "business")
        let cached = try local(accountID: "business")
        var state = AccountPoolState(accounts: [business], mode: .manual)
        let requests = LockedValue<[(String, String)]>([])
        let checkpoints = LockedValue(0)
        let service = CodexUsageSyncService(
            client: WorkspaceUsageClient(acceptedToken: business.apiToken, requests: requests),
            onOAuthTokenRefreshed: { _, _, _ in checkpoints.withLock { $0 += 1 } },
            localAccounts: [cached]
        )

        try await service.sync(state: &state, now: now)

        #expect(requests.value.map { $0.0 } == [cached.accessToken, business.apiToken])
        #expect(checkpoints.value == 0)
        #expect(state.accounts[0].apiToken == business.apiToken)
        #expect(state.accounts[0].oauthRefreshToken == business.oauthRefreshToken)
        #expect(!state.accounts[0].isUsageSyncExcluded)
    }

    @Test
    func mismatchedWorkspaceIsExcludedWithoutSendingUsageRequests() async throws {
        var business = try account(accountID: "business")
        business.apiToken = try token(accountID: "personal", issuedAt: 100)
        var state = AccountPoolState(accounts: [business], mode: .manual)
        let requests = LockedValue<[(String, String)]>([])
        let service = CodexUsageSyncService(
            client: WorkspaceUsageClient(acceptedToken: business.apiToken, requests: requests)
        )

        try await service.sync(state: &state, now: now)

        #expect(requests.value.isEmpty)
        #expect(state.accounts[0].usedUnits == business.usedUnits)
        #expect(state.accounts[0].usageSyncError == CodexSyncError.oauthWorkspaceMismatch.localizedDescription)
    }

    @Test
    func refreshCannotReplaceBusinessCredentialWithPersonalCredential() async throws {
        let business = try account(accountID: "business")
        let personal = try local(accountID: "personal")
        var state = AccountPoolState(accounts: [business], mode: .manual)
        let service = CodexUsageSyncService(
            client: MockCodexUsageClient(responseByToken: [:], shouldThrowError: CodexClientHTTPError(statusCode: 401)),
            oauthRefreshClient: StubOAuthTokenRefreshClient(
                requests: LockedValue([]),
                result: .success(OAuthTokens(
                    accessToken: personal.accessToken,
                    refreshToken: personal.refreshToken,
                    idToken: personal.idToken
                ))
            ),
            oauthConfiguration: .codexDefault
        )

        try await service.sync(state: &state, now: now)

        #expect(state.accounts[0].apiToken == business.apiToken)
        #expect(state.accounts[0].oauthRefreshToken == business.oauthRefreshToken)
        #expect(state.accounts[0].usageSyncError == CodexSyncError.oauthWorkspaceMismatch.localizedDescription)
    }

    @Test
    func mismatchedWorkspaceCannotBeWrittenDuringAccountSwitch() async throws {
        var business = try account(accountID: "business")
        business.apiToken = try token(accountID: "personal", issuedAt: 100)
        let switchCalled = LockedValue(false)
        let coordinator = PoolDashboardSwitchLaunchCoordinator(switchExecutor: { _, _, _, _, _, _ in
            switchCalled.withLock { $0 = true }
        })

        let result = await coordinator.switchAndLaunch(
            account: business,
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: WorkspaceAuthFileResolver(),
            authorizeAuthFile: { nil }
        )

        #expect(!switchCalled.value)
        #expect(!result.didSwitchAuth)
        #expect(result.errorMessage == CodexSyncError.oauthWorkspaceMismatch.localizedDescription)
    }

    @Test
    func newestCredentialWinsAndOlderCachesDoNotRollBackThePool() throws {
        let business = try account(accountID: "business", issuedAt: 300)
        let older = try local(accountID: "business", issuedAt: 200)
        let newer = try local(accountID: "business", issuedAt: 400)
        let newest = try local(accountID: "business", issuedAt: 500)

        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [older]) == nil)
        #expect(LocalCodexAccountDiscovery.newerTokens(
            for: business, in: [newer, older, newest]
        )?.accessToken == newest.accessToken)
    }

    @Test
    func storedWorkspaceIDMustAgreeWithBothTokens() throws {
        var business = try account(accountID: "business")
        let personalToken = try token(accountID: "personal", issuedAt: 200)
        let businessToken = try token(accountID: "business", issuedAt: 200)
        let mismatchedAccess = LocalCodexOAuthAccount(
            id: "wrong-access", displayName: "dual@example.com", email: "dual@example.com",
            source: "fixture", accessToken: personalToken, refreshToken: "refresh",
            idToken: personalToken, chatGPTAccountID: "business"
        )
        let mismatchedID = LocalCodexOAuthAccount(
            id: "wrong-id", displayName: "dual@example.com", email: "dual@example.com",
            source: "fixture", accessToken: businessToken, refreshToken: "refresh",
            idToken: personalToken, chatGPTAccountID: "business"
        )

        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [mismatchedAccess]) == nil)
        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [mismatchedID]) == nil)

        business.oauthIDToken = personalToken
        let missingID = LocalCodexOAuthAccount(
            id: "missing-id", displayName: "dual@example.com", email: "dual@example.com",
            source: "fixture", accessToken: businessToken, refreshToken: "refresh",
            chatGPTAccountID: "business"
        )
        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [missingID]) == nil)
    }

    @Test
    func identicalAccessTokenCanFillMissingRefreshMetadataWithoutReplacingRotatedMetadata() throws {
        var business = try account(accountID: "business")
        let cached = try local(accountID: "business", issuedAt: 100)
        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [cached]) == nil)

        business.oauthRefreshToken = nil
        #expect(LocalCodexAccountDiscovery.newerTokens(for: business, in: [cached])?.refreshToken == cached.refreshToken)
    }

    @Test
    func localImportUpdatesTheExistingWorkspaceWithoutDuplicatingItAsPersonal() throws {
        let personal = try account(accountID: "personal")
        let business = try account(accountID: "business")
        let recovered = try local(accountID: "business")
        var state = AccountPoolState(accounts: [personal, business], mode: .manual)

        PoolAccountUpsertCoordinator().applyLocalImport(
            state: &state,
            usage: CodexUsage(usedUnits: 24, quota: 100, accountID: "business", isPaid: true, planType: "team"),
            fallbackName: "Business",
            tokens: OAuthTokens(
                accessToken: recovered.accessToken,
                refreshToken: recovered.refreshToken,
                idToken: recovered.idToken
            ),
            chatGPTAccountID: "business",
            now: now
        )

        #expect(state.accounts.count == 2)
        #expect(state.accounts[0].apiToken == personal.apiToken)
        #expect(state.accounts[1].id == business.id)
        #expect(state.accounts[1].identityScope == business.identityScope)
        #expect(state.accounts[1].oauthRefreshToken == recovered.refreshToken)
    }

    @Test
    func discoveryPreservesDifferentWorkspaceIDsSharingAnEmailAndToken() throws {
        let payload: [[String: Any]] = ["personal", "business"].map { accountID in
            ["email": "dual@example.com", "account_id": accountID, "access_token": "shared-access"]
        }
        let accounts = LocalCodexAccountDiscovery.parseAccounts(
            from: try JSONSerialization.data(withJSONObject: payload), source: "fixture"
        )

        #expect(accounts.count == 2)
        #expect(Set(accounts.compactMap(\.chatGPTAccountID)) == ["personal", "business"])
    }

    @Test
    func discoveryIncludesMirroredAccountsInAnIsolatedHomeDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "workspace-credentials-\(UUID())")
        let cache = directory.appending(path: ".codex/auth_accounts")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let cached = try local(accountID: "business")
        let payload: [String: Any] = [
            "tokens": [
                "account_id": "business", "access_token": cached.accessToken,
                "refresh_token": cached.refreshToken!, "id_token": cached.idToken!
            ]
        ]
        try JSONSerialization.data(withJSONObject: payload).write(to: cache.appending(path: "business.json"))

        let accounts = LocalCodexAccountDiscovery.discover(homeDirectory: directory)

        #expect(accounts.count == 1)
        #expect(accounts[0].chatGPTAccountID == "business")
        #expect(accounts[0].refreshToken == cached.refreshToken)
    }

    @Test
    func switchMetadataNeverMatchesOnEmailAlone() {
        let cache: [String: Any] = [
            "email": "dual@example.com",
            "tokens": ["access_token": "other-workspace-token", "refresh_token": "other-workspace-refresh"]
        ]

        #expect(!CodexAuthSwitchService.authCacheMatches(cache, accountID: "personal", accessToken: "personal-token"))
        #expect(CodexAuthSwitchService.authCacheMatches(cache, accountID: "personal", accessToken: "other-workspace-token"))
    }

    @Test
    func switchMetadataRejectsContradictoryWorkspaceClaims() throws {
        let cache: [String: Any] = [
            "tokens": ["account_id": "personal", "access_token": try token(accountID: "business", issuedAt: 200)]
        ]

        #expect(!CodexAuthSwitchService.authCacheMatches(cache, accountID: "personal", accessToken: "personal-token"))
    }
}

private struct WorkspaceUsageClient: CodexUsageClient {
    let acceptedToken: String
    let requests: LockedValue<[(String, String)]>
    var cancelOtherRequests: Bool = false

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        requests.withLock { $0.append((accessToken, accountID)) }
        guard accessToken == acceptedToken else {
            if cancelOtherRequests { throw CancellationError() }
            throw CodexClientHTTPError(statusCode: 401)
        }
        return CodexUsage(usedUnits: 24, quota: 100, primaryUsagePercent: 54, isPaid: true, planType: "team")
    }
}

private struct WorkspaceAuthFileResolver: AuthFileURLResolving {
    func resolveAuthFileURLForSwitch(sessionAuthorizedURL: URL?) throws -> URL {
        URL(fileURLWithPath: "/unused/workspace-test-auth.json")
    }
}

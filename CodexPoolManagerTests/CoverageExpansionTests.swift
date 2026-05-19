import Foundation
import Testing
@testable import CodexPoolManager

private enum CoverageExpansionError: Error {
    case expected
}

private final class SuccessTokenURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statusCode: Int = 200
    private static var data = Data()
    private static var observer: ((URLRequest) -> Void)?

    static func configure(
        statusCode: Int,
        data: Data,
        observer: ((URLRequest) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.data = data
        self.observer = observer
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tuple: (Int, Data, ((URLRequest) -> Void)?)
        Self.lock.lock()
        tuple = (Self.statusCode, Self.data, Self.observer)
        Self.lock.unlock()

        tuple.2?(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: tuple.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: tuple.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FailureTokenURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statusCode: Int = 401
    private static var data = Data()

    static func configure(statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.data = data
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tuple: (Int, Data)
        Self.lock.lock()
        tuple = (Self.statusCode, Self.data)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: tuple.0,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: tuple.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func makeSuccessTokenSession(
    statusCode: Int,
    data: Data,
    observer: ((URLRequest) -> Void)? = nil
) -> URLSession {
    SuccessTokenURLProtocol.configure(statusCode: statusCode, data: data, observer: observer)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SuccessTokenURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func makeFailureTokenSession(
    statusCode: Int,
    data: Data
) -> URLSession {
    FailureTokenURLProtocol.configure(statusCode: statusCode, data: data)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FailureTokenURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func withTemporaryFile(
    contents: String,
    suffix: String = ".json",
    _ body: (URL) throws -> Void
) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cpm-coverage-\(UUID().uuidString)\(suffix)")
    try Data(contents.utf8).write(to: url, options: .atomic)
    defer { try? FileManager.default.removeItem(at: url) }
    try body(url)
}

private func preserveLanguageOverride(_ body: () throws -> Void) rethrows {
    let defaults = UserDefaults.standard
    let key = L10n.languageOverrideKey
    let previous = defaults.object(forKey: key)
    defer {
        if let previous {
            defaults.set(previous, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
    try body()
}

private func parsedFormBody(_ form: String) -> [String: String] {
    var values: [String: String] = [:]
    for pair in form.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard let key = parts.first, !key.isEmpty else { continue }
        let rawValue = parts.count == 2 ? parts[1] : ""
        let decoded = rawValue.removingPercentEncoding ?? rawValue
        values[key] = decoded
    }
    return values
}

private func requestBodyData(_ request: URLRequest) -> Data {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while stream.hasBytesAvailable {
        let bytesRead = stream.read(&buffer, maxLength: bufferSize)
        if bytesRead < 0 {
            break
        }
        if bytesRead == 0 {
            break
        }
        data.append(buffer, count: bytesRead)
    }

    return data
}

@MainActor
struct OAuthLoginServiceCoverageExpansionTests {
    @Test
    func completeManualSignInExchangesTokenAndBuildsExpectedRequest() async throws {
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            clientID: "client-xyz",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let responseBody = """
        {
          "access_token": "access-123",
          "refresh_token": "refresh-456",
          "id_token": "id-789"
        }
        """
        let capturedRequest = LockedValue<URLRequest?>(nil)
        let session = makeSuccessTokenSession(
            statusCode: 200,
            data: Data(responseBody.utf8),
            observer: { request in
                capturedRequest.withLock { $0 = request }
            }
        )
        let service = OAuthLoginService(session: session)
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?code=abc123&state=expected-state")
        )

        let tokens = try await service.completeManualSignIn(
            configuration: configuration,
            callbackURL: callbackURL,
            expectedState: "expected-state",
            codeVerifier: "verifier-123"
        )

        #expect(tokens.accessToken == "access-123")
        #expect(tokens.refreshToken == "refresh-456")
        #expect(tokens.idToken == "id-789")

        let request = try #require(capturedRequest.value)
        #expect(request.url == configuration.tokenEndpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let form = String(data: requestBodyData(request), encoding: .utf8) ?? ""
        let fields = parsedFormBody(form)
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["client_id"] == "client-xyz")
        #expect(fields["code"] == "abc123")
        #expect(fields["redirect_uri"] == "aiaagentpool://oauth/callback")
        #expect(fields["code_verifier"] == "verifier-123")
    }

    @Test
    func completeManualSignInThrowsStateMismatchBeforeTokenExchange() async throws {
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let service = OAuthLoginService(session: .shared)
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?code=abc123&state=actual-state")
        )

        await #expect(throws: OAuthLoginError.stateMismatch) {
            _ = try await service.completeManualSignIn(
                configuration: configuration,
                callbackURL: callbackURL,
                expectedState: "expected-state",
                codeVerifier: "verifier-123"
            )
        }
    }

    @Test
    func completeManualSignInPropagatesTokenExchangeFailure() async throws {
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let session = makeFailureTokenSession(
            statusCode: 401,
            data: Data("unauthorized".utf8)
        )
        let service = OAuthLoginService(session: session)
        let callbackURL = try #require(
            URL(string: "aiaagentpool://oauth/callback?code=abc123&state=state-1")
        )

        await #expect(throws: OAuthLoginError.tokenExchangeFailed("unauthorized")) {
            _ = try await service.completeManualSignIn(
                configuration: configuration,
                callbackURL: callbackURL,
                expectedState: "state-1",
                codeVerifier: "verifier-123"
            )
        }
    }
}

struct L10nCoverageExpansionTests {
    @Test
    func normalizedLanguageOverrideCodeCoversAliasesAndFallbacks() {
        #expect(L10n.normalizedLanguageOverrideCode("") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode(" system ") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode("Follow System") == L10n.systemLanguageCode)
        #expect(L10n.normalizedLanguageOverrideCode("zh-TW") == "zh-Hant")
        #expect(L10n.normalizedLanguageOverrideCode("zh-CN") == "zh-Hans")
        #expect(L10n.normalizedLanguageOverrideCode("fr-CA") == "fr")
        #expect(L10n.normalizedLanguageOverrideCode("unknown-language") == L10n.systemLanguageCode)
    }

    @Test
    func localeUsesExplicitOverrideWhenProvided() {
        let locale = L10n.locale(for: "ja")
        #expect(locale.identifier.lowercased().hasPrefix("ja"))
    }

    @Test
    func localeUsesSavedOverrideWhenOverrideParameterIsNil() throws {
        preserveLanguageOverride {
            UserDefaults.standard.set("ko", forKey: L10n.languageOverrideKey)
            let locale = L10n.locale()
            #expect(locale.identifier.lowercased().hasPrefix("ko"))
        }
    }

    @Test
    func textFallsBackToKeyForUnknownLocalizationKey() {
        let key = "l10n.coverage.expansion.nonexistent.\(UUID().uuidString)"
        #expect(L10n.text(key) == key)
    }

    @Test
    func textFormatVariantReturnsFormattedValue() {
        let rendered = L10n.text("usage.remaining_percent_format", 42)
        #expect(rendered.contains("42"))
    }
}

struct CodexAuthFileAccessServiceCoverageExpansionTests {
    @Test
    func bookmarkRoundTripAndResolvePathUsesSessionThenBookmark() throws {
        let bookmarkKey = "test.auth.file.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let service = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)
        let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent("auth-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: temporaryURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        #expect(!service.hasSavedBookmark())
        try service.saveBookmark(for: temporaryURL)
        #expect(service.hasSavedBookmark())

        let resolved = try service.loadAuthorizedURLFromBookmark()
        #expect(resolved.url.standardizedFileURL.lastPathComponent == temporaryURL.lastPathComponent)
        #expect(resolved.wasStale == false)

        let fromSession = try service.resolveAuthFileURLForSwitch(sessionAuthorizedURL: temporaryURL)
        #expect(fromSession.standardizedFileURL.lastPathComponent == temporaryURL.lastPathComponent)

        let fromBookmark = try service.resolveAuthFileURLForSwitch(sessionAuthorizedURL: nil)
        #expect(fromBookmark.standardizedFileURL.lastPathComponent == temporaryURL.lastPathComponent)
    }

    @Test
    func loadAccountsReadsFromAuthFile() throws {
        let bookmarkKey = "test.auth.file.accounts.\(UUID().uuidString)"
        let service = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)
        let json = """
        {
          "session": {
            "email": "local@example.com",
            "account_id": "acct-local",
            "access_token": "sk-local-token-123"
          }
        }
        """

        try withTemporaryFile(contents: json) { url in
            let accounts = try service.loadAccounts(from: url)
            #expect(accounts.count == 1)
            #expect(accounts.first?.email == "local@example.com")
            #expect(accounts.first?.chatGPTAccountID == "acct-local")
        }
    }

    @Test
    func withSecurityScopeRunsBodyAndReturnsValue() throws {
        let service = CodexAuthFileAccessService(bookmarkKey: "test.auth.file.scope.\(UUID().uuidString)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scope-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        let value = try service.withSecurityScope(url: url) {
            (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        #expect(value == "hello")
    }
}

struct LocalAccountsCoordinatorCoverageExpansionTests {
    @Test
    func normalizeStoredImportedAccountNamesUpdatesPlaceholderOnly() {
        let targetID = UUID()
        let untouchedID = UUID()
        let placeholderName = L10n.text("account.default_oauth_name")
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: targetID,
                    name: placeholderName,
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-a",
                    chatGPTAccountID: "acct-1"
                ),
                AgentAccount(
                    id: untouchedID,
                    name: "Custom Name",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-b",
                    chatGPTAccountID: "acct-2"
                )
            ],
            mode: .manual
        )
        let localAccounts = [
            LocalCodexOAuthAccount(
                id: "local-1",
                displayName: "display",
                email: "updated@example.com",
                source: "test",
                accessToken: "token-a",
                chatGPTAccountID: "acct-1"
            ),
            LocalCodexOAuthAccount(
                id: "local-2",
                displayName: "display-2",
                email: "should-not-overwrite@example.com",
                source: "test",
                accessToken: "token-b",
                chatGPTAccountID: "acct-2"
            )
        ]
        let coordinator = PoolDashboardLocalAccountsCoordinator()

        coordinator.normalizeStoredImportedAccountNames(
            state: &state,
            localAccounts: localAccounts
        )

        #expect(state.accounts.first(where: { $0.id == targetID })?.name == "updated@example.com")
        #expect(state.accounts.first(where: { $0.id == untouchedID })?.name == "Custom Name")
    }

    @Test
    func refreshLocalOAuthAccountsLoadsAccountsFromSavedBookmark() throws {
        let bookmarkKey = "test.local.accounts.bookmark.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let authFileAccessService = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)
        let authJSON = """
        {
          "session": {
            "email": "bookmark@example.com",
            "account_id": "acct-bookmark",
            "access_token": "sk-bookmark-token"
          }
        }
        """

        try withTemporaryFile(contents: authJSON) { authFileURL in
            try authFileAccessService.saveBookmark(for: authFileURL)

            var state = AccountPoolState(accounts: [], mode: .manual)
            var viewModel = LocalOAuthImportViewModel()
            let coordinator = PoolDashboardLocalAccountsCoordinator()

            let authorizedURL = coordinator.refreshLocalOAuthAccounts(
                state: &state,
                viewModel: &viewModel,
                authFileAccessService: authFileAccessService,
                currentAuthorizedAuthFileURL: nil
            )

            #expect(authorizedURL?.standardizedFileURL.lastPathComponent == authFileURL.lastPathComponent)
            #expect(viewModel.accounts.count == 1)
            #expect(viewModel.accounts.first?.email == "bookmark@example.com")
            #expect(viewModel.errorMessage == nil)
        }
    }

    @Test
    func loadLocalOAuthAccountsFromBookmarkInvalidBookmarkKeepsFallbackURLAndMarksError() {
        let bookmarkKey = "test.local.accounts.invalid.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.set(Data("invalid-bookmark".utf8), forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let coordinator = PoolDashboardLocalAccountsCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        let fallbackURL = URL(string: "file:///tmp/current-auth.json")

        let result = coordinator.loadLocalOAuthAccountsFromBookmark(
            state: &state,
            viewModel: &viewModel,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: bookmarkKey),
            currentAuthorizedAuthFileURL: fallbackURL
        )

        #expect(result.didLoadAccounts == false)
        #expect(result.authorizedURL == fallbackURL)
        #expect(viewModel.errorMessage?.isEmpty == false)
        #expect(viewModel.errorMessage?.localizedCaseInsensitiveContains("auth.json") == true)
    }
}

@MainActor
struct AuthFilePanelAndFlowCoverageExpansionTests {
    @Test
    func authFilePanelServiceUsesInjectedPicker() {
        let expectedURL = URL(fileURLWithPath: "/tmp/auth.json")
        let service = CodexAuthFilePanelService(picker: { expectedURL })
        #expect(service.pickAuthFileURL() == expectedURL)

        let cancelled = CodexAuthFilePanelService(picker: { nil })
        #expect(cancelled.pickAuthFileURL() == nil)
    }

    @Test
    func localAccountsCoordinatorOpenAuthFilePanelLoadsPickedAuthFile() throws {
        let bookmarkKey = "test.panel.load.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        let coordinator = PoolDashboardLocalAccountsCoordinator()
        let accessService = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)

        let authJSON = """
        {
          "session": {
            "email": "panel@example.com",
            "account_id": "acct-panel",
            "access_token": "sk-panel-token"
          }
        }
        """

        try withTemporaryFile(contents: authJSON) { authFileURL in
            let pickedURL = coordinator.openAuthFilePanelAndLoad(
                state: &state,
                viewModel: &viewModel,
                authFileAccessService: accessService,
                filePanelService: CodexAuthFilePanelService(picker: { authFileURL })
            )

            #expect(pickedURL?.standardizedFileURL.lastPathComponent == authFileURL.lastPathComponent)
            #expect(viewModel.accounts.count == 1)
            #expect(viewModel.accounts.first?.email == "panel@example.com")
            #expect(accessService.hasSavedBookmark())
        }
    }

    @Test
    func localAccountsFlowCoordinatorOpenAuthFilePanelKeepsCurrentURLWhenCancelled() {
        let bookmarkKey = "test.panel.cancel.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let fallbackURL = URL(fileURLWithPath: "/tmp/current-auth.json")
        let flowCoordinator = PoolDashboardLocalAccountsFlowCoordinator()
        let output = flowCoordinator.openAuthFilePanel(
            from: AccountPoolState(accounts: [], mode: .manual),
            viewModel: LocalOAuthImportViewModel(),
            currentAuthorizedAuthFileURL: fallbackURL,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: bookmarkKey),
            filePanelService: CodexAuthFilePanelService(picker: { nil })
        )

        #expect(output.pickedAuthFileURL == nil)
        #expect(output.sessionAuthorizedAuthFileURL == fallbackURL)
        #expect(output.state.accounts.isEmpty)
    }
}

@MainActor
struct RuntimeCoordinatorCoverageExpansionTests {
    @Test
    func prepareManualOAuthSignInReturnsErrorForInvalidConfiguration() {
        let coordinator = PoolDashboardRuntimeCoordinator()

        let output = coordinator.prepareManualOAuthSignIn(
            input: .init(
                issuer: "not-valid-url",
                clientID: "",
                scopes: "openid",
                redirectURI: "http://localhost:1455/auth/callback",
                originator: "codex_cli_rs",
                workspaceID: "",
                accountNameInput: "",
                fallbackQuota: 100
            )
        )

        #expect(output.authorizationURL == nil)
        #expect(output.expectedState == nil)
        #expect(output.codeVerifier == nil)
        #expect(output.oauthError != nil)
    }

    @Test
    func importManualOAuthCallbackRejectsInvalidURLStringWithoutMutatingState() async {
        let coordinator = PoolDashboardRuntimeCoordinator()
        let state = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 1, quota: 100)],
            mode: .manual
        )
        let input = PoolDashboardRuntimeCoordinator.OAuthSignInInput(
            issuer: "https://auth.openai.com",
            clientID: "app",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback",
            originator: "codex_cli_rs",
            workspaceID: "",
            accountNameInput: "Input Name",
            fallbackQuota: 1000
        )

        let output = await coordinator.importManualOAuthCallback(
            from: state,
            input: input,
            callbackURLString: "   ",
            expectedState: "state-1",
            codeVerifier: "verifier-1"
        )

        #expect(output.state.snapshot == state.snapshot)
        #expect(output.oauthError != nil)
        #expect(output.oauthSuccessMessage == nil)
        #expect(output.nextOAuthAccountName == "Input Name")
        #expect(output.shouldRefreshLocalOAuthAccounts == false)
    }

    @Test
    func importManualOAuthCallbackRejectsStateMismatchWithoutCallingUsageFetch() async {
        let coordinator = PoolDashboardRuntimeCoordinator()
        let state = AccountPoolState(accounts: [], mode: .manual)
        let input = PoolDashboardRuntimeCoordinator.OAuthSignInInput(
            issuer: "https://auth.openai.com",
            clientID: "app",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback",
            originator: "codex_cli_rs",
            workspaceID: "",
            accountNameInput: "Input Name",
            fallbackQuota: 1000
        )
        let callbackURLString = "aiaagentpool://oauth/callback?code=abc123&state=wrong-state"

        let output = await coordinator.importManualOAuthCallback(
            from: state,
            input: input,
            callbackURLString: callbackURLString,
            expectedState: "expected-state",
            codeVerifier: "verifier-1"
        )

        #expect(output.state.snapshot == state.snapshot)
        #expect(output.oauthError == OAuthLoginError.stateMismatch.localizedDescription)
        #expect(output.oauthSuccessMessage == nil)
        #expect(output.nextOAuthAccountName == "Input Name")
        #expect(output.shouldRefreshLocalOAuthAccounts == false)
    }
}

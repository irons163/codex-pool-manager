import Foundation
import SwiftUI
import Testing
@testable import CodexPoolManager

private enum CoverageExpansionError: Error {
    case expected
}

private final class StubUsageFetcher: CodexUsageFetching {
    let result: Result<CodexUsage, Error>
    let requests = LockedValue<[(token: String, accountID: String)]>([])

    init(result: Result<CodexUsage, Error>) {
        self.result = result
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        requests.withLock { $0.append((token: accessToken, accountID: accountID)) }
        return try result.get()
    }
}

private final class StubOAuthCompleteLoginService: OAuthCompleteLoginServicing {
    var signInResult: Result<OAuthTokens, Error>
    var manualPreparationResult: Result<OAuthManualSignInPreparation, Error>
    var manualCompleteResult: Result<OAuthTokens, Error>

    let signInConfigurations = LockedValue<[OAuthClientConfiguration]>([])
    let manualPreparationConfigurations = LockedValue<[OAuthClientConfiguration]>([])
    let manualCompleteRequests = LockedValue<[(config: OAuthClientConfiguration, callbackURL: URL, expectedState: String, codeVerifier: String)]>([])

    init(
        signInResult: Result<OAuthTokens, Error>,
        manualPreparationResult: Result<OAuthManualSignInPreparation, Error>,
        manualCompleteResult: Result<OAuthTokens, Error>
    ) {
        self.signInResult = signInResult
        self.manualPreparationResult = manualPreparationResult
        self.manualCompleteResult = manualCompleteResult
    }

    func signIn(configuration: OAuthClientConfiguration) async throws -> OAuthTokens {
        signInConfigurations.withLock { $0.append(configuration) }
        return try signInResult.get()
    }

    func prepareManualSignIn(configuration: OAuthClientConfiguration) throws -> OAuthManualSignInPreparation {
        manualPreparationConfigurations.withLock { $0.append(configuration) }
        return try manualPreparationResult.get()
    }

    func completeManualSignIn(
        configuration: OAuthClientConfiguration,
        callbackURL: URL,
        expectedState: String,
        codeVerifier: String
    ) async throws -> OAuthTokens {
        manualCompleteRequests.withLock {
            $0.append((config: configuration, callbackURL: callbackURL, expectedState: expectedState, codeVerifier: codeVerifier))
        }
        return try manualCompleteResult.get()
    }
}

private struct StubDataFlowCoordinator: PoolDashboardDataFlowCoordinating {
    let result: Result<(state: AccountPoolState, rawResponse: String?), Error>

    func syncState(
        from state: AccountPoolState
    ) async throws -> (state: AccountPoolState, rawResponse: String?) {
        try result.get()
    }
}

private struct StubAuthFileURLResolver: AuthFileURLResolving {
    let result: Result<URL, Error>

    func resolveAuthFileURLForSwitch(sessionAuthorizedURL: URL?) throws -> URL {
        try result.get()
    }
}

private final class StubRuntimeOAuthCoordinator: PoolDashboardRuntimeOAuthCoordinating {
    var signInOutput: PoolDashboardRuntimeCoordinator.OAuthSignInOutput
    var manualPreparationOutput: PoolDashboardRuntimeCoordinator.ManualOAuthPreparationOutput
    var manualImportOutput: PoolDashboardRuntimeCoordinator.OAuthSignInOutput

    let signInInputs = LockedValue<[PoolDashboardRuntimeCoordinator.OAuthSignInInput]>([])
    let manualPreparationInputs = LockedValue<[PoolDashboardRuntimeCoordinator.OAuthSignInInput]>([])
    let manualImportRequests = LockedValue<[(input: PoolDashboardRuntimeCoordinator.OAuthSignInInput, callbackURLString: String, expectedState: String, codeVerifier: String)]>([])

    init(
        signInOutput: PoolDashboardRuntimeCoordinator.OAuthSignInOutput,
        manualPreparationOutput: PoolDashboardRuntimeCoordinator.ManualOAuthPreparationOutput,
        manualImportOutput: PoolDashboardRuntimeCoordinator.OAuthSignInOutput
    ) {
        self.signInOutput = signInOutput
        self.manualPreparationOutput = manualPreparationOutput
        self.manualImportOutput = manualImportOutput
    }

    func signInWithOAuth(
        from state: AccountPoolState,
        input: PoolDashboardRuntimeCoordinator.OAuthSignInInput
    ) async -> PoolDashboardRuntimeCoordinator.OAuthSignInOutput {
        signInInputs.withLock { $0.append(input) }
        return signInOutput
    }

    func prepareManualOAuthSignIn(
        input: PoolDashboardRuntimeCoordinator.OAuthSignInInput
    ) -> PoolDashboardRuntimeCoordinator.ManualOAuthPreparationOutput {
        manualPreparationInputs.withLock { $0.append(input) }
        return manualPreparationOutput
    }

    func importManualOAuthCallback(
        from state: AccountPoolState,
        input: PoolDashboardRuntimeCoordinator.OAuthSignInInput,
        callbackURLString: String,
        expectedState: String,
        codeVerifier: String
    ) async -> PoolDashboardRuntimeCoordinator.OAuthSignInOutput {
        manualImportRequests.withLock {
            $0.append((input: input, callbackURLString: callbackURLString, expectedState: expectedState, codeVerifier: codeVerifier))
        }
        return manualImportOutput
    }
}

private func makeOAuthIDToken(payload: [String: Any]) throws -> String {
    let payloadData = try JSONSerialization.data(withJSONObject: payload)
    let encodedPayload = payloadData.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encodedPayload).sig"
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

private final class SharedUsageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var statusCode: Int = 200
    private static var data = Data()
    private static var expectedAuthorization: String?

    static func configure(statusCode: Int, data: Data, expectedAuthorization: String) {
        lock.lock()
        defer { lock.unlock() }
        self.statusCode = statusCode
        self.data = data
        self.expectedAuthorization = expectedAuthorization
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 200
        data = Data()
        expectedAuthorization = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard
            let url = request.url,
            url.host == "chatgpt.com",
            url.path == "/backend-api/wham/usage"
        else {
            return false
        }

        let expected: String?
        lock.lock()
        expected = expectedAuthorization
        lock.unlock()
        guard let expected else { return false }
        return request.value(forHTTPHeaderField: "Authorization") == "Bearer \(expected)"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let tuple: (Int, Data)
        Self.lock.lock()
        tuple = (Self.statusCode, Self.data)
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
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
    private func makeOAuthInput(accountNameInput: String = "") -> PoolDashboardRuntimeCoordinator.OAuthSignInInput {
        .init(
            issuer: "https://auth.openai.com",
            clientID: "app",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback",
            originator: "codex_cli_rs",
            workspaceID: "",
            accountNameInput: accountNameInput,
            fallbackQuota: 1000
        )
    }

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

    @Test
    func syncCodexUsageReturnsInjectedSyncResult() async {
        var syncedState = AccountPoolState(accounts: [], mode: .manual)
        syncedState.addAccount(name: "synced@example.com", quota: 100, usedUnits: 7)

        let coordinator = PoolDashboardRuntimeCoordinator(
            dataFlowCoordinator: StubDataFlowCoordinator(result: .success((state: syncedState, rawResponse: #"{"ok":true}"#)))
        )
        let output = await coordinator.syncCodexUsage(from: AccountPoolState(accounts: [], mode: .manual))

        #expect(output.state.snapshot == syncedState.snapshot)
        #expect(output.syncError == nil)
        #expect(output.lastUsageRawJSON == #"{"ok":true}"#)
    }

    @Test
    func syncCodexUsageReturnsFailureMessageWhenSyncThrows() async {
        let coordinator = PoolDashboardRuntimeCoordinator(
            dataFlowCoordinator: StubDataFlowCoordinator(result: .failure(URLError(.timedOut)))
        )
        let initialState = AccountPoolState(accounts: [AgentAccount(id: UUID(), name: "A", usedUnits: 1, quota: 100)], mode: .manual)

        let output = await coordinator.syncCodexUsage(from: initialState)

        #expect(output.state.snapshot == initialState.snapshot)
        #expect(output.syncError?.isEmpty == false)
        #expect(output.lastUsageRawJSON == nil)
    }

    @Test
    func signInWithOAuthAddsAccountOnSuccessfulInjectedDependencies() async throws {
        let idToken = try makeOAuthIDToken(payload: [
            "sub": "user-signin-1",
            "account_id": "acct-signin-1",
            "email": "signin@example.com"
        ])
        let loginService = StubOAuthCompleteLoginService(
            signInResult: .success(
                OAuthTokens(
                    accessToken: "sk-signin-1",
                    refreshToken: "refresh-signin-1",
                    idToken: idToken
                )
            ),
            manualPreparationResult: .failure(CoverageExpansionError.expected),
            manualCompleteResult: .failure(CoverageExpansionError.expected)
        )
        let usageFetcher = StubUsageFetcher(result: .success(
            CodexUsage(
                usedUnits: 21,
                quota: 100,
                accountID: "acct-signin-1",
                accountEmail: "signin@example.com",
                isPaid: true
            )
        ))
        let coordinator = PoolDashboardRuntimeCoordinator(
            loginServiceFactory: { loginService },
            usageClientFactory: { usageFetcher }
        )

        let output = await coordinator.signInWithOAuth(
            from: AccountPoolState(accounts: [], mode: .manual),
            input: makeOAuthInput(accountNameInput: "")
        )

        #expect(output.oauthError == nil)
        #expect(output.oauthSuccessMessage?.isEmpty == false)
        #expect(output.nextOAuthAccountName.isEmpty)
        #expect(output.shouldRefreshLocalOAuthAccounts == true)
        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts.first?.name == "signin@example.com")
        #expect(output.state.accounts.first?.chatGPTAccountID == "acct-signin-1")
        #expect(loginService.signInConfigurations.value.count == 1)
        #expect(usageFetcher.requests.value.first?.accountID == "acct-signin-1")
    }

    @Test
    func prepareManualOAuthSignInReturnsInjectedManualPreparation() throws {
        let expectedURL = try #require(
            URL(string: "https://auth.openai.com/oauth/authorize?state=stub-state")
        )
        let loginService = StubOAuthCompleteLoginService(
            signInResult: .failure(CoverageExpansionError.expected),
            manualPreparationResult: .success(
                OAuthManualSignInPreparation(
                    authorizationURL: expectedURL,
                    state: "stub-state",
                    codeVerifier: "stub-verifier"
                )
            ),
            manualCompleteResult: .failure(CoverageExpansionError.expected)
        )
        let coordinator = PoolDashboardRuntimeCoordinator(loginServiceFactory: { loginService })

        let output = coordinator.prepareManualOAuthSignIn(input: makeOAuthInput())

        #expect(output.authorizationURL == expectedURL)
        #expect(output.expectedState == "stub-state")
        #expect(output.codeVerifier == "stub-verifier")
        #expect(output.oauthError == nil)
        #expect(loginService.manualPreparationConfigurations.value.count == 1)
    }

    @Test
    func importManualOAuthCallbackCompletesAndCreatesAccountWithInjectedDependencies() async throws {
        let idToken = try makeOAuthIDToken(payload: [
            "sub": "user-manual-1",
            "account_id": "acct-manual-1",
            "email": "manual@example.com"
        ])
        let loginService = StubOAuthCompleteLoginService(
            signInResult: .failure(CoverageExpansionError.expected),
            manualPreparationResult: .failure(CoverageExpansionError.expected),
            manualCompleteResult: .success(
                OAuthTokens(
                    accessToken: "sk-manual-1",
                    refreshToken: nil,
                    idToken: idToken
                )
            )
        )
        let usageFetcher = StubUsageFetcher(result: .success(
            CodexUsage(
                usedUnits: 5,
                quota: 50,
                accountID: "acct-manual-1",
                accountEmail: "manual@example.com",
                isPaid: false
            )
        ))
        let coordinator = PoolDashboardRuntimeCoordinator(
            loginServiceFactory: { loginService },
            usageClientFactory: { usageFetcher }
        )

        let output = await coordinator.importManualOAuthCallback(
            from: AccountPoolState(accounts: [], mode: .manual),
            input: makeOAuthInput(accountNameInput: "Manual Input"),
            callbackURLString: "aiaagentpool://oauth/callback?code=abc123&state=expected-state",
            expectedState: "expected-state",
            codeVerifier: "manual-verifier"
        )

        #expect(output.oauthError == nil)
        #expect(output.oauthSuccessMessage?.isEmpty == false)
        #expect(output.shouldRefreshLocalOAuthAccounts == true)
        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts.first?.chatGPTAccountID == "acct-manual-1")
        #expect(loginService.manualCompleteRequests.value.count == 1)
        #expect(usageFetcher.requests.value.first?.accountID == "acct-manual-1")
    }
}

@MainActor
struct OAuthSignInFlowCoordinatorCoverageExpansionTests {
    private func makeFlowInput() -> PoolDashboardOAuthSignInFlowCoordinator.Input {
        .init(
            issuer: "https://auth.openai.com",
            clientID: "app-client",
            scopes: "openid profile email",
            redirectURI: "aiaagentpool://oauth/callback",
            originator: "codex_cli_rs",
            workspaceID: "",
            fallbackQuota: 100
        )
    }

    @Test
    func signInWithOAuthAppliesRuntimeOutputAndPreservesMutationContract() async {
        var runtimeState = AccountPoolState(accounts: [], mode: .manual)
        runtimeState.addAccount(name: "flow@example.com", quota: 100, usedUnits: 3)
        let runtimeOutput = PoolDashboardRuntimeCoordinator.OAuthSignInOutput(
            state: runtimeState,
            oauthError: "oauth-error",
            oauthSuccessMessage: "oauth-success",
            nextOAuthAccountName: "next-name",
            shouldRefreshLocalOAuthAccounts: true
        )
        let runtimeCoordinator = StubRuntimeOAuthCoordinator(
            signInOutput: runtimeOutput,
            manualPreparationOutput: .init(authorizationURL: nil, expectedState: nil, codeVerifier: nil, oauthError: nil),
            manualImportOutput: runtimeOutput
        )
        let coordinator = PoolDashboardOAuthSignInFlowCoordinator(runtimeCoordinator: runtimeCoordinator)
        let initialViewState = PoolDashboardViewState()
        let output = await coordinator.signInWithOAuth(
            from: AccountPoolState(accounts: [], mode: .manual),
            viewState: initialViewState,
            oauthAccountName: "before-name",
            input: makeFlowInput()
        )

        #expect(output.state.snapshot == runtimeState.snapshot)
        #expect(output.viewState.oauthError == "oauth-error")
        #expect(output.viewState.oauthSuccessMessage == "oauth-success")
        #expect(output.oauthAccountName == "next-name")
        #expect(output.shouldRefreshLocalOAuthAccounts == true)
        #expect(runtimeCoordinator.signInInputs.value.first?.accountNameInput == "before-name")
    }

    @Test
    func prepareManualOAuthSignInMapsRuntimePreparationOutput() throws {
        let authorizationURL = try #require(URL(string: "https://auth.openai.com/oauth/authorize?state=flow"))
        let runtimeCoordinator = StubRuntimeOAuthCoordinator(
            signInOutput: .init(
                state: AccountPoolState(accounts: [], mode: .manual),
                oauthError: nil,
                oauthSuccessMessage: nil,
                nextOAuthAccountName: "",
                shouldRefreshLocalOAuthAccounts: false
            ),
            manualPreparationOutput: .init(
                authorizationURL: authorizationURL,
                expectedState: "flow-state",
                codeVerifier: "flow-verifier",
                oauthError: "flow-error"
            ),
            manualImportOutput: .init(
                state: AccountPoolState(accounts: [], mode: .manual),
                oauthError: nil,
                oauthSuccessMessage: nil,
                nextOAuthAccountName: "",
                shouldRefreshLocalOAuthAccounts: false
            )
        )
        let coordinator = PoolDashboardOAuthSignInFlowCoordinator(runtimeCoordinator: runtimeCoordinator)

        let output = coordinator.prepareManualOAuthSignIn(input: makeFlowInput())

        #expect(output.authorizationURL == authorizationURL)
        #expect(output.expectedState == "flow-state")
        #expect(output.codeVerifier == "flow-verifier")
        #expect(output.oauthError == "flow-error")
        #expect(runtimeCoordinator.manualPreparationInputs.value.count == 1)
        #expect(runtimeCoordinator.manualPreparationInputs.value.first?.accountNameInput.isEmpty == true)
    }

    @Test
    func importManualOAuthCallbackPassesCallbackFieldsAndAppliesMutation() async {
        var runtimeState = AccountPoolState(accounts: [], mode: .manual)
        runtimeState.addAccount(name: "manual-flow@example.com", quota: 100, usedUnits: 9)
        let runtimeOutput = PoolDashboardRuntimeCoordinator.OAuthSignInOutput(
            state: runtimeState,
            oauthError: nil,
            oauthSuccessMessage: "done",
            nextOAuthAccountName: "",
            shouldRefreshLocalOAuthAccounts: false
        )
        let runtimeCoordinator = StubRuntimeOAuthCoordinator(
            signInOutput: runtimeOutput,
            manualPreparationOutput: .init(authorizationURL: nil, expectedState: nil, codeVerifier: nil, oauthError: nil),
            manualImportOutput: runtimeOutput
        )
        let coordinator = PoolDashboardOAuthSignInFlowCoordinator(runtimeCoordinator: runtimeCoordinator)

        let output = await coordinator.importManualOAuthCallback(
            from: AccountPoolState(accounts: [], mode: .manual),
            viewState: PoolDashboardViewState(),
            oauthAccountName: "Manual Name",
            input: makeFlowInput(),
            callbackURLString: "aiaagentpool://oauth/callback?code=abc&state=flow-state",
            expectedState: "flow-state",
            codeVerifier: "flow-verifier"
        )

        #expect(output.state.snapshot == runtimeState.snapshot)
        #expect(output.viewState.oauthError == nil)
        #expect(output.viewState.oauthSuccessMessage == "done")
        #expect(output.oauthAccountName.isEmpty)
        #expect(output.shouldRefreshLocalOAuthAccounts == false)
        #expect(runtimeCoordinator.manualImportRequests.value.count == 1)
        #expect(runtimeCoordinator.manualImportRequests.value.first?.expectedState == "flow-state")
        #expect(runtimeCoordinator.manualImportRequests.value.first?.codeVerifier == "flow-verifier")
    }
}

@MainActor
struct SwitchLaunchCoordinatorCoverageExpansionTests {
    private func makeSwitchableAccount(
        token: String = "sk-token",
        accountID: String? = "acct-123"
    ) -> AgentAccount {
        AgentAccount(
            id: UUID(),
            name: "switch@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: token,
            chatGPTAccountID: accountID
        )
    }

    @Test
    func switchAndLaunchSucceedsWithResolvedAuthURL() async {
        let authURL = URL(fileURLWithPath: "/tmp/auth-success.json")
        let capturedLogs = LockedValue<[String]>([])
        let coordinator = PoolDashboardSwitchLaunchCoordinator(
            switchExecutor: { _, _, _, _, _, logger in
                logger("switch ok")
                capturedLogs.withLock { $0.append("executor-called") }
            }
        )

        let output = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(),
            currentAuthorizedAuthFileURL: authURL,
            authFileAccessService: StubAuthFileURLResolver(result: .success(authURL)),
            authorizeAuthFile: { nil }
        )

        #expect(output.errorMessage == nil)
        #expect(output.didSwitchAuth == true)
        #expect(output.sessionAuthorizedAuthFileURL == authURL)
        #expect(output.switchLaunchLog.contains("switch ok"))
        #expect(capturedLogs.value == ["executor-called"])
    }

    @Test
    func switchAndLaunchReportsLaunchFailureButKeepsSuccessfulAuthSwitch() async {
        let authURL = URL(fileURLWithPath: "/tmp/auth-launch-failure.json")
        let coordinator = PoolDashboardSwitchLaunchCoordinator(
            switchExecutor: { _, _, _, _, _, _ in
                throw CodexAuthSwitchError.launchFailedAfterSwitch(reason: "app relaunch failed")
            }
        )

        let output = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(),
            currentAuthorizedAuthFileURL: authURL,
            authFileAccessService: StubAuthFileURLResolver(result: .success(authURL)),
            authorizeAuthFile: { nil }
        )

        #expect(output.didSwitchAuth == true)
        #expect(output.sessionAuthorizedAuthFileURL == authURL)
        #expect(output.errorMessage?.contains("app relaunch failed") == true)
    }

    @Test
    func switchAndLaunchReturnsPermissionErrorWhenAuthFileMissingAndAuthorizationCancelled() async {
        let coordinator = PoolDashboardSwitchLaunchCoordinator(
            switchExecutor: { _, _, _, _, _, _ in
                Issue.record("switch executor should not be called when auth permission is cancelled")
            }
        )

        let output = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(),
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: StubAuthFileURLResolver(
                result: .failure(CodexAuthFileAccessService.AccessError.missingAuthFile)
            ),
            authorizeAuthFile: { nil }
        )

        #expect(output.didSwitchAuth == false)
        #expect(output.sessionAuthorizedAuthFileURL == nil)
        #expect(output.errorMessage == L10n.text("switch.error.requires_auth_file_permission"))
    }

    @Test
    func switchAndLaunchRetriesAfterPermissionGrantAndUsesAuthorizedURL() async {
        let grantedURL = URL(fileURLWithPath: "/tmp/auth-granted.json")
        let capturedAuthURLs = LockedValue<[URL]>([])
        let coordinator = PoolDashboardSwitchLaunchCoordinator(
            switchExecutor: { authURL, _, _, _, _, _ in
                capturedAuthURLs.withLock { $0.append(authURL) }
            }
        )

        let output = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(),
            currentAuthorizedAuthFileURL: nil,
            authFileAccessService: StubAuthFileURLResolver(
                result: .failure(CodexAuthFileAccessService.AccessError.missingAuthFile)
            ),
            authorizeAuthFile: { grantedURL }
        )

        #expect(output.didSwitchAuth == true)
        #expect(output.errorMessage == nil)
        #expect(output.sessionAuthorizedAuthFileURL == grantedURL)
        #expect(capturedAuthURLs.value == [grantedURL])
    }

    @Test
    func switchAndLaunchReturnsValidationErrorsBeforeExecutor() async {
        let coordinator = PoolDashboardSwitchLaunchCoordinator(
            switchExecutor: { _, _, _, _, _, _ in
                Issue.record("switch executor should not run when required account fields are missing")
            }
        )

        let missingToken = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(token: ""),
            currentAuthorizedAuthFileURL: URL(fileURLWithPath: "/tmp/auth.json"),
            authFileAccessService: StubAuthFileURLResolver(result: .success(URL(fileURLWithPath: "/tmp/auth.json"))),
            authorizeAuthFile: { nil }
        )
        #expect(missingToken.errorMessage == L10n.text("switch.error.missing_token"))
        #expect(missingToken.didSwitchAuth == false)

        let missingAccountID = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(accountID: nil),
            currentAuthorizedAuthFileURL: URL(fileURLWithPath: "/tmp/auth.json"),
            authFileAccessService: StubAuthFileURLResolver(result: .success(URL(fileURLWithPath: "/tmp/auth.json"))),
            authorizeAuthFile: { nil }
        )
        #expect(missingAccountID.errorMessage == L10n.text("switch.error.missing_account_id"))
        #expect(missingAccountID.didSwitchAuth == false)
    }
}

@MainActor
struct LocalImportCoordinatorCoverageExpansionTests {
    @Test
    func importLocalOAuthAccountAddsAccountOnSuccessfulUsageFetch() async {
        let usage = CodexUsage(
            usedUnits: 12,
            quota: 100,
            accountID: "acct-imported",
            accountEmail: "imported@example.com",
            isPaid: true
        )
        let usageFetcher = StubUsageFetcher(result: .success(usage))
        let coordinator = PoolDashboardLocalImportCoordinator(
            usageClientFactory: { _ in usageFetcher }
        )
        let localAccount = LocalCodexOAuthAccount(
            id: "local-import-1",
            displayName: "OAuth Account",
            email: "fallback@example.com",
            source: "test",
            accessToken: "sk-import-token",
            chatGPTAccountID: "acct-imported"
        )

        let output = await coordinator.importLocalOAuthAccount(
            localAccount,
            state: AccountPoolState(accounts: [], mode: .manual),
            viewModel: LocalOAuthImportViewModel(),
            onRawResponse: { _ in }
        )

        #expect(output.didImport == true)
        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts.first?.chatGPTAccountID == "acct-imported")
        #expect(output.state.accounts.first?.name == "imported@example.com")
        #expect(output.viewModel.errorMessage == nil)
        #expect(output.viewModel.successMessage?.isEmpty == false)
        #expect(usageFetcher.requests.value.count == 1)
        #expect(usageFetcher.requests.value.first?.token == "sk-import-token")
        #expect(usageFetcher.requests.value.first?.accountID == "acct-imported")
    }

    @Test
    func importLocalOAuthAccountReturnsLocalizedErrorWhenUsageFetchFails() async {
        let usageFetcher = StubUsageFetcher(result: .failure(URLError(.timedOut)))
        let coordinator = PoolDashboardLocalImportCoordinator(
            usageClientFactory: { _ in usageFetcher }
        )
        let localAccount = LocalCodexOAuthAccount(
            id: "local-import-2",
            displayName: "OAuth Account",
            email: "fallback@example.com",
            source: "test",
            accessToken: "sk-import-token-2",
            chatGPTAccountID: "acct-imported-2"
        )

        let output = await coordinator.importLocalOAuthAccount(
            localAccount,
            state: AccountPoolState(accounts: [], mode: .manual),
            viewModel: LocalOAuthImportViewModel(),
            onRawResponse: { _ in }
        )

        #expect(output.didImport == false)
        #expect(output.state.accounts.isEmpty)
        #expect(output.viewModel.successMessage == nil)
        #expect(output.viewModel.errorMessage?.contains(L10n.text("usage.sync.error.network")) == true)
        #expect(usageFetcher.requests.value.count == 1)
    }

    @Test
    func importLocalOAuthAccountSkipsImportWhenChatGPTAccountIDMissing() async {
        let usageFetcher = StubUsageFetcher(result: .success(CodexUsage(usedUnits: 1, quota: 100)))
        let coordinator = PoolDashboardLocalImportCoordinator(
            usageClientFactory: { _ in usageFetcher }
        )
        let localAccount = LocalCodexOAuthAccount(
            id: "local-import-3",
            displayName: "OAuth Account",
            email: "missing-id@example.com",
            source: "test",
            accessToken: "sk-import-token-3",
            chatGPTAccountID: nil
        )

        let output = await coordinator.importLocalOAuthAccount(
            localAccount,
            state: AccountPoolState(accounts: [], mode: .manual),
            viewModel: LocalOAuthImportViewModel(),
            onRawResponse: { _ in }
        )

        #expect(output.didImport == false)
        #expect(output.state.accounts.isEmpty)
        #expect(output.viewModel.errorMessage == L10n.text("auth.missing_chatgpt_account_id"))
        #expect(usageFetcher.requests.value.isEmpty)
    }

    @Test
    func importLocalOAuthAccountUpdatesExistingAccountAndUsesUpdatedMessage() async {
        let usage = CodexUsage(
            usedUnits: 22,
            quota: 100,
            accountID: "acct-imported-existing",
            accountEmail: "updated@example.com",
            isPaid: true
        )
        let usageFetcher = StubUsageFetcher(result: .success(usage))
        let coordinator = PoolDashboardLocalImportCoordinator(
            usageClientFactory: { _ in usageFetcher }
        )
        let localAccount = LocalCodexOAuthAccount(
            id: "local-import-existing",
            displayName: "OAuth Account",
            email: "fallback@example.com",
            source: "test",
            accessToken: "sk-import-token-existing",
            chatGPTAccountID: "acct-imported-existing"
        )
        let existingAccount = AgentAccount(
            id: UUID(),
            name: "old@example.com",
            usedUnits: 1,
            quota: 100,
            apiToken: "sk-old-token",
            chatGPTAccountID: "acct-imported-existing"
        )
        let existingState = AccountPoolState(accounts: [existingAccount], mode: .manual)

        let output = await coordinator.importLocalOAuthAccount(
            localAccount,
            state: existingState,
            viewModel: LocalOAuthImportViewModel(),
            onRawResponse: { _ in }
        )

        #expect(output.didImport == true)
        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts.first?.chatGPTAccountID == "acct-imported-existing")
        #expect(output.state.accounts.first?.usedUnits == 22)
        #expect(output.viewModel.successMessage?.isEmpty == false)
        #expect(output.viewModel.errorMessage == nil)
        #expect(usageFetcher.requests.value.count == 1)
    }

    @Test
    func importLocalOAuthAccountUsesDefaultUsageClientAndCapturesRawResponse() async throws {
        let responseJSON = """
        {
          "used_units": 7,
          "quota": 100,
          "account_id": "acct-default-path",
          "email": "default-path@example.com"
        }
        """
        let accessToken = "sk-default-local-import-coverage-token"
        SharedUsageURLProtocol.configure(
            statusCode: 200,
            data: Data(responseJSON.utf8),
            expectedAuthorization: accessToken
        )
        URLProtocol.registerClass(SharedUsageURLProtocol.self)
        defer {
            URLProtocol.unregisterClass(SharedUsageURLProtocol.self)
            SharedUsageURLProtocol.reset()
        }

        let coordinator = PoolDashboardLocalImportCoordinator()
        let localAccount = LocalCodexOAuthAccount(
            id: "local-default-client",
            displayName: "OAuth Account",
            email: "fallback@example.com",
            source: "test",
            accessToken: accessToken,
            chatGPTAccountID: "acct-default-path"
        )
        let rawResponses = LockedValue<[String]>([])
        let output = await coordinator.importLocalOAuthAccount(
            localAccount,
            state: AccountPoolState(accounts: [], mode: .manual),
            viewModel: LocalOAuthImportViewModel(),
            onRawResponse: { raw in
                rawResponses.withLock { $0.append(raw) }
            }
        )

        #expect(output.didImport == true)
        #expect(output.state.accounts.count == 1)
        #expect(output.state.accounts.first?.usedUnits == 7)
        #expect(output.state.accounts.first?.quota == 100)

        for _ in 0..<20 where rawResponses.value.isEmpty {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(rawResponses.value.count == 1)
        #expect(rawResponses.value.first?.contains("\"used_units\": 7") == true)
    }
}

@MainActor
struct MutationCoordinatorCoverageExpansionTests {
    @Test
    func applyBackupExportResultKeepsExistingStateWhenNoPayloadAndNoError() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewState = PoolDashboardViewState()
        viewState.backupJSON = "{\"old\":true}"
        viewState.backupError = "old-error"

        coordinator.applyBackupExportResult((json: nil, errorMessage: nil), viewState: &viewState)

        #expect(viewState.backupJSON == "{\"old\":true}")
        #expect(viewState.backupError == "old-error")
    }

    @Test
    func applyBackupImportResultReturnsFalseWhenNoStateAndNoError() {
        let coordinator = PoolDashboardMutationCoordinator()
        let originalState = AccountPoolState(
            accounts: [AgentAccount(id: UUID(), name: "Keep", usedUnits: 1, quota: 100)],
            mode: .manual
        )
        var state = originalState
        var viewState = PoolDashboardViewState()
        viewState.backupError = "old-error"

        let shouldSync = coordinator.applyBackupImportResult(
            (state: nil, errorMessage: nil),
            state: &state,
            viewState: &viewState
        )

        #expect(shouldSync == false)
        #expect(state.snapshot == originalState.snapshot)
        #expect(viewState.backupError == "old-error")
    }

    @Test
    func applyLocalImportOutputWithoutImportKeepsSyncError() {
        let coordinator = PoolDashboardMutationCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        viewModel.errorMessage = "import-failed"
        var viewState = PoolDashboardViewState()
        viewState.syncError = "existing-sync-error"
        let output = PoolDashboardLocalImportCoordinator.Output(
            state: state,
            viewModel: viewModel,
            didImport: false
        )

        coordinator.applyLocalImportOutput(
            output,
            state: &state,
            viewModel: &viewModel,
            viewState: &viewState
        )

        #expect(viewState.syncError == "existing-sync-error")
        #expect(viewModel.errorMessage == "import-failed")
    }

    @Test
    func applySwitchOutputSetsWarningWhenAuthSwitchedButLaunchFailed() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState()
        var authorizedURL: URL? = nil
        let output = PoolDashboardSwitchLaunchCoordinator.Output(
            switchLaunchLog: "switch-log",
            errorMessage: "launch failed",
            sessionAuthorizedAuthFileURL: URL(fileURLWithPath: "/tmp/auth-switched.json"),
            didSwitchAuth: true
        )

        coordinator.applySwitchOutput(
            output,
            viewModel: &viewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &authorizedURL
        )

        #expect(viewState.switchLaunchError == nil)
        #expect(viewState.switchLaunchWarning == L10n.text("switch.warning.launch_failed_but_switched"))
        #expect(viewState.lastSwitchLaunchLog == "switch-log")
        #expect(authorizedURL?.path == "/tmp/auth-switched.json")
    }

    @Test
    func applySwitchOutputClearsWarningWhenAuthSwitchedWithoutError() {
        let coordinator = PoolDashboardMutationCoordinator()
        var viewModel = LocalOAuthImportViewModel()
        var viewState = PoolDashboardViewState()
        viewState.switchLaunchWarning = "old-warning"
        var authorizedURL: URL? = URL(fileURLWithPath: "/tmp/old.json")
        let output = PoolDashboardSwitchLaunchCoordinator.Output(
            switchLaunchLog: "ok",
            errorMessage: nil,
            sessionAuthorizedAuthFileURL: nil,
            didSwitchAuth: true
        )

        coordinator.applySwitchOutput(
            output,
            viewModel: &viewModel,
            viewState: &viewState,
            sessionAuthorizedAuthFileURL: &authorizedURL
        )

        #expect(viewState.switchLaunchError == nil)
        #expect(viewState.switchLaunchWarning == nil)
        #expect(viewState.lastSwitchLaunchLog == "ok")
        #expect(authorizedURL == nil)
    }
}

@MainActor
struct StrategyAndVaultCoverageExpansionTests {
    @Test
    func strategyBindingAdapterCoversLaunchAndAutoSyncBindings() {
        var state = AccountPoolState(
            accounts: [],
            mode: .manual,
            autoSyncEnabled: true,
            autoSyncIntervalSeconds: 30
        )
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardStrategyBindingAdapter(state: binding)

        #expect(adapter.mode.wrappedValue == .intelligent)
        adapter.mode.wrappedValue = .manual
        #expect(state.mode == .intelligent)

        #expect(adapter.switchWithoutLaunching.wrappedValue == false)
        adapter.switchWithoutLaunching.wrappedValue = true
        #expect(state.switchWithoutLaunching == true)

        #expect(adapter.autoSyncEnabled.wrappedValue == true)
        adapter.autoSyncEnabled.wrappedValue = false
        #expect(state.autoSyncEnabled == false)

        adapter.autoSyncIntervalSeconds.wrappedValue = 500
        #expect(state.autoSyncIntervalSeconds == 300)
        adapter.autoSyncIntervalSeconds.wrappedValue = 1
        #expect(state.autoSyncIntervalSeconds == 5)
    }

    @Test
    func strategyBindingAdapterManualSelectionHandlesEmptyAccountList() {
        var state = AccountPoolState(accounts: [], mode: .intelligent)
        let binding = Binding<AccountPoolState>(
            get: { state },
            set: { state = $0 }
        )
        let adapter = PoolDashboardStrategyBindingAdapter(state: binding)

        let generatedID = adapter.manualSelection.wrappedValue
        #expect(state.manualAccountID == nil)

        adapter.manualSelection.wrappedValue = generatedID
        #expect(state.manualAccountID == generatedID)
    }

    @Test
    func tokenVaultsCoverRemoveAndEmptyStorageFallback() {
        let inMemoryVault = InMemoryAccountTokenVault()
        let inMemoryID = UUID()
        inMemoryVault.setToken("memory-token", for: inMemoryID)
        #expect(inMemoryVault.tokenCount == 1)
        inMemoryVault.removeToken(for: inMemoryID)
        #expect(inMemoryVault.token(for: inMemoryID) == nil)
        #expect(inMemoryVault.tokenCount == 0)

        let suiteName = "CodexPoolManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let defaultsVault = UserDefaultsAccountTokenVault(defaults: defaults, key: "tokens")
        #expect(defaultsVault.tokenCount == 0)

        let defaultsID = UUID()
        defaultsVault.setToken("defaults-token", for: defaultsID)
        #expect(defaultsVault.tokenCount == 1)
        defaultsVault.removeToken(for: defaultsID)
        #expect(defaultsVault.token(for: defaultsID) == nil)
        #expect(defaultsVault.tokenCount == 0)
    }

    @Test
    func backupFlowCoordinatorCoversRefetchableExportPath() {
        let coordinator = PoolDashboardBackupFlowCoordinator()
        let account = AgentAccount(
            id: UUID(),
            name: "Refetchable",
            usedUnits: 55,
            quota: 100,
            apiToken: "token-refetchable",
            chatGPTAccountID: "acct-refetchable",
            usageWindowName: "primary_window",
            usageWindowResetAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let state = AccountPoolState(accounts: [account], mode: .manual)
        var viewState = PoolDashboardViewState()

        coordinator.exportRefetchableSnapshot(from: state, viewState: &viewState)

        #expect(viewState.backupError == nil)
        #expect(!viewState.backupJSON.isEmpty)
        #expect(viewState.backupJSON.contains("acct-refetchable"))
    }
}

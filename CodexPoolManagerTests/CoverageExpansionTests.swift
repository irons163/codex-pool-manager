import Foundation
import SwiftUI
import Testing
import Darwin
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
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
    struct Stub {
        let statusCode: Int
        let data: Data
        let observer: ((URLRequest) -> Void)?
    }

    static let responseIDHeader = "X-Codex-Test-Success-Response-ID"
    private static let lock = NSLock()
    private static var stubsByResponseID: [String: Stub] = [:]

    static func configure(
        responseID: String,
        statusCode: Int,
        data: Data,
        observer: ((URLRequest) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        stubsByResponseID[responseID] = Stub(
            statusCode: statusCode,
            data: data,
            observer: observer
        )
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub: Stub?
        let responseID = request.value(forHTTPHeaderField: Self.responseIDHeader)
        Self.lock.lock()
        stub = responseID.flatMap { Self.stubsByResponseID[$0] }
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        stub.observer?(request)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FailureTokenURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let data: Data
    }

    static let responseIDHeader = "X-Codex-Test-Failure-Response-ID"
    private static let lock = NSLock()
    private static var stubsByResponseID: [String: Stub] = [:]

    static func configure(responseID: String, statusCode: Int, data: Data) {
        lock.lock()
        defer { lock.unlock() }
        stubsByResponseID[responseID] = Stub(statusCode: statusCode, data: data)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub: Stub?
        let responseID = request.value(forHTTPHeaderField: Self.responseIDHeader)
        Self.lock.lock()
        stub = responseID.flatMap { Self.stubsByResponseID[$0] }
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.data)
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
    let responseID = UUID().uuidString
    SuccessTokenURLProtocol.configure(
        responseID: responseID,
        statusCode: statusCode,
        data: data,
        observer: observer
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SuccessTokenURLProtocol.self]
    configuration.httpAdditionalHeaders = [SuccessTokenURLProtocol.responseIDHeader: responseID]
    return URLSession(configuration: configuration)
}

private func makeFailureTokenSession(
    statusCode: Int,
    data: Data
) -> URLSession {
    let responseID = UUID().uuidString
    FailureTokenURLProtocol.configure(
        responseID: responseID,
        statusCode: statusCode,
        data: data
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FailureTokenURLProtocol.self]
    configuration.httpAdditionalHeaders = [FailureTokenURLProtocol.responseIDHeader: responseID]
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
    languageOverrideMutationLock.lock()
    defer { languageOverrideMutationLock.unlock() }

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

private let languageOverrideMutationLock = NSLock()

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

private enum LocalhostCallbackTestError: Error {
    case socketCreateFailed
    case socketBindFailed
    case socketLookupFailed
    case invalidPort
}

private func availableLoopbackPort() throws -> UInt16 {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { throw LocalhostCallbackTestError.socketCreateFailed }
    defer { close(fd) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw LocalhostCallbackTestError.socketBindFailed }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let lookupResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            getsockname(fd, sockaddrPointer, &length)
        }
    }
    guard lookupResult == 0 else { throw LocalhostCallbackTestError.socketLookupFailed }

    let port = UInt16(bigEndian: boundAddress.sin_port)
    guard port > 0 else { throw LocalhostCallbackTestError.invalidPort }
    return port
}

@MainActor
struct OAuthLoginServiceCoverageExpansionTests {
    @Test
    func successTokenSessionsKeepResponsesIsolated() async throws {
        let firstSession = makeSuccessTokenSession(
            statusCode: 201,
            data: Data("first-response".utf8)
        )
        let secondSession = makeSuccessTokenSession(
            statusCode: 202,
            data: Data("second-response".utf8)
        )
        let firstURL = try #require(URL(string: "https://auth.example.com/first"))
        let secondURL = try #require(URL(string: "https://auth.example.com/second"))

        async let firstResult = firstSession.data(from: firstURL)
        async let secondResult = secondSession.data(from: secondURL)
        let ((firstData, firstResponse), (secondData, secondResponse)) = try await (
            firstResult,
            secondResult
        )

        #expect(String(data: firstData, encoding: .utf8) == "first-response")
        #expect((firstResponse as? HTTPURLResponse)?.statusCode == 201)
        #expect(String(data: secondData, encoding: .utf8) == "second-response")
        #expect((secondResponse as? HTTPURLResponse)?.statusCode == 202)
    }

    @Test
    func failureTokenSessionsKeepResponsesIsolated() async throws {
        let firstSession = makeFailureTokenSession(
            statusCode: 401,
            data: Data("first-failure".utf8)
        )
        let secondSession = makeFailureTokenSession(
            statusCode: 429,
            data: Data("second-failure".utf8)
        )
        let firstURL = try #require(URL(string: "https://auth.example.com/failure-one"))
        let secondURL = try #require(URL(string: "https://auth.example.com/failure-two"))

        async let firstResult = firstSession.data(from: firstURL)
        async let secondResult = secondSession.data(from: secondURL)
        let ((firstData, firstResponse), (secondData, secondResponse)) = try await (
            firstResult,
            secondResult
        )

        #expect(String(data: firstData, encoding: .utf8) == "first-failure")
        #expect((firstResponse as? HTTPURLResponse)?.statusCode == 401)
        #expect(String(data: secondData, encoding: .utf8) == "second-failure")
        #expect((secondResponse as? HTTPURLResponse)?.statusCode == 429)
    }

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

    @Test
    func refreshTokenServiceExchangesRefreshTokenAndBuildsExpectedRequest() async throws {
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            clientID: "client-refresh",
            scopes: "openid profile",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let responseBody = """
        {
          "access_token": "refreshed-access",
          "refresh_token": "next-refresh",
          "id_token": "next-id"
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
        let service = OAuthTokenRefreshService(session: session)

        let tokens = try await service.refreshTokens(
            refreshToken: "refresh + &= token",
            configuration: configuration
        )

        #expect(tokens.accessToken == "refreshed-access")
        #expect(tokens.refreshToken == "next-refresh")
        #expect(tokens.idToken == "next-id")

        let request = try #require(capturedRequest.value)
        #expect(request.url == configuration.tokenEndpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let form = String(data: requestBodyData(request), encoding: .utf8) ?? ""
        let fields = parsedFormBody(form)
        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["client_id"] == "client-refresh")
        #expect(fields["refresh_token"] == "refresh + &= token")
    }

    @Test
    func refreshTokenServicePropagatesHTTPFailureMessage() async throws {
        let configuration = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            scopes: "openid",
            redirectURI: "aiaagentpool://oauth/callback"
        )
        let session = makeFailureTokenSession(
            statusCode: 403,
            data: Data("refresh denied".utf8)
        )
        let service = OAuthTokenRefreshService(session: session)

        await #expect(throws: OAuthLoginError.tokenExchangeFailed("refresh denied")) {
            _ = try await service.refreshTokens(
                refreshToken: "refresh-token",
                configuration: configuration
            )
        }
    }
}

@MainActor
struct CodexUsageSyncServiceCoverageExpansionTests {
    @Test
    func codexSyncMapsDirectCodexSyncErrorWithoutRewrapping() async {
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: UUID(uuidString: "00000000-0000-0000-0000-00000000C601")!,
                    name: "Direct sync error",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-direct-error"
                )
            ],
            mode: .manual
        )
        if let accountID = state.accounts.first?.id {
            state.updateAccount(accountID, chatGPTAccountID: "acct-direct-error")
        }
        let sync = CodexUsageSyncService(
            client: MockCodexUsageClient(
                responseByToken: [:],
                shouldThrowError: CodexSyncError.rateLimited
            )
        )

        try? await sync.sync(state: &state, now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(state.accounts[0].isUsageSyncExcluded)
        #expect(state.accounts[0].usageSyncError == CodexSyncError.rateLimited.localizedDescription)
    }

    @Test
    func codexSyncRefreshKeepsExistingRefreshAndIDTokensWhenResponseOmitsThem() async throws {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-00000000C602")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: accountID,
                    name: "Refresh fallback",
                    usedUnits: 10,
                    quota: 100,
                    apiToken: "expired-access-token",
                    oauthRefreshToken: "old-refresh-token",
                    oauthIDToken: "old-id-token"
                )
            ],
            mode: .manual
        )
        state.updateAccount(accountID, chatGPTAccountID: "acct-refresh-fallback")
        let usageRequests = LockedValue<[(token: String, accountID: String)]>([])
        let usageResponses = LockedValue<[String: Result<CodexUsage, Error>]>([
            "expired-access-token": .failure(CodexClientHTTPError(statusCode: 401)),
            "fresh-access-token": .success(CodexUsage(usedUnits: 44, quota: 100))
        ])
        let refreshRequests = LockedValue<[(refreshToken: String, clientID: String)]>([])
        let sync = CodexUsageSyncService(
            client: SequencedCodexUsageClient(
                requests: usageRequests,
                responses: usageResponses
            ),
            oauthRefreshClient: StubOAuthTokenRefreshClient(
                requests: refreshRequests,
                result: .success(OAuthTokens(
                    accessToken: " fresh-access-token ",
                    refreshToken: " \n ",
                    idToken: "\t"
                ))
            ),
            oauthConfiguration: .codexDefault
        )
        let now = Date(timeIntervalSince1970: 1_800_000_100)

        try await sync.sync(state: &state, now: now)

        #expect(usageRequests.value.map(\.token) == ["expired-access-token", "fresh-access-token"])
        #expect(refreshRequests.value.map(\.refreshToken) == ["old-refresh-token"])
        #expect(state.accounts[0].apiToken == "fresh-access-token")
        #expect(state.accounts[0].oauthRefreshToken == "old-refresh-token")
        #expect(state.accounts[0].oauthIDToken == "old-id-token")
        #expect(state.accounts[0].oauthLastRefreshAt == now)
        #expect(state.accounts[0].usedUnits == 44)
        #expect(!state.accounts[0].isUsageSyncExcluded)
    }

    @Test
    func openAICodexUsageClientTreatsSinglePaidWindowAsBothFiveHourAndWeekly() async throws {
        let responseJSON = """
        {
          "account_id": "acct-single-window",
          "email": "single@example.com",
          "plan_type": "pro",
          "rate_limit": {
            "secondary": {
              "name": "usage_window",
              "usedPercent": 66,
              "resetAt": "2026-07-30T12:34:56.789Z"
            }
          }
        }
        """
        let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=single-paid-window"))
        let session = makeSuccessTokenSession(
            statusCode: 200,
            data: Data(responseJSON.utf8)
        )

        let client = OpenAICodexUsageClient(endpoint: endpoint, session: session)
        let usage = try await client.fetchUsage(accessToken: "token-single", accountID: "acct-single-window")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetAt = try #require(formatter.date(from: "2026-07-30T12:34:56.789Z"))
        #expect(usage.isPaid)
        #expect(usage.primaryUsagePercent == 66)
        #expect(usage.secondaryUsagePercent == 66)
        #expect(usage.primaryUsageResetAt == resetAt)
        #expect(usage.secondaryUsageResetAt == resetAt)
        #expect(usage.usedUnits == 66)
        #expect(usage.quota == 100)
        #expect(usage.usageWindowName == "usage_window")
        #expect(usage.usageWindowResetAt == resetAt)
    }

    @Test
    func openAICodexUsageClientParsesPaidUsageUnitsWithoutWindows() async throws {
        let responseJSON = """
        {
          "account_id": "acct-units",
          "email": "units@example.com",
          "credits": { "unlimited": true },
          "used_units": 123,
          "quota": 456
        }
        """
        let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=paid-units-no-windows"))
        let session = makeSuccessTokenSession(
            statusCode: 200,
            data: Data(responseJSON.utf8)
        )

        let client = OpenAICodexUsageClient(endpoint: endpoint, session: session)
        let usage = try await client.fetchUsage(accessToken: "token-units", accountID: "acct-units")

        #expect(usage.isPaid)
        #expect(usage.usedUnits == 123)
        #expect(usage.quota == 456)
        #expect(usage.usageWindowName == "weekly_window")
        #expect(usage.primaryUsagePercent == nil)
        #expect(usage.secondaryUsagePercent == nil)
    }
}

struct OAuthSupportEdgeCoverageExpansionTests {
    @Test
    func authorizeURLOmitsAllowedWorkspaceWhenForcedWorkspaceIsEmpty() throws {
        let config = OAuthClientConfiguration(
            issuer: URL(string: "https://auth.example.com")!,
            clientID: "client-empty-workspace",
            scopes: "openid",
            redirectURI: "aiaagentpool://oauth/callback",
            forcedWorkspaceID: ""
        )
        let request = OAuthAuthorizationRequest(
            state: "state-empty-workspace",
            codeChallenge: "challenge"
        )

        let url = try OAuthAuthorizationRequestBuilder.makeAuthorizeURL(
            config: config,
            request: request
        )
        let items = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { ($0.name, $0.value ?? "") })

        #expect(items["allowed_workspace_id"] == nil)
    }

    @Test
    func localhostCallbackConfigAcceptsHTTPSLoopbackDefaultsAndEmptyPath() throws {
        let localhostHTTPS = try #require(URL(string: "https://localhost"))
        let ipv4HTTP = try #require(URL(string: "http://127.0.0.1/callback"))
        let ipv6HTTP = try #require(URL(string: "http://[::1]:1455/callback"))

        let httpsConfig = try #require(LocalhostOAuthCallbackConfig(redirectURI: localhostHTTPS))
        let ipv4Config = try #require(LocalhostOAuthCallbackConfig(redirectURI: ipv4HTTP))
        let ipv6Config = try #require(LocalhostOAuthCallbackConfig(redirectURI: ipv6HTTP))

        #expect(httpsConfig.host == "localhost")
        #expect(httpsConfig.port == 443)
        #expect(httpsConfig.callbackPath == "/")
        #expect(ipv4Config.host == "127.0.0.1")
        #expect(ipv4Config.port == 80)
        #expect(ipv4Config.callbackPath == "/callback")
        #expect(ipv6Config.host == "::1")
        #expect(ipv6Config.port == 1455)
    }

    @Test
    func localhostCallbackExtractorBuildsURLWithoutQueryAndRejectsMalformedRequestLine() {
        let config = LocalhostOAuthCallbackConfig(host: "localhost", port: 1455, callbackPath: "/auth/callback")

        let noQueryURL = LocalhostOAuthCallbackExtractor.callbackURL(
            fromRequest: "GET /auth/callback HTTP/1.1\r\nHost: localhost\r\n\r\n",
            config: config
        )
        let malformedURL = LocalhostOAuthCallbackExtractor.callbackURL(
            fromRequest: "\r\nHost: localhost\r\n\r\n",
            config: config
        )

        #expect(noQueryURL?.absoluteString == "http://localhost:1455/auth/callback")
        #expect(malformedURL == nil)
    }

    @Test
    func idTokenClaimsParserAcceptsCamelCaseAccountIDAndIgnoresBlankOrganizationIDs() throws {
        let token = try makeOAuthIDToken(payload: [
            "sub": "user-camel",
            "accountId": "acct-camel",
            "email": "camel@example.com",
            "https://api.openai.com/auth": [
                "organizations": [
                    ["id": "   ", "is_default": true],
                    ["id": "\n\t"]
                ]
            ]
        ])

        let claims = try #require(OAuthIDTokenClaimsParser.parse(token))

        #expect(claims.subject == "user-camel")
        #expect(claims.accountID == "acct-camel")
        #expect(claims.email == "camel@example.com")
        #expect(claims.organizationID == nil)
        #expect(claims.resolvedIdentityScope(fallbackWorkspaceID: " fallback-org ") == "org:fallback-org")
    }
}

@MainActor
struct LocalhostOAuthCallbackServerCoverageExpansionTests {
    @Test
    func localhostCallbackServerCapturesCallbackURL() async throws {
        let port = try availableLoopbackPort()
        let config = LocalhostOAuthCallbackConfig(host: "127.0.0.1", port: port, callbackPath: "/auth/callback")
        let server = LocalhostOAuthCallbackServer()

        let callbackURL = URL(string: "http://127.0.0.1:\(port)/auth/callback?code=smoke-code&state=smoke-state")!
        let senderTaskBox = LockedValue<Task<Void, Never>?>(nil)

        let captured = try await server.waitForCallback(
            config: config,
            timeoutNanoseconds: 5_000_000_000,
            onReadyToReceiveCallback: {
                senderTaskBox.withLock { task in
                    task = Task.detached(priority: .userInitiated) {
                        let session = URLSession(configuration: .ephemeral)
                        let deadline = Date().addingTimeInterval(5.0)
                        while Date() < deadline {
                            do {
                                let (_, response) = try await session.data(from: callbackURL)
                                if (response as? HTTPURLResponse) != nil {
                                    return
                                }
                            } catch {
                                try? await Task.sleep(nanoseconds: 50_000_000)
                            }
                        }
                    }
                }
                return true
            }
        )

        let payload = try OAuthCallbackParser.parse(callbackURL: captured)
        #expect(payload.code == "smoke-code")
        #expect(payload.state == "smoke-state")
    }

    @Test
    func localhostCallbackServerReturnsBrowserStartFailureWhenReadyActionFails() async throws {
        let port = try availableLoopbackPort()
        let config = LocalhostOAuthCallbackConfig(host: "127.0.0.1", port: port, callbackPath: "/auth/callback")
        let server = LocalhostOAuthCallbackServer()

        await #expect(throws: OAuthLoginError.browserStartFailed) {
            _ = try await server.waitForCallback(
                config: config,
                timeoutNanoseconds: 5_000_000_000,
                onReadyToReceiveCallback: { false }
            )
        }
    }

    @Test
    func localhostCallbackServerTimesOutWhenNoCallbackArrives() async throws {
        let port = try availableLoopbackPort()
        let config = LocalhostOAuthCallbackConfig(host: "127.0.0.1", port: port, callbackPath: "/auth/callback")
        let server = LocalhostOAuthCallbackServer()

        await #expect(throws: OAuthLoginError.localhostCallbackTimedOut) {
            _ = try await server.waitForCallback(
                config: config,
                timeoutNanoseconds: 250_000_000,
                onReadyToReceiveCallback: { true }
            )
        }
    }

    @Test
    func localhostCallbackServerCanCancelPendingWait() async throws {
        let port = try availableLoopbackPort()
        let config = LocalhostOAuthCallbackConfig(host: "127.0.0.1", port: port, callbackPath: "/auth/callback")
        let server = LocalhostOAuthCallbackServer()

        let waitTask = Task {
            try await server.waitForCallback(
                config: config,
                timeoutNanoseconds: 5_000_000_000,
                onReadyToReceiveCallback: { true }
            )
        }

        try await Task.sleep(nanoseconds: 150_000_000)
        server.cancelPendingWait()

        await #expect(throws: CancellationError.self) {
            _ = try await waitTask.value
        }
    }
}

@Suite(.serialized)
struct L10nCoverageExpansionTests {
    @Test
    func languageOptionsExposeStableIDs() {
        let ids = L10n.languageOptions.map(\.id)
        #expect(ids.first == L10n.systemLanguageCode)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains("en"))
    }

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
            var matched = false
            for _ in 0..<12 {
                UserDefaults.standard.set("ko", forKey: L10n.languageOverrideKey)
                let locale = L10n.locale()
                if locale.identifier.lowercased().hasPrefix("ko") {
                    matched = true
                    break
                }
            }
            #expect(matched)
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

@Suite(.serialized)
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

    @Test
    func accessErrorDescriptionAndMissingBookmarkPathAreCovered() {
        let error = CodexAuthFileAccessService.AccessError.missingAuthFile
        #expect(error.errorDescription != nil)
        #expect(!(error.errorDescription ?? "").isEmpty)

        let service = CodexAuthFileAccessService(bookmarkKey: "test.auth.file.missing.bookmark.\(UUID().uuidString)")
        do {
            _ = try service.loadAuthorizedURLFromBookmark()
            Issue.record("Expected loadAuthorizedURLFromBookmark to throw when bookmark is missing")
        } catch let accessError as CodexAuthFileAccessService.AccessError {
            switch accessError {
            case .missingAuthFile:
                #expect(true)
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test
    func resolveAuthFileURLForSwitchCoversFallbackOrMissingPath() {
        let service = CodexAuthFileAccessService(bookmarkKey: "test.auth.file.resolve.\(UUID().uuidString)")
        let fallbackURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/auth.json")
        let fallbackExists = FileManager.default.fileExists(atPath: fallbackURL.path)

        if fallbackExists {
            do {
                let resolved = try service.resolveAuthFileURLForSwitch(sessionAuthorizedURL: nil)
                #expect(resolved.standardizedFileURL.path == fallbackURL.standardizedFileURL.path)
            } catch {
                Issue.record("Expected fallback auth file path to resolve, got error: \(error)")
            }
        } else {
            do {
                _ = try service.resolveAuthFileURLForSwitch(sessionAuthorizedURL: nil)
                Issue.record("Expected missing auth file error when fallback path does not exist")
            } catch let accessError as CodexAuthFileAccessService.AccessError {
                switch accessError {
                case .missingAuthFile:
                    #expect(true)
                }
            } catch {
                Issue.record("Unexpected error type: \(error)")
            }
        }
    }

    @Test
    func resolveAuthFileURLForSwitchThrowsMissingWhenInjectedFallbackPathDoesNotExist() {
        let missingFallback = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString)-auth.json")
        let service = CodexAuthFileAccessService(
            bookmarkKey: "test.auth.file.resolve.missing.\(UUID().uuidString)",
            fallbackAuthFileURLProvider: { missingFallback }
        )

        do {
            _ = try service.resolveAuthFileURLForSwitch(sessionAuthorizedURL: nil)
            Issue.record("Expected missingAuthFile error when fallback path is missing")
        } catch let accessError as CodexAuthFileAccessService.AccessError {
            switch accessError {
            case .missingAuthFile:
                #expect(true)
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

@Suite(.serialized)
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
    func normalizeStoredImportedAccountNamesFallsBackToDisplayNameWhenEmailIsMissing() {
        let targetID = UUID(uuidString: "00000000-0000-0000-0000-00000000B501")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: targetID,
                    name: "OAuth Account",
                    usedUnits: 0,
                    quota: 100,
                    apiToken: "token-a",
                    chatGPTAccountID: "acct-display"
                )
            ],
            mode: .manual
        )
        let localAccounts = [
            LocalCodexOAuthAccount(
                id: "local-display",
                displayName: "Display Name",
                email: nil,
                source: "test",
                accessToken: "token-a",
                chatGPTAccountID: "acct-display"
            )
        ]
        let coordinator = PoolDashboardLocalAccountsCoordinator()

        coordinator.normalizeStoredImportedAccountNames(
            state: &state,
            localAccounts: localAccounts
        )

        #expect(state.accounts.first(where: { $0.id == targetID })?.name == "Display Name")
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

    @Test
    func loadLocalOAuthAccountsReadFailureSetsErrorMessage() {
        let coordinator = PoolDashboardLocalAccountsCoordinator()
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewModel = LocalOAuthImportViewModel()
        let missingURL = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)-auth.json")

        coordinator.loadLocalOAuthAccounts(
            from: missingURL,
            state: &state,
            viewModel: &viewModel,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: "test.local.accounts.missing.\(UUID().uuidString)")
        )

        #expect(viewModel.errorMessage != nil)
        #expect(!(viewModel.errorMessage ?? "").isEmpty)
    }

    @Test
    func saveAuthFileBookmarkFailureSetsErrorMessage() {
        let coordinator = PoolDashboardLocalAccountsCoordinator()
        var viewModel = LocalOAuthImportViewModel()
        let invalidURL = URL(string: "https://example.com/auth.json")!

        coordinator.saveAuthFileBookmark(
            for: invalidURL,
            viewModel: &viewModel,
            authFileAccessService: CodexAuthFileAccessService(bookmarkKey: "test.local.accounts.save.fail.\(UUID().uuidString)")
        )

        #expect(viewModel.errorMessage != nil)
        #expect(!(viewModel.errorMessage ?? "").isEmpty)
    }

    @Test
    func loadLocalOAuthAccountsFromBookmarkResavesWhenBookmarkIsStale() throws {
        let bookmarkKey = "test.local.accounts.stale.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let service = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)
        let coordinator = PoolDashboardLocalAccountsCoordinator()
        let authJSON = """
        {
          "session": {
            "email": "stale@example.com",
            "account_id": "acct-stale",
            "access_token": "sk-stale-token"
          }
        }
        """

        try withTemporaryFile(contents: authJSON) { originalURL in
            try service.saveBookmark(for: originalURL)

            let movedURL = originalURL.deletingLastPathComponent().appendingPathComponent("moved-\(UUID().uuidString).json")
            try FileManager.default.moveItem(at: originalURL, to: movedURL)
            defer { try? FileManager.default.removeItem(at: movedURL) }

            var state = AccountPoolState(accounts: [], mode: .manual)
            var viewModel = LocalOAuthImportViewModel()

            let result = coordinator.loadLocalOAuthAccountsFromBookmark(
                state: &state,
                viewModel: &viewModel,
                authFileAccessService: service,
                currentAuthorizedAuthFileURL: nil
            )

            #expect(result.didLoadAccounts)
            #expect(result.authorizedURL?.standardizedFileURL.lastPathComponent == movedURL.lastPathComponent)
            #expect(viewModel.accounts.count == 1)
            #expect(viewModel.errorMessage == nil)

            let resolvedAfterResave = try service.loadAuthorizedURLFromBookmark()
            #expect(resolvedAfterResave.url.standardizedFileURL.lastPathComponent == movedURL.lastPathComponent)
            #expect(!resolvedAfterResave.wasStale)
        }
    }

    @Test
    func hasSavedAuthFileBookmarkReflectsBookmarkPresence() throws {
        let bookmarkKey = "test.local.accounts.saved.check.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defer { defaults.removeObject(forKey: bookmarkKey) }

        let service = CodexAuthFileAccessService(bookmarkKey: bookmarkKey)
        let coordinator = PoolDashboardLocalAccountsCoordinator()

        #expect(!coordinator.hasSavedAuthFileBookmark(authFileAccessService: service))

        try withTemporaryFile(contents: "{\"access_token\":\"token\"}") { authFileURL in
            try service.saveBookmark(for: authFileURL)
            #expect(coordinator.hasSavedAuthFileBookmark(authFileAccessService: service))
        }
    }
}

@Suite(.serialized)
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

    #if canImport(AppKit)
    @Test
    func authFilePanelConfiguredOpenPanelUsesExpectedDefaults() {
        let home = URL(fileURLWithPath: "/tmp/cpm-home-\(UUID().uuidString)", isDirectory: true)
        let panel = CodexAuthFilePanelService.configuredOpenPanel(homeDirectory: home)

        #expect(panel.canChooseFiles)
        #expect(panel.canChooseDirectories == false)
        #expect(panel.allowsMultipleSelection == false)
        #expect(panel.allowedContentTypes.contains(.json))
        #expect(panel.prompt == L10n.text("common.choose"))
        #expect(panel.message == L10n.text("auth.file_panel.message_select_auth_json"))
        #expect(panel.directoryURL?.path == home.appending(path: ".codex").path)
        #expect(panel.nameFieldStringValue.isEmpty == false)
    }

    @Test
    func authFilePanelPickURLFromPanelHandlesAcceptedAndCancelledStates() {
        let panel = NSOpenPanel()
        var acceptedRunModalCalled = false
        var cancelledRunModalCalled = false

        let accepted = CodexAuthFilePanelService.pickURLFromPanel(panel) { _ in
            acceptedRunModalCalled = true
            return .OK
        }
        #expect(acceptedRunModalCalled)
        #expect(accepted == panel.url)

        let cancelled = CodexAuthFilePanelService.pickURLFromPanel(panel) { _ in
            cancelledRunModalCalled = true
            return .cancel
        }
        #expect(cancelledRunModalCalled)
        #expect(cancelled == nil)
    }
    #endif

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
    func switchAndLaunchDefaultExecutorSwitchOnlyRewritesAuthFile() async throws {
        let sourceJSON = """
        {
          "session": {
            "access_token": "old-token",
            "profile": { "email": "old@example.com" },
            "account_id": "old-account"
          }
        }
        """
        let authURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("switch-default-\(UUID().uuidString).json")
        try Data(sourceJSON.utf8).write(to: authURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: authURL) }

        let coordinator = PoolDashboardSwitchLaunchCoordinator()
        let output = await coordinator.switchAndLaunch(
            account: makeSwitchableAccount(token: "new-token", accountID: "acct-new"),
            switchWithoutLaunching: true,
            launchTarget: .codex,
            currentAuthorizedAuthFileURL: authURL,
            authFileAccessService: StubAuthFileURLResolver(result: .success(authURL)),
            authorizeAuthFile: { nil }
        )

        #expect(output.errorMessage == nil)
        #expect(output.didSwitchAuth == true)
        #expect(output.sessionAuthorizedAuthFileURL == authURL)

        let rewritten = try Data(contentsOf: authURL)
        let root = try #require(JSONSerialization.jsonObject(with: rewritten) as? [String: Any])
        let session = try #require(root["session"] as? [String: Any])
        let profile = try #require(session["profile"] as? [String: Any])
        #expect(session["access_token"] as? String == "new-token")
        #expect(session["account_id"] as? String == "acct-new")
        #expect(profile["email"] as? String == "switch@example.com")
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
    func inMemoryTokenVaultPruneKeepsAllowedCredentialsAndReportsRemovedCount() {
        let vault = InMemoryAccountTokenVault()
        let keptID = UUID()
        let removedID = UUID()
        let missingAllowedID = UUID()
        let keptCredential = OAuthCredential(
            accessToken: "kept-access",
            refreshToken: "kept-refresh",
            idToken: "kept-id",
            lastRefreshAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        vault.setOAuthCredential(keptCredential, for: keptID)
        vault.setToken("removed-access", for: removedID)

        let removedCount = vault.pruneTokens(keeping: [keptID, missingAllowedID])

        #expect(removedCount == 1)
        #expect(vault.tokenCount == 1)
        #expect(vault.oauthCredential(for: keptID) == keptCredential)
        #expect(vault.token(for: removedID) == nil)
        #expect(vault.pruneTokens(keeping: [keptID]) == 0)
    }

    @Test
    func userDefaultsTokenVaultPrunePersistsOnlyAllowedRawEntries() {
        let suiteName = "CodexPoolManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "tokens"
        let vault = UserDefaultsAccountTokenVault(defaults: defaults, key: key)
        let keptID = UUID()
        let removedID = UUID()
        let keptCredential = OAuthCredential(
            accessToken: "kept-access",
            refreshToken: "kept-refresh",
            idToken: "kept-id",
            lastRefreshAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        vault.setOAuthCredential(keptCredential, for: keptID)
        vault.setToken("removed-access", for: removedID)
        var rawStorage = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        rawStorage["not-a-uuid"] = "legacy-orphan-token"
        defaults.set(rawStorage, forKey: key)

        let removedCount = vault.pruneTokens(keeping: [keptID])

        #expect(removedCount == 2)
        #expect(vault.tokenCount == 1)
        #expect(vault.oauthCredential(for: keptID) == keptCredential)
        #expect(vault.token(for: removedID) == nil)
        #expect(Set((defaults.dictionary(forKey: key) as? [String: String] ?? [:]).keys) == Set([keptID.uuidString]))
        #expect(vault.pruneTokens(keeping: [keptID]) == 0)
    }

    @Test
    func userDefaultsTokenVaultDecodesLegacyTrimmedTokensAndIgnoresBlankRawValues() {
        let suiteName = "CodexPoolManagerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Cannot create UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let key = "tokens"
        let legacyID = UUID()
        let blankID = UUID()
        defaults.set(
            [
                legacyID.uuidString: "  legacy-access-token\n",
                blankID.uuidString: " \n\t "
            ],
            forKey: key
        )
        let vault = UserDefaultsAccountTokenVault(defaults: defaults, key: key)

        #expect(vault.token(for: legacyID) == "legacy-access-token")
        #expect(vault.oauthCredential(for: legacyID)?.refreshToken == nil)
        #expect(vault.oauthCredential(for: blankID) == nil)
        #expect(vault.tokenCount == 2)
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

struct UsageAnalyticsCanonicalizationCoverageTests {
    @Test
    func usageAnalyticsRecordInitializationAndDecodingDeriveFallbackValues() throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 1_800_000_000)
        let initialized = UsageAnalyticsRecord(
            timestamp: timestamp,
            accountKey: "record-init",
            weeklyDeltaPercent: 7,
            fiveHourDeltaPercent: 2,
            fiveHourAbsolutePercent: 40
        )
        #expect(initialized.weeklyAbsolutePercent == 7)
        #expect(initialized.weeklyRemainingPercent == 93)
        #expect(initialized.fiveHourRemainingPercent == 60)

        let payload = """
        {
          "timestamp": 1800000000,
          "accountKey": "decoded",
          "fiveHourAbsolutePercent": 30,
          "weeklyWastedPercent": -4,
          "fiveHourWastedPercent": -5,
          "weeklyIdleDelayMinutes": -6
        }
        """
        let decoded = try JSONDecoder().decode(UsageAnalyticsRecord.self, from: Data(payload.utf8))

        #expect(decoded.weeklyDeltaPercent == 0)
        #expect(decoded.fiveHourDeltaPercent == 0)
        #expect(decoded.weeklyAbsolutePercent == 0)
        #expect(decoded.weeklyRemainingPercent == 100)
        #expect(decoded.fiveHourRemainingPercent == 70)
        #expect(decoded.weeklyWastedPercent == 0)
        #expect(decoded.fiveHourWastedPercent == 0)
        #expect(decoded.weeklyIdleDelayMinutes == 0)
    }

    @Test
    func usageAnalyticsSnapshotAndStateDecodingUseEmptyFallbacks() throws {
        let snapshot = try JSONDecoder().decode(
            UsageAnalyticsAccountSnapshot.self,
            from: Data(#"{"accountKey":"snapshot"}"#.utf8)
        )
        #expect(snapshot.accountKey == "snapshot")
        #expect(snapshot.lastWeeklyPercent == 0)
        #expect(snapshot.lastFiveHourPercent == nil)
        #expect(snapshot.lastSeenAt == .distantPast)

        let state = try JSONDecoder().decode(UsageAnalyticsState.self, from: Data("{}".utf8))
        #expect(state.records.isEmpty)
        #expect(state.snapshots.isEmpty)
        #expect(state.thresholdEvents.isEmpty)
        #expect(state.switchEvents.isEmpty)
        #expect(state.lastActiveAccountKey == nil)
        #expect(state.lastUpdatedAt == nil)
    }

    @Test
    func normalizedStateCanonicalizesLegacyAccountKeysAcrossAnalyticsCollections() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let account = AgentAccount(
            id: accountID,
            name: "Canonical",
            usedUnits: 20,
            quota: 100,
            apiToken: "token-canonical",
            email: "Canonical@Example.COM",
            chatGPTAccountID: "ACCT-CANONICAL",
            identityScope: "Org-Scope"
        )
        let canonicalKey = account.usageAnalyticsAccountKey
        let olderSnapshot = UsageAnalyticsAccountSnapshot(
            accountKey: "email:canonical@example.com",
            lastWeeklyPercent: 10,
            lastFiveHourPercent: 11,
            lastSeenAt: now.addingTimeInterval(-120)
        )
        let newerSnapshot = UsageAnalyticsAccountSnapshot(
            accountKey: "account:acct-canonical|scope:org-scope",
            lastWeeklyPercent: 22,
            lastFiveHourPercent: 23,
            lastSeenAt: now
        )
        let state = UsageAnalyticsState(
            records: [
                UsageAnalyticsRecord(
                    timestamp: now,
                    accountKey: "email:CANONICAL@EXAMPLE.COM",
                    weeklyDeltaPercent: 3,
                    fiveHourDeltaPercent: 1,
                    activeAccountKeyAtSync: "token:token-canonical"
                )
            ],
            snapshots: [olderSnapshot, newerSnapshot],
            thresholdEvents: [
                UsageAnalyticsThresholdEvent(
                    timestamp: now,
                    accountKey: "id:\(accountID.uuidString.uppercased())",
                    kind: .weekly,
                    thresholdPercent: 50,
                    previousRemainingPercent: 55,
                    currentRemainingPercent: 45
                )
            ],
            switchEvents: [
                UsageAnalyticsSwitchEvent(
                    timestamp: now,
                    fromAccountKey: "email:canonical@example.com",
                    toAccountKey: "token:token-canonical",
                    fromRemainingPercent: 30,
                    toRemainingPercent: 80,
                    trigger: "test"
                )
            ],
            lastActiveAccountKey: "account:ACCT-CANONICAL|scope:ORG-SCOPE",
            lastUpdatedAt: now
        )

        let normalized = UsageAnalyticsEngine.normalized(
            state: state,
            accounts: [account],
            now: now,
            calendar: Calendar(identifier: .gregorian)
        )

        #expect(normalized.records.map { $0.accountKey } == [canonicalKey])
        #expect(normalized.records.first?.activeAccountKeyAtSync == canonicalKey)
        #expect(normalized.snapshots.count == 1)
        #expect(normalized.snapshots.first?.accountKey == canonicalKey)
        #expect(normalized.snapshots.first?.lastWeeklyPercent == 22)
        #expect(normalized.thresholdEvents.map { $0.accountKey } == [canonicalKey])
        #expect(normalized.switchEvents.first?.fromAccountKey == canonicalKey)
        #expect(normalized.switchEvents.first?.toAccountKey == canonicalKey)
        #expect(normalized.lastActiveAccountKey == canonicalKey)
    }

    @Test
    func analyticsAnomaliesReportUsageSpikeMissingActivityAndResetDrift() {
        let now = Date(timeIntervalSince1970: 1_800_100_000)
        let driftingAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C201")!,
            name: "Drifter",
            usedUnits: 40,
            quota: 100,
            chatGPTAccountID: "drifter",
            usageWindowResetAt: now.addingTimeInterval(8 * 3600)
        )
        let quietAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C202")!,
            name: "Quiet",
            usedUnits: 10,
            quota: 100,
            chatGPTAccountID: "quiet"
        )
        let state = UsageAnalyticsState(
            records: [
                UsageAnalyticsRecord(
                    timestamp: now.addingTimeInterval(-10 * 60),
                    accountKey: driftingAccount.usageAnalyticsAccountKey,
                    weeklyDeltaPercent: 24,
                    fiveHourDeltaPercent: 0
                )
            ],
            snapshots: [
                UsageAnalyticsAccountSnapshot(
                    accountKey: driftingAccount.usageAnalyticsAccountKey,
                    lastWeeklyPercent: 30,
                    lastFiveHourPercent: nil,
                    lastWeeklyResetAt: now.addingTimeInterval(3 * 3600),
                    lastSeenAt: now.addingTimeInterval(-3600)
                )
            ]
        )

        let anomalies = UsageAnalyticsEngine.anomalies(
            state: state,
            accounts: [driftingAccount, quietAccount],
            now: now
        )

        #expect(anomalies.contains { $0.title == "Usage Spike" && $0.severity == .warning })
        #expect(anomalies.contains { $0.title == "Reset Drift" && $0.detail.contains("Drifter") })
        #expect(anomalies.contains { $0.title == "No Recent Activity" && $0.detail.contains("Quiet") })
    }

    @Test
    func analyticsRecommendationUsesEtaAsTieBreakerWhenRemainingCapacityMatches() {
        let slowBurnAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C211")!,
            name: "Slow Burn",
            usedUnits: 40,
            quota: 100,
            chatGPTAccountID: "slow-burn"
        )
        let longEtaAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C212")!,
            name: "Long ETA",
            usedUnits: 40,
            quota: 100,
            chatGPTAccountID: "long-eta"
        )
        let etas = [
            slowBurnAccount.usageAnalyticsAccountKey: UsageAnalyticsETA(
                accountKey: slowBurnAccount.usageAnalyticsAccountKey,
                remainingPercent: 60,
                burnPerHour: 6,
                etaHours: 10
            ),
            longEtaAccount.usageAnalyticsAccountKey: UsageAnalyticsETA(
                accountKey: longEtaAccount.usageAnalyticsAccountKey,
                remainingPercent: 60,
                burnPerHour: 2,
                etaHours: 30
            )
        ]

        let recommendation = UsageAnalyticsEngine.recommendation(
            accounts: [slowBurnAccount, longEtaAccount],
            activeAccountKey: slowBurnAccount.usageAnalyticsAccountKey,
            etasByAccountKey: etas
        )

        #expect(recommendation.targetAccountKey == longEtaAccount.usageAnalyticsAccountKey)
        #expect(recommendation.reason.contains("Long ETA"))
        #expect(recommendation.reason.contains("60% -> 60%"))
    }

    @Test
    func projectedCoverageCountsRecurringWeeklyAndFiveHourResetSlots() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = Date(timeIntervalSince1970: 1_800_200_000)
        let weeklyRecurringAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C221")!,
            name: "Weekly",
            usedUnits: 20,
            quota: 100,
            chatGPTAccountID: "weekly",
            usageWindowResetAt: now.addingTimeInterval(-(167 * 3600 + 45 * 60))
        )
        let fiveHourRecurringAccount = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000C222")!,
            name: "Five Hour",
            usedUnits: 20,
            quota: 100,
            chatGPTAccountID: "five-hour",
            primaryUsageResetAt: now.addingTimeInterval(-(4 * 3600 + 45 * 60)),
            isPaid: true
        )

        let coverage = UsageAnalyticsEngine.projectedCoverage(
            accounts: [weeklyRecurringAccount, fiveHourRecurringAccount],
            now: now,
            horizonHours: 1,
            slotMinutes: 30,
            calendar: calendar
        )

        #expect(coverage.totalSlots == 2)
        #expect(coverage.uncoveredSlots == 1)
        #expect(coverage.collisionRatio == 0.5)
    }
}

private struct DefaultAPITokenAccountPoolStore: AccountPoolStoring {
    let snapshot: AccountPoolSnapshot?

    func load() -> AccountPoolSnapshot? {
        snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {}
}

struct AccountPoolStoreAndModelCoverageExpansionTests {
    private func snapshot(for account: AgentAccount) -> AccountPoolSnapshot {
        AccountPoolSnapshot(
            accounts: [account],
            groups: [],
            activities: [],
            mode: .manual,
            activeAccountID: account.id,
            manualAccountID: account.id,
            focusLockedAccountID: nil,
            minSwitchInterval: 300,
            lowUsageThresholdRatio: 0.15,
            minUsageRatioDeltaToSwitch: 0,
            lastSwitchAt: nil
        )
    }

    @Test
    func accountPoolStoringDefaultAPITokenLookupTrimsLoadedSnapshotToken() {
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-00000000A501")!
        let store = DefaultAPITokenAccountPoolStore(
            snapshot: snapshot(for: AgentAccount(
                id: accountID,
                name: "Default lookup",
                usedUnits: 0,
                quota: 100,
                apiToken: "  default-token\n"
            ))
        )

        #expect(store.apiToken(for: accountID) == "default-token")
        #expect(store.apiToken(for: UUID()) == nil)
        store.removeToken(for: accountID)
    }

    @Test
    func userDefaultsStoreAPITokenFallsBackToLoadedSnapshotWhenVaultIsEmpty() throws {
        let suiteName = "CodexPoolManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let accountID = UUID(uuidString: "00000000-0000-0000-0000-00000000A502")!
        let vault = InMemoryAccountTokenVault()
        let account = AgentAccount(
            id: accountID,
            name: "Fallback token",
            usedUnits: 0,
            quota: 100,
            apiToken: "  fallback-token\n"
        )
        let data = try JSONEncoder().encode(snapshot(for: account))
        defaults.set(data, forKey: "snapshot")

        let store = UserDefaultsAccountPoolStore(
            defaults: defaults,
            key: "snapshot",
            tokenVault: vault
        )

        #expect(store.apiToken(for: accountID) == "fallback-token")
        #expect(vault.token(for: accountID) == "fallback-token")
    }

    @Test
    func developerAwareStoreRemoveTokenDelegatesToDeveloperVaultWhenMockModeIsEnabled() throws {
        let suiteName = "CodexPoolManagerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockModeKey = "mock_mode"
        let developerTokenKey = "developer_tokens"
        let accountID = UUID(uuidString: "00000000-0000-0000-0000-00000000A503")!
        defaults.set(true, forKey: mockModeKey)
        UserDefaultsAccountTokenVault(defaults: defaults, key: developerTokenKey)
            .setToken("developer-token", for: accountID)

        let store = DeveloperAwareAccountPoolStore(
            defaults: defaults,
            productionSnapshotKey: "prod_snapshot",
            productionTokenKey: "prod_tokens",
            developerSnapshotKey: "dev_snapshot",
            developerTokenKey: developerTokenKey,
            developerMockModeKey: mockModeKey
        )

        store.removeToken(for: accountID)

        #expect(UserDefaultsAccountTokenVault(defaults: defaults, key: developerTokenKey).token(for: accountID) == nil)
    }

    @Test
    func localCodexDiscoveryFindsIdentityInNestedArraysAndUsesDefaultNameFallback() {
        let json = """
        {
          "items": [
            {
              "session": {
                "access_token": "sk-array-token-abcdef",
                "metadata": [
                  { "profile": [{ "email_address": "array@example.com" }] },
                  { "account": [{ "chatgptAccountId": "acct-array" }] }
                ]
              }
            },
            {
              "access_token": "sk-name-fallback-token-123456"
            }
          ]
        }
        """
        let accounts = LocalCodexAccountDiscovery.parseAccounts(
            from: Data(json.utf8),
            source: "/tmp/auth.json"
        )

        #expect(accounts.count == 2)
        #expect(accounts[0].email == "array@example.com")
        #expect(accounts[0].chatGPTAccountID == "acct-array")
        #expect(accounts[1].displayName == L10n.text("account.default_oauth_name"))
        #expect(accounts[1].id.contains("sk-name-fallback"))
    }

    @Test
    func agentAccountNormalizesPartialResetCreditExpiriesWithoutLegacyExpiry() {
        let firstExpiry = Date(timeIntervalSince1970: 1_800_000_000)
        let secondExpiry = Date(timeIntervalSince1970: 1_800_003_600)
        let account = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A504")!,
            name: "Partial reset credits",
            usedUnits: 0,
            quota: 100,
            rateLimitResetCreditsAvailableCount: 3,
            rateLimitResetCreditsEstimatedExpiresAt: nil,
            rateLimitResetCreditEstimatedExpiries: [firstExpiry, secondExpiry]
        )

        #expect(account.rateLimitResetCreditsEstimatedExpiresAt == firstExpiry)
        #expect(account.rateLimitResetCreditEstimatedExpiries == [
            firstExpiry,
            secondExpiry,
            secondExpiry
        ])
    }

    @Test
    func agentAccountPlanBadgeFormatsCustomAndUnspecifiedPaidPlans() {
        let custom = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A505")!,
            name: "Custom plan",
            usedUnits: 0,
            quota: 100,
            isPaid: true,
            planType: "team-pro_plus"
        )
        let unspecified = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A506")!,
            name: "Paid",
            usedUnits: 0,
            quota: 100,
            isPaid: true
        )

        #expect(custom.planBadgeText == "Team Pro Plus")
        #expect(unspecified.planBadgeText == L10n.text("account.paid_badge"))
    }

    @Test
    func groupCreationRejectsDefaultAndExactDuplicateNames() {
        var state = AccountPoolState(accounts: [], mode: .manual)

        #expect(state.createGroup("Default") == nil)
        #expect(state.createGroup("Team") == "Team")
        #expect(state.createGroup("Team") == nil)
        #expect(state.groups == [AgentAccount.defaultGroupName, "Team"])
    }

    @Test
    func hydrateMissingAPITokenRejectsMissingLoadedTokenAndExistingCurrentToken() {
        let emptyAccountID = UUID(uuidString: "00000000-0000-0000-0000-00000000A507")!
        let existingAccountID = UUID(uuidString: "00000000-0000-0000-0000-00000000A508")!
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: emptyAccountID, name: "Empty", usedUnits: 0, quota: 100, apiToken: ""),
                AgentAccount(id: existingAccountID, name: "Existing", usedUnits: 0, quota: 100, apiToken: "current-token")
            ],
            mode: .manual
        )

        let missingAccountResult = state.hydrateMissingAPIToken(for: UUID(), token: "new-token")
        let nilTokenResult = state.hydrateMissingAPIToken(for: emptyAccountID, token: nil)
        let blankTokenResult = state.hydrateMissingAPIToken(for: emptyAccountID, token: " \n ")
        let existingTokenResult = state.hydrateMissingAPIToken(for: existingAccountID, token: "new-token")

        #expect(!missingAccountResult)
        #expect(!nilTokenResult)
        #expect(!blankTokenResult)
        #expect(!existingTokenResult)
        #expect(state.accounts.first(where: { $0.id == existingAccountID })?.apiToken == "current-token")
    }

    @Test
    func appAppearancePreferenceIDsMirrorRawValues() {
        #expect(AppAppearancePreference.allCases.map(\.id) == AppAppearancePreference.allCases.map(\.rawValue))
    }

    @Test
    func poolAccountUsagePresenterLabelsRemoteNonPercentUsageAsUnits() {
        let presenter = PoolAccountUsagePresenter()
        let account = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A509")!,
            name: "Remote units",
            usedUnits: 40,
            quota: 1_000,
            apiToken: "token",
            chatGPTAccountID: "acct-units"
        )

        #expect(!presenter.isPercentUsageAccount(account))
        #expect(presenter.usageSourceLabel(for: account) == L10n.text("usage.source.units"))
    }

    @Test
    func oauthAccountUpsertResolverUsesPersonalScopeWhenIncomingScopeIsMissing() {
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-00000000A510")!
        let accounts = [
            AgentAccount(
                id: existingID,
                name: "Scoped",
                usedUnits: 0,
                quota: 100,
                apiToken: "old-token",
                chatGPTAccountID: "acct-scoped",
                identityScope: AgentAccount.personalIdentityScope
            )
        ]

        let matched = OAuthAccountUpsertResolver.resolveExistingAccountID(
            in: accounts,
            chatGPTAccountID: " ACCT-SCOPED ",
            accessToken: "new-token",
            identityScope: nil
        )

        #expect(matched == existingID)
    }

    @Test
    func menuBarPresenterReportsFocusModeText() {
        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: AccountPoolState(accounts: [], mode: .focus),
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        #expect(snapshot.modeText == L10n.text("mode.focus"))
    }

    @Test
    func switchModeDecodingRejectsUnknownLegacyValue() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(SwitchMode.self, from: Data(#""automatic""#.utf8))
        }
    }

    @Test
    func accountIdentityKeysFallBackToStableIDWhenNoIdentityExists() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000A511")!
        let account = AgentAccount(
            id: id,
            name: "No identity",
            usedUnits: 0,
            quota: 100,
            apiToken: " \n ",
            email: " ",
            chatGPTAccountID: "\t"
        )

        #expect(account.deduplicationKey == "id:\(id.uuidString.lowercased())")
        #expect(account.usageAnalyticsAccountKey == "id:\(id.uuidString.lowercased())")
    }

    @Test
    func paidSmartSwitchRemainingRatioFallsBackToWeeklyAndStopsWhenWeeklyIsExhausted() {
        let fallback = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A512")!,
            name: "Paid fallback",
            usedUnits: 20,
            quota: 100,
            primaryUsagePercent: nil,
            isPaid: true
        )
        let exhausted = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A513")!,
            name: "Paid exhausted",
            usedUnits: 100,
            quota: 100,
            primaryUsagePercent: -20,
            isPaid: true
        )
        let clampedPrimary = AgentAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000A514")!,
            name: "Paid clamped",
            usedUnits: 1,
            quota: 100,
            primaryUsagePercent: 150,
            isPaid: true
        )

        #expect(fallback.smartSwitchRemainingPercent == 80)
        #expect(exhausted.smartSwitchRemainingPercent == 0)
        #expect(clampedPrimary.smartSwitchRemainingPercent == 0)
    }

    @Test
    func updateAccountNormalizesClampsAndStoresOptionalMetadata() {
        let id = UUID(uuidString: "00000000-0000-0000-0000-00000000A515")!
        let weeklyReset = Date(timeIntervalSince1970: 1_800_001_000)
        let fiveHourReset = Date(timeIntervalSince1970: 1_800_002_000)
        let secondaryReset = Date(timeIntervalSince1970: 1_800_003_000)
        let refreshAt = Date(timeIntervalSince1970: 1_800_004_000)
        var state = AccountPoolState(
            accounts: [
                AgentAccount(id: id, name: "Original", usedUnits: 50, quota: 100)
            ],
            mode: .manual
        )

        state.updateAccount(
            id,
            name: "",
            groupName: " Team ",
            quota: 0,
            usedUnits: -5,
            apiToken: "updated-token",
            credentialType: .relayAPIKey,
            relayProviderID: " provider-id \n",
            relayProviderName: " Provider Name ",
            relayBaseURL: " https://relay.example.com/v1 ",
            relayWireAPI: " \t ",
            relayRequiresOpenAIAuth: false,
            email: "User@Example.COM",
            chatGPTAccountID: "acct-updated",
            identityScope: " Org Scope ",
            usageWindowName: "weekly_window",
            usageWindowResetAt: weeklyReset,
            primaryUsagePercent: 150,
            primaryUsageResetAt: fiveHourReset,
            secondaryUsagePercent: -10,
            secondaryUsageResetAt: secondaryReset,
            oauthRefreshToken: "refresh-token",
            oauthIDToken: "id-token",
            oauthLastRefreshAt: refreshAt,
            isPaid: true,
            planType: " team-pro ",
            now: Date(timeIntervalSince1970: 1_800_005_000)
        )

        let account = state.accounts[0]
        #expect(account.name == L10n.text("account.unnamed"))
        #expect(account.groupName == "Team")
        #expect(state.groups.contains("Team"))
        #expect(account.quota == 1)
        #expect(account.usedUnits == 0)
        #expect(account.apiToken == "updated-token")
        #expect(account.credentialType == .relayAPIKey)
        #expect(account.relayProviderID == "provider-id")
        #expect(account.relayProviderName == "Provider Name")
        #expect(account.relayBaseURL == "https://relay.example.com/v1")
        #expect(account.relayWireAPI == AgentAccount.defaultRelayWireAPI)
        #expect(!account.relayRequiresOpenAIAuth)
        #expect(account.email == "User@Example.COM")
        #expect(account.chatGPTAccountID == "acct-updated")
        #expect(account.identityScope == "org scope")
        #expect(account.usageWindowName == "weekly_window")
        #expect(account.usageWindowResetAt == weeklyReset)
        #expect(account.primaryUsagePercent == 100)
        #expect(account.primaryUsageResetAt == fiveHourReset)
        #expect(account.secondaryUsagePercent == 0)
        #expect(account.secondaryUsageResetAt == secondaryReset)
        #expect(account.oauthRefreshToken == "refresh-token")
        #expect(account.oauthIDToken == "id-token")
        #expect(account.oauthLastRefreshAt == refreshAt)
        #expect(account.isPaid)
        #expect(account.planType == "team-pro")
    }
}

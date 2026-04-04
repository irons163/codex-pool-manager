import Foundation
import AuthenticationServices
import CryptoKit
import Security
import Network
#if canImport(AppKit)
import AppKit
#endif

struct OAuthClientConfiguration: Equatable, Codable {
    let issuer: URL
    let clientID: String
    let scopes: String
    let redirectURI: String
    let originator: String
    let forcedWorkspaceID: String?

    init(
        issuer: URL,
        clientID: String = "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: String,
        redirectURI: String,
        originator: String = "codex_cli_rs",
        forcedWorkspaceID: String? = nil
    ) {
        self.issuer = issuer
        self.clientID = clientID
        self.scopes = scopes
        self.redirectURI = redirectURI
        self.originator = originator
        self.forcedWorkspaceID = forcedWorkspaceID
    }

    var authorizationEndpoint: URL {
        endpointURL(path: "/oauth/authorize")
    }

    var tokenEndpoint: URL {
        endpointURL(path: "/oauth/token")
    }

    var callbackURLScheme: String? {
        URL(string: redirectURI)?.scheme
    }

    private func endpointURL(path: String) -> URL {
        URL(string: path, relativeTo: issuer)?.absoluteURL ?? issuer
    }
}

struct OAuthAuthorizationRequest: Equatable {
    let state: String
    let codeChallenge: String
}

enum OAuthAuthorizationRequestBuilder {
    static func makeAuthorizeURL(
        config: OAuthClientConfiguration,
        request: OAuthAuthorizationRequest
    ) throws -> URL {
        var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes),
            URLQueryItem(name: "code_challenge", value: request.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: request.state),
            URLQueryItem(name: "originator", value: config.originator)
        ]
        if let forcedWorkspaceID = config.forcedWorkspaceID, !forcedWorkspaceID.isEmpty {
            components?.queryItems?.append(URLQueryItem(name: "allowed_workspace_id", value: forcedWorkspaceID))
        }

        guard let url = components?.url else {
            throw OAuthLoginError.invalidAuthorizeURL
        }
        return url
    }
}

struct OAuthCallbackPayload: Equatable {
    let code: String
    let state: String
}

enum OAuthCallbackParser {
    static func parse(callbackURL: URL) throws -> OAuthCallbackPayload {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw OAuthLoginError.invalidCallback
        }

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        if let error = items["error"], !error.isEmpty {
            throw OAuthLoginError.authorizationFailed(error)
        }

        guard let code = items["code"], !code.isEmpty else {
            throw OAuthLoginError.missingCode
        }
        guard let state = items["state"], !state.isEmpty else {
            throw OAuthLoginError.stateMismatch
        }
        return OAuthCallbackPayload(code: code, state: state)
    }
}

enum OAuthTokenRequestBuilder {
    static func authorizationCodeBody(
        clientID: String,
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) -> Data {
        formEncodedBody([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("code_verifier", codeVerifier)
        ])
    }

    private static func formEncodedBody(_ pairs: [(String, String)]) -> Data {
        let form = pairs
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? "")" }
            .joined(separator: "&")
        return Data(form.utf8)
    }
}

struct OAuthTokens: Equatable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
}

struct OAuthManualSignInPreparation: Equatable {
    let authorizationURL: URL
    let state: String
    let codeVerifier: String
}

struct OAuthIDTokenClaims: Equatable {
    let subject: String?
    let accountID: String?
    let email: String?
}

enum OAuthIDTokenClaimsParser {
    static func parse(_ idToken: String?) -> OAuthIDTokenClaims? {
        guard let idToken, !idToken.isEmpty else { return nil }
        let segments = idToken.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        let normalized = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padded = normalized.padding(
            toLength: ((normalized.count + 3) / 4) * 4,
            withPad: "=",
            startingAt: 0
        )

        guard let data = Data(base64Encoded: padded),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let subject = payload["sub"] as? String
        let accountID = (payload["account_id"] as? String) ?? (payload["accountId"] as? String)
        let email = payload["email"] as? String
        return OAuthIDTokenClaims(subject: subject, accountID: accountID, email: email)
    }
}

enum OAuthLoginError: Error, LocalizedError, Equatable {
    case invalidAuthorizeURL
    case invalidRedirectURI
    case browserStartFailed
    case invalidCallback
    case localhostCallbackStartFailed(String)
    case localhostCallbackTimedOut
    case authorizationFailed(String)
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            return L10n.text("oauth.error.invalid_authorize_url")
        case .invalidRedirectURI:
            return L10n.text("oauth.error.invalid_redirect_uri")
        case .browserStartFailed:
            return L10n.text("oauth.error.browser_start_failed")
        case .invalidCallback:
            return L10n.text("oauth.error.invalid_callback")
        case .localhostCallbackStartFailed(let message):
            return String(
                format: L10n.text("oauth.error.localhost_callback_start_failed_format"),
                message
            )
        case .localhostCallbackTimedOut:
            return L10n.text("oauth.error.localhost_callback_timed_out")
        case .authorizationFailed(let message):
            return String(format: L10n.text("oauth.error.authorization_failed_format"), message)
        case .missingCode:
            return L10n.text("oauth.error.missing_code")
        case .stateMismatch:
            return L10n.text("oauth.error.state_mismatch")
        case .tokenExchangeFailed(let message):
            return String(format: L10n.text("oauth.error.token_exchange_failed_format"), message)
        }
    }
}

struct PKCECodes {
    let codeVerifier: String
    let codeChallenge: String

    static func make() -> PKCECodes {
        let verifier = randomBase64URL(byteCount: 32)
        let challenge = sha256Base64URL(verifier)
        return PKCECodes(codeVerifier: verifier, codeChallenge: challenge)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let result = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        if result != errSecSuccess {
            let fallback = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            return fallback
        }
        return Data(bytes).base64URLEncodedString()
    }

    private static func sha256Base64URL(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64URLEncodedString()
    }
}

@MainActor
final class OAuthLoginService: NSObject {
    private let session: URLSession
    private var webAuthenticationSession: ASWebAuthenticationSession?
    private let localhostCallbackServer = LocalhostOAuthCallbackServer()
    private let presentationContextProvider = OAuthPresentationContextProvider()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(configuration: OAuthClientConfiguration) async throws -> OAuthTokens {
        try await withTaskCancellationHandler {
            let manualPreparation = try prepareManualSignIn(configuration: configuration)
            let authorizeURL = manualPreparation.authorizationURL

            let callbackURL: URL
            if let redirectURL = URL(string: configuration.redirectURI),
               let localhostConfig = LocalhostOAuthCallbackConfig(redirectURI: redirectURL) {
                callbackURL = try await beginLocalhostBrowserAuthentication(
                    authorizeURL: authorizeURL,
                    callbackConfig: localhostConfig
                )
            } else {
                guard let callbackScheme = configuration.callbackURLScheme else {
                    throw OAuthLoginError.invalidRedirectURI
                }
                callbackURL = try await beginWebAuthentication(
                    authorizeURL: authorizeURL,
                    callbackScheme: callbackScheme
                )
            }
            let payload = try OAuthCallbackParser.parse(callbackURL: callbackURL)
            guard payload.state == manualPreparation.state else {
                throw OAuthLoginError.stateMismatch
            }

            return try await exchangeCodeForTokens(
                code: payload.code,
                codeVerifier: manualPreparation.codeVerifier,
                configuration: configuration
            )
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancelPendingSignIn()
            }
        }
    }

    func prepareManualSignIn(configuration: OAuthClientConfiguration) throws -> OAuthManualSignInPreparation {
        let pkce = PKCECodes.make()
        let state = UUID().uuidString
        let request = OAuthAuthorizationRequest(state: state, codeChallenge: pkce.codeChallenge)
        let authorizeURL = try OAuthAuthorizationRequestBuilder.makeAuthorizeURL(
            config: configuration,
            request: request
        )
        return OAuthManualSignInPreparation(
            authorizationURL: authorizeURL,
            state: state,
            codeVerifier: pkce.codeVerifier
        )
    }

    func completeManualSignIn(
        configuration: OAuthClientConfiguration,
        callbackURL: URL,
        expectedState: String,
        codeVerifier: String
    ) async throws -> OAuthTokens {
        let payload = try OAuthCallbackParser.parse(callbackURL: callbackURL)
        guard payload.state == expectedState else {
            throw OAuthLoginError.stateMismatch
        }
        return try await exchangeCodeForTokens(
            code: payload.code,
            codeVerifier: codeVerifier,
            configuration: configuration
        )
    }

    private func cancelPendingSignIn() {
        webAuthenticationSession?.cancel()
        webAuthenticationSession = nil
        localhostCallbackServer.cancelPendingWait()
    }

    private func beginWebAuthentication(authorizeURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            func resumeOnce(_ result: Result<URL, Error>) {
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }

            let authSession = ASWebAuthenticationSession(
                url: authorizeURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    self.webAuthenticationSession = nil
                    resumeOnce(.failure(error))
                    return
                }
                guard let callbackURL else {
                    self.webAuthenticationSession = nil
                    resumeOnce(.failure(OAuthLoginError.invalidCallback))
                    return
                }
                self.webAuthenticationSession = nil
                resumeOnce(.success(callbackURL))
            }

            authSession.prefersEphemeralWebBrowserSession = false
            authSession.presentationContextProvider = presentationContextProvider
            self.webAuthenticationSession = authSession
            guard authSession.start() else {
                self.webAuthenticationSession = nil
                resumeOnce(.failure(OAuthLoginError.browserStartFailed))
                return
            }
        }
    }

    private func beginLocalhostBrowserAuthentication(
        authorizeURL: URL,
        callbackConfig: LocalhostOAuthCallbackConfig
    ) async throws -> URL {
        try await localhostCallbackServer.waitForCallback(config: callbackConfig) {
            #if canImport(AppKit)
            if Thread.isMainThread {
                return NSWorkspace.shared.open(authorizeURL)
            }
            var opened = false
            DispatchQueue.main.sync {
                opened = NSWorkspace.shared.open(authorizeURL)
            }
            return opened
            #else
            return false
            #endif
        }
    }

    private func exchangeCodeForTokens(
        code: String,
        codeVerifier: String,
        configuration: OAuthClientConfiguration
    ) async throws -> OAuthTokens {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthTokenRequestBuilder.authorizationCodeBody(
            clientID: configuration.clientID,
            code: code,
            redirectURI: configuration.redirectURI,
            codeVerifier: codeVerifier
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthLoginError.tokenExchangeFailed(L10n.text("oauth.error.invalid_response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw OAuthLoginError.tokenExchangeFailed(String(message.prefix(200)))
        }

        let tokenResponse = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
        return OAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            idToken: tokenResponse.idToken
        )
    }

    private struct TokenExchangeResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }
}

private final class OAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(AppKit)
        return NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first
            ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

struct LocalhostOAuthCallbackConfig: Equatable {
    let host: String
    let port: UInt16
    let callbackPath: String

    init?(redirectURI: URL) {
        guard let scheme = redirectURI.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = redirectURI.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1" || host == "::1" else {
            return nil
        }

        let port: Int
        if let explicitPort = redirectURI.port {
            port = explicitPort
        } else {
            port = scheme == "https" ? 443 : 80
        }
        guard (1...65535).contains(port), let validPort = UInt16(exactly: port) else {
            return nil
        }

        let path = redirectURI.path.isEmpty ? "/" : redirectURI.path
        self.host = host
        self.port = validPort
        self.callbackPath = path
    }

    init(host: String, port: UInt16, callbackPath: String) {
        self.host = host
        self.port = port
        self.callbackPath = callbackPath
    }
}

enum LocalhostOAuthCallbackExtractor {
    static func callbackURL(fromRequest request: String, config: LocalhostOAuthCallbackConfig) -> URL? {
        guard let firstLine = request.split(separator: "\r\n", omittingEmptySubsequences: false).first else {
            return nil
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            return nil
        }

        let target = String(parts[1])
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(pieces[0])
        guard path == config.callbackPath else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "http"
        components.host = config.host
        components.port = Int(config.port)
        components.percentEncodedPath = path
        if pieces.count > 1 {
            components.percentEncodedQuery = String(pieces[1])
        }
        return components.url
    }
}

final class LocalhostOAuthCallbackServer {
    private let queue = DispatchQueue(label: "CodexPoolManager.LocalhostOAuthCallbackServer")
    private let activeStateLock = NSLock()
    private var activeState: ContinuationState?

    private final class ContinuationState {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, Error>?
        private var completed = false
        private var readySignaled = false
        var listener: NWListener?
        private let onComplete: () -> Void

        init(_ continuation: CheckedContinuation<URL, Error>, onComplete: @escaping () -> Void) {
            self.continuation = continuation
            self.onComplete = onComplete
        }

        func complete(with result: Result<URL, Error>) {
            lock.lock()
            guard !completed, let continuation else {
                lock.unlock()
                return
            }
            completed = true
            self.continuation = nil
            let listener = self.listener
            self.listener = nil
            lock.unlock()

            listener?.cancel()
            onComplete()
            continuation.resume(with: result)
        }

        func runReadyAction(_ action: () -> Void) {
            lock.lock()
            guard !completed, !readySignaled else {
                lock.unlock()
                return
            }
            readySignaled = true
            lock.unlock()
            action()
        }
    }

    func waitForCallback(
        config: LocalhostOAuthCallbackConfig,
        timeoutNanoseconds: UInt64 = 120_000_000_000,
        onReadyToReceiveCallback: @escaping () -> Bool = { true }
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            let state = ContinuationState(continuation) { [weak self] in
                self?.clearActiveState()
            }
            setActiveState(state)

            let listener: NWListener
            do {
                let port = NWEndpoint.Port(rawValue: config.port)
                guard let port else {
                    throw OAuthLoginError.localhostCallbackStartFailed(L10n.text("oauth.error.invalid_port"))
                }
                listener = try NWListener(using: .tcp, on: port)
            } catch {
                state.complete(with: .failure(OAuthLoginError.localhostCallbackStartFailed(error.localizedDescription)))
                return
            }

            state.listener = listener

            listener.stateUpdateHandler = { newState in
                switch newState {
                case .ready:
                    Task { @MainActor in
                        state.runReadyAction {
                            if !onReadyToReceiveCallback() {
                                state.complete(with: .failure(OAuthLoginError.browserStartFailed))
                            }
                        }
                    }
                case .failed(let error):
                    Task { @MainActor in
                        state.complete(with: .failure(OAuthLoginError.localhostCallbackStartFailed(error.localizedDescription)))
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { connection in
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, _, error in
                    defer { connection.cancel() }

                    if let error {
                        state.complete(with: .failure(OAuthLoginError.localhostCallbackStartFailed(error.localizedDescription)))
                        return
                    }

                    let requestString = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    guard let callbackURL = LocalhostOAuthCallbackExtractor.callbackURL(fromRequest: requestString, config: config) else {
                        self.sendHTTPResponse(
                            status: "404 Not Found",
                            body: "<html><body><h3>Invalid callback path</h3></body></html>",
                            on: connection
                        )
                        return
                    }

                    self.sendHTTPResponse(
                        status: "200 OK",
                        body: self.successCallbackHTML(),
                        on: connection
                    )
                    self.activateHostApp()
                    state.complete(with: .success(callbackURL))
                }
            }

            listener.start(queue: queue)

            Task {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                state.complete(with: .failure(OAuthLoginError.localhostCallbackTimedOut))
            }
        }
    }

    func cancelPendingWait() {
        activeStateLock.lock()
        let state = activeState
        activeStateLock.unlock()

        state?.complete(with: .failure(CancellationError()))
    }

    private func setActiveState(_ state: ContinuationState) {
        activeStateLock.lock()
        activeState = state
        activeStateLock.unlock()
    }

    private func clearActiveState() {
        activeStateLock.lock()
        activeState = nil
        activeStateLock.unlock()
    }

    private func sendHTTPResponse(status: String, body: String, on connection: NWConnection) {
        let payload = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: payload.data(using: .utf8), completion: .contentProcessed { _ in })
    }

    private func successCallbackHTML() -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>Login complete</title>
          <meta name="viewport" content="width=device-width, initial-scale=1">
        </head>
        <body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;padding:24px;line-height:1.5;">
          <h3>Login complete. You can return to the app.</h3>
          <p>This tab can be closed now.</p>
        </body>
        </html>
        """
    }

    private func activateHostApp() {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        #endif
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "+&=")
        return set
    }()
}

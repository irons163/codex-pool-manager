import Foundation
import AuthenticationServices
import CryptoKit
import Security
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
        clientID: String,
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

enum OAuthLoginError: Error, LocalizedError, Equatable {
    case invalidAuthorizeURL
    case invalidRedirectURI
    case browserStartFailed
    case invalidCallback
    case authorizationFailed(String)
    case missingCode
    case stateMismatch
    case tokenExchangeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizeURL:
            return "授權網址無效"
        case .invalidRedirectURI:
            return "Redirect URI 設定無效"
        case .browserStartFailed:
            return "無法開啟 OAuth 登入頁"
        case .invalidCallback:
            return "回呼資料無效"
        case .authorizationFailed(let message):
            return "授權失敗：\(message)"
        case .missingCode:
            return "授權結果缺少 code"
        case .stateMismatch:
            return "授權狀態驗證失敗"
        case .tokenExchangeFailed(let message):
            return "Token 交換失敗：\(message)"
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
    private let presentationContextProvider = OAuthPresentationContextProvider()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(configuration: OAuthClientConfiguration) async throws -> OAuthTokens {
        guard let callbackScheme = configuration.callbackURLScheme else {
            throw OAuthLoginError.invalidRedirectURI
        }

        let pkce = PKCECodes.make()
        let state = UUID().uuidString
        let request = OAuthAuthorizationRequest(state: state, codeChallenge: pkce.codeChallenge)
        let authorizeURL = try OAuthAuthorizationRequestBuilder.makeAuthorizeURL(
            config: configuration,
            request: request
        )

        let callbackURL = try await beginWebAuthentication(
            authorizeURL: authorizeURL,
            callbackScheme: callbackScheme
        )
        let payload = try OAuthCallbackParser.parse(callbackURL: callbackURL)
        guard payload.state == state else {
            throw OAuthLoginError.stateMismatch
        }

        return try await exchangeCodeForTokens(
            code: payload.code,
            pkce: pkce,
            configuration: configuration
        )
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

    private func exchangeCodeForTokens(
        code: String,
        pkce: PKCECodes,
        configuration: OAuthClientConfiguration
    ) async throws -> OAuthTokens {
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuthTokenRequestBuilder.authorizationCodeBody(
            clientID: configuration.clientID,
            code: code,
            redirectURI: configuration.redirectURI,
            codeVerifier: pkce.codeVerifier
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OAuthLoginError.tokenExchangeFailed("無效回應")
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

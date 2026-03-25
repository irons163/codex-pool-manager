import Foundation

struct CodexClientHTTPError: Error, Equatable {
    let statusCode: Int
}

enum CodexSyncError: Error, Equatable, LocalizedError {
    case unauthorized
    case rateLimited
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "授權失敗，請檢查 API Token。"
        case .rateLimited:
            return "已達速率限制，請稍後再試。"
        case .network:
            return "網路異常，請檢查連線。"
        case .unknown:
            return "同步失敗，請稍後再試。"
        }
    }
}

struct CodexUsage: Equatable {
    let usedUnits: Int
    let quota: Int
    let usageWindowName: String?
    let usageWindowResetAt: Date?
    let accountID: String?
    let accountEmail: String?

    init(
        usedUnits: Int,
        quota: Int,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        accountID: String? = nil,
        accountEmail: String? = nil
    ) {
        self.usedUnits = usedUnits
        self.quota = quota
        self.usageWindowName = usageWindowName
        self.usageWindowResetAt = usageWindowResetAt
        self.accountID = accountID
        self.accountEmail = accountEmail
    }
}

protocol CodexUsageClient {
    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage
}

struct CodexUsageSyncService<Client: CodexUsageClient> {
    let client: Client
    let maxRetries: Int

    init(client: Client, maxRetries: Int = 0) {
        self.client = client
        self.maxRetries = max(0, maxRetries)
    }

    func sync(state: inout AccountPoolState, now: Date = .now) async throws {
        for account in state.accounts {
            guard !account.apiToken.isEmpty,
                  let chatGPTAccountID = account.chatGPTAccountID,
                  !chatGPTAccountID.isEmpty else {
                continue
            }
            let usage = try await fetchUsageWithRetry(
                accessToken: account.apiToken,
                accountID: chatGPTAccountID
            )
            state.updateAccount(
                account.id,
                quota: usage.quota,
                usedUnits: usage.usedUnits,
                usageWindowName: usage.usageWindowName,
                usageWindowResetAt: usage.usageWindowResetAt,
                now: now
            )
        }
        state.markUsageSynced(at: now)
    }

    private func fetchUsageWithRetry(accessToken: String, accountID: String) async throws -> CodexUsage {
        var attempt = 0
        while true {
            do {
                return try await client.fetchUsage(accessToken: accessToken, accountID: accountID)
            } catch {
                if attempt >= maxRetries {
                    throw mapSyncError(error)
                }
                attempt += 1
            }
        }
    }

    private func mapSyncError(_ error: Error) -> CodexSyncError {
        if let http = error as? CodexClientHTTPError {
            if http.statusCode == 401 || http.statusCode == 403 {
                return .unauthorized
            }
            if http.statusCode == 429 {
                return .rateLimited
            }
            return .unknown
        }
        if error is URLError {
            return .network
        }
        return .unknown
    }
}

struct OpenAICodexUsageClient: CodexUsageClient {
    var endpoint: URL
    var session: URLSession = .shared
    var onRawResponse: ((String) -> Void)?

    init(
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        session: URLSession = .shared,
        onRawResponse: ((String) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        self.onRawResponse = onRawResponse
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        enum RequestPolicy {
            static let timeout: TimeInterval = 30
        }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = RequestPolicy.timeout
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CodexClientHTTPError(statusCode: statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            onRawResponse?(raw)
        }

        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        let usageWindowName = payload.rateLimit?.primaryWindow?.name ?? "primary_window"
        let usageWindowResetAt = payload.rateLimit?.primaryWindow?.resetAt
        let accountID = payload.accountID
        let accountEmail = payload.email
        if let usedUnits = payload.usedUnits, let quota = payload.quota {
            return CodexUsage(
                usedUnits: usedUnits,
                quota: quota,
                usageWindowName: usageWindowName,
                usageWindowResetAt: usageWindowResetAt,
                accountID: accountID,
                accountEmail: accountEmail
            )
        }
        if let usedPercent = payload.rateLimit?.primaryWindow?.usedPercent {
            let clamped = min(max(Int(usedPercent.rounded()), 0), 100)
            return CodexUsage(
                usedUnits: clamped,
                quota: 100,
                usageWindowName: usageWindowName,
                usageWindowResetAt: usageWindowResetAt,
                accountID: accountID,
                accountEmail: accountEmail
            )
        }
        throw CodexSyncError.unknown
    }

    private struct UsagePayload: Decodable {
        let usedUnits: Int?
        let quota: Int?
        let rateLimit: RateLimit?
        let accountID: String?
        let email: String?

        private enum CodingKeys: String, CodingKey {
            case usedUnits = "used_units"
            case quota
            case rateLimit = "rate_limit"
            case accountID = "account_id"
            case email
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let name: String?
        let resetAt: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            usedPercent = try container.decodeIfPresent(Double.self, forKeys: ["used_percent", "usedPercent"])
            name = try container.decodeIfPresent(String.self, forKeys: ["name", "window_name", "windowName"])
            resetAt = try container.decodeDateIfPresent(forKeys: ["reset_at", "resets_at", "resetAt", "resetsAt"])
        }
    }

    fileprivate struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    fileprivate static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
private extension KeyedDecodingContainer where K == OpenAICodexUsageClient.DynamicCodingKey {
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKeys keys: [String]) throws -> T? {
        for key in keys {
            guard let codingKey = OpenAICodexUsageClient.DynamicCodingKey(stringValue: key),
                  contains(codingKey) else {
                continue
            }
            if let value = try? decodeIfPresent(T.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }

    func decodeDateIfPresent(forKeys keys: [String]) throws -> Date? {
        if let unix = try decodeIfPresent(Double.self, forKeys: keys) {
            return Date(timeIntervalSince1970: unix)
        }
        if let raw = try decodeIfPresent(String.self, forKeys: keys) {
            if let date = OpenAICodexUsageClient.iso8601Formatter.date(from: raw) {
                return date
            }
            let fallbackFormatter = ISO8601DateFormatter()
            if let date = fallbackFormatter.date(from: raw) {
                return date
            }
            if let unix = Double(raw) {
                return Date(timeIntervalSince1970: unix)
            }
        }
        return nil
    }
}


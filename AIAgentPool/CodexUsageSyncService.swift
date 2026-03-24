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
            state.updateAccount(account.id, quota: usage.quota, usedUnits: usage.usedUnits, now: now)
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

    init(endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!) {
        self.endpoint = endpoint
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

        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        if let usedUnits = payload.usedUnits, let quota = payload.quota {
            return CodexUsage(usedUnits: usedUnits, quota: quota)
        }
        if let usedPercent = payload.rateLimit?.primaryWindow?.usedPercent {
            let clamped = min(max(usedPercent, 0), 100)
            return CodexUsage(usedUnits: clamped, quota: 100)
        }
        throw CodexSyncError.unknown
    }

    private struct UsagePayload: Decodable {
        let usedUnits: Int?
        let quota: Int?
        let rateLimit: RateLimit?

        private enum CodingKeys: String, CodingKey {
            case usedUnits = "used_units"
            case quota
            case rateLimit = "rate_limit"
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?

        private enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Int?

        private enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
        }
    }
}

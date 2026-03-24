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
    func fetchUsage(apiToken: String) async throws -> CodexUsage
}

struct CodexUsageSyncService<Client: CodexUsageClient> {
    let client: Client
    let maxRetries: Int

    init(client: Client, maxRetries: Int = 0) {
        self.client = client
        self.maxRetries = max(0, maxRetries)
    }

    func sync(state: inout AccountPoolState, now: Date = .now) async throws {
        for account in state.accounts where !account.apiToken.isEmpty {
            let usage = try await fetchUsageWithRetry(apiToken: account.apiToken)
            state.updateAccount(account.id, quota: usage.quota, usedUnits: usage.usedUnits, now: now)
        }
        state.markUsageSynced(at: now)
    }

    private func fetchUsageWithRetry(apiToken: String) async throws -> CodexUsage {
        var attempt = 0
        while true {
            do {
                return try await client.fetchUsage(apiToken: apiToken)
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

    init(endpoint: URL = URL(string: "https://api.openai.com/v1/usage")!) {
        self.endpoint = endpoint
    }

    func fetchUsage(apiToken: String) async throws -> CodexUsage {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CodexClientHTTPError(statusCode: statusCode)
        }

        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        return CodexUsage(usedUnits: payload.usedUnits, quota: payload.quota)
    }

    private struct UsagePayload: Decodable {
        let usedUnits: Int
        let quota: Int

        private enum CodingKeys: String, CodingKey {
            case usedUnits = "used_units"
            case quota
        }
    }
}

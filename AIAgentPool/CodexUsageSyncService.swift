import Foundation

struct CodexUsage: Equatable {
    let usedUnits: Int
    let quota: Int
}

protocol CodexUsageClient {
    func fetchUsage(apiToken: String) async throws -> CodexUsage
}

struct CodexUsageSyncService<Client: CodexUsageClient> {
    let client: Client

    func sync(state: inout AccountPoolState, now: Date = .now) async throws {
        for account in state.accounts where !account.apiToken.isEmpty {
            let usage = try await client.fetchUsage(apiToken: account.apiToken)
            state.updateAccount(account.id, quota: usage.quota, usedUnits: usage.usedUnits, now: now)
        }
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
            throw URLError(.badServerResponse)
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

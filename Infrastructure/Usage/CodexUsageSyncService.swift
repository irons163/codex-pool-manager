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
            return L10n.text("usage.sync.error.unauthorized")
        case .rateLimited:
            return L10n.text("usage.sync.error.rate_limited")
        case .network:
            return L10n.text("usage.sync.error.network")
        case .unknown:
            return L10n.text("usage.sync.error.unknown")
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
    let primaryUsagePercent: Int?
    let primaryUsageResetAt: Date?
    let secondaryUsagePercent: Int?
    let secondaryUsageResetAt: Date?
    let isPaid: Bool

    init(
        usedUnits: Int,
        quota: Int,
        usageWindowName: String? = nil,
        usageWindowResetAt: Date? = nil,
        accountID: String? = nil,
        accountEmail: String? = nil,
        primaryUsagePercent: Int? = nil,
        primaryUsageResetAt: Date? = nil,
        secondaryUsagePercent: Int? = nil,
        secondaryUsageResetAt: Date? = nil,
        isPaid: Bool = false
    ) {
        self.usedUnits = usedUnits
        self.quota = quota
        self.usageWindowName = usageWindowName
        self.usageWindowResetAt = usageWindowResetAt
        self.accountID = accountID
        self.accountEmail = accountEmail
        self.primaryUsagePercent = primaryUsagePercent
        self.primaryUsageResetAt = primaryUsageResetAt
        self.secondaryUsagePercent = secondaryUsagePercent
        self.secondaryUsageResetAt = secondaryUsageResetAt
        self.isPaid = isPaid
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
        let missingTokenMessage = L10n.text("usage.sync.excluded.missing_token")
        let missingAccountIDMessage = L10n.text("usage.sync.excluded.missing_account_id")
        for account in state.accounts {
            guard !account.apiToken.isEmpty else {
                state.setUsageSyncExclusion(for: account.id, reason: missingTokenMessage, now: now)
                continue
            }
            guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
                state.setUsageSyncExclusion(for: account.id, reason: missingAccountIDMessage, now: now)
                continue
            }

            do {
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
                    primaryUsagePercent: usage.primaryUsagePercent,
                    primaryUsageResetAt: usage.primaryUsageResetAt,
                    secondaryUsagePercent: usage.secondaryUsagePercent,
                    secondaryUsageResetAt: usage.secondaryUsageResetAt,
                    isPaid: usage.isPaid,
                    now: now
                )
                state.setUsageSyncExclusion(for: account.id, reason: nil, now: now)
            } catch {
                let mapped = mapSyncError(error)
                state.setUsageSyncExclusion(
                    for: account.id,
                    reason: mapped.localizedDescription,
                    now: now
                )
            }
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
        let isPaid = inferPaidStatus(from: payload)
        let primaryWindow = payload.rateLimit?.primaryWindow
        let secondaryWindow = payload.rateLimit?.secondaryWindow
        let resolvedWindows = resolveUsageWindows(
            isPaid: isPaid,
            primaryWindow: primaryWindow,
            secondaryWindow: secondaryWindow
        )
        let selectedWindow = resolvedWindows.selectedWindow
        let usageWindowName = selectedWindow?.name ?? resolvedWindows.defaultWindowName
        let usageWindowResetAt = selectedWindow?.resetAt
            ?? resolvedWindows.weeklyWindow?.resetAt
            ?? resolvedWindows.fiveHourWindow?.resetAt
        // Normalize paid-account semantics:
        // primaryUsage* => 5h window, secondaryUsage* => weekly window.
        let primaryUsagePercent = percentValue(from: resolvedWindows.fiveHourWindow?.usedPercent)
        let secondaryUsagePercent = percentValue(from: resolvedWindows.weeklyWindow?.usedPercent)
        let accountID = payload.accountID
        let accountEmail = payload.email
        if let usedUnits = payload.usedUnits, let quota = payload.quota {
            return CodexUsage(
                usedUnits: usedUnits,
                quota: quota,
                usageWindowName: usageWindowName,
                usageWindowResetAt: usageWindowResetAt,
                accountID: accountID,
                accountEmail: accountEmail,
                primaryUsagePercent: primaryUsagePercent,
                primaryUsageResetAt: resolvedWindows.fiveHourWindow?.resetAt,
                secondaryUsagePercent: secondaryUsagePercent,
                secondaryUsageResetAt: resolvedWindows.weeklyWindow?.resetAt,
                isPaid: isPaid
            )
        }
        if let usedPercent = selectedWindow?.usedPercent
            ?? primaryWindow?.usedPercent
            ?? secondaryWindow?.usedPercent {
            let clamped = min(max(Int(usedPercent.rounded()), 0), 100)
            return CodexUsage(
                usedUnits: clamped,
                quota: 100,
                usageWindowName: usageWindowName,
                usageWindowResetAt: usageWindowResetAt,
                accountID: accountID,
                accountEmail: accountEmail,
                primaryUsagePercent: primaryUsagePercent,
                primaryUsageResetAt: resolvedWindows.fiveHourWindow?.resetAt,
                secondaryUsagePercent: secondaryUsagePercent,
                secondaryUsageResetAt: resolvedWindows.weeklyWindow?.resetAt,
                isPaid: isPaid
            )
        }
        throw CodexSyncError.unknown
    }

    private struct ResolvedUsageWindows {
        let selectedWindow: Window?
        let fiveHourWindow: Window?
        let weeklyWindow: Window?
        let defaultWindowName: String
    }

    private enum PaidWindowRole {
        case fiveHour
        case weekly
    }

    private func resolveUsageWindows(
        isPaid: Bool,
        primaryWindow: Window?,
        secondaryWindow: Window?
    ) -> ResolvedUsageWindows {
        if !isPaid {
            return ResolvedUsageWindows(
                selectedWindow: primaryWindow ?? secondaryWindow,
                fiveHourWindow: primaryWindow,
                weeklyWindow: secondaryWindow,
                defaultWindowName: "primary_window"
            )
        }

        let roles = resolvePaidWindowRoles(primaryWindow: primaryWindow, secondaryWindow: secondaryWindow)
        return ResolvedUsageWindows(
            selectedWindow: roles.weekly ?? primaryWindow ?? secondaryWindow,
            fiveHourWindow: roles.fiveHour,
            weeklyWindow: roles.weekly,
            defaultWindowName: "weekly_window"
        )
    }

    private func resolvePaidWindowRoles(
        primaryWindow: Window?,
        secondaryWindow: Window?
    ) -> (fiveHour: Window?, weekly: Window?) {
        switch (primaryWindow, secondaryWindow) {
        case (nil, nil):
            return (nil, nil)
        case let (window?, nil), let (nil, window?):
            return (window, window)
        case let (primary?, secondary?):
            if let roles = rolesFromWindowNames(primary: primary, secondary: secondary) {
                return roles
            }
            if let roles = rolesFromWindowDurations(primary: primary, secondary: secondary) {
                return roles
            }
            if let roles = rolesFromWindowResetTime(primary: primary, secondary: secondary) {
                return roles
            }
            // Fallback to legacy assumption if no signal is available.
            return (primary, secondary)
        }
    }

    private func rolesFromWindowNames(primary: Window, secondary: Window) -> (fiveHour: Window, weekly: Window)? {
        let primaryRole = inferRole(from: primary)
        let secondaryRole = inferRole(from: secondary)
        if primaryRole == .fiveHour && secondaryRole == .weekly {
            return (primary, secondary)
        }
        if primaryRole == .weekly && secondaryRole == .fiveHour {
            return (secondary, primary)
        }
        return nil
    }

    private func rolesFromWindowDurations(primary: Window, secondary: Window) -> (fiveHour: Window, weekly: Window)? {
        if let primaryDuration = primary.limitWindowSeconds,
           let secondaryDuration = secondary.limitWindowSeconds,
           primaryDuration != secondaryDuration {
            return primaryDuration < secondaryDuration ? (primary, secondary) : (secondary, primary)
        }
        if let primaryDuration = primary.resetAfterSeconds,
           let secondaryDuration = secondary.resetAfterSeconds,
           primaryDuration != secondaryDuration {
            return primaryDuration < secondaryDuration ? (primary, secondary) : (secondary, primary)
        }
        return nil
    }

    private func rolesFromWindowResetTime(primary: Window, secondary: Window) -> (fiveHour: Window, weekly: Window)? {
        guard let primaryReset = primary.resetAt,
              let secondaryReset = secondary.resetAt,
              primaryReset != secondaryReset else {
            return nil
        }
        return primaryReset < secondaryReset ? (primary, secondary) : (secondary, primary)
    }

    private func inferRole(from window: Window) -> PaidWindowRole? {
        guard let name = window.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else {
            return nil
        }
        if name.contains("week") {
            return .weekly
        }
        if name.contains("5h") || name.contains("five") || name.contains("hour") {
            return .fiveHour
        }
        return nil
    }

    private struct UsagePayload: Decodable {
        let usedUnits: Int?
        let quota: Int?
        let rateLimit: RateLimit?
        let accountID: String?
        let email: String?
        let planType: String?
        let credits: Credits?

        private enum CodingKeys: String, CodingKey {
            case usedUnits = "used_units"
            case quota
            case rateLimit = "rate_limit"
            case accountID = "account_id"
            case email
            case planType = "plan_type"
            case credits
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            primaryWindow = try container.decodeIfPresent(Window.self, forKeys: [
                "primary_window",
                "primaryWindow"
            ])
            secondaryWindow = try container.decodeIfPresent(Window.self, forKeys: [
                "secondary_window",
                "secondaryWindow",
                "secondary",
                "weekly_window",
                "week_window"
            ])
        }
    }

    private struct Credits: Decodable {
        let hasCredits: Bool?
        let unlimited: Bool?

        private enum CodingKeys: String, CodingKey {
            case hasCredits = "has_credits"
            case unlimited
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let name: String?
        let resetAt: Date?
        let limitWindowSeconds: Double?
        let resetAfterSeconds: Double?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            usedPercent = try container.decodeIfPresent(Double.self, forKeys: ["used_percent", "usedPercent"])
            name = try container.decodeIfPresent(String.self, forKeys: ["name", "window_name", "windowName"])
            resetAt = try container.decodeDateIfPresent(forKeys: ["reset_at", "resets_at", "resetAt", "resetsAt"])
            limitWindowSeconds = try container.decodeIfPresent(
                Double.self,
                forKeys: ["limit_window_seconds", "limitWindowSeconds"]
            )
            resetAfterSeconds = try container.decodeIfPresent(
                Double.self,
                forKeys: ["reset_after_seconds", "resetAfterSeconds"]
            )
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

    private func inferPaidStatus(from payload: UsagePayload) -> Bool {
        if let planType = payload.planType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !planType.isEmpty {
            return planType != "free"
        }
        if payload.credits?.hasCredits == true || payload.credits?.unlimited == true {
            return true
        }
        return false
    }

    private func percentValue(from rawValue: Double?) -> Int? {
        guard let rawValue else { return nil }
        return min(max(Int(rawValue.rounded()), 0), 100)
    }
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

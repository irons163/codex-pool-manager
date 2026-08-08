import Foundation

struct CodexClientHTTPError: Error, Equatable {
    let statusCode: Int
}

enum CodexSyncError: Error, Equatable, LocalizedError {
    case unauthorized
    case oauthLoginExpired
    case rateLimited
    case network
    case unknown

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return L10n.text("usage.sync.error.unauthorized")
        case .oauthLoginExpired:
            return L10n.text("usage.sync.error.oauth_login_expired")
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
    let planType: String?
    let rateLimitResetCreditsAvailableCount: Int?
    let rateLimitResetCreditExpiries: [Date?]?

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
        isPaid: Bool = false,
        planType: String? = nil,
        rateLimitResetCreditsAvailableCount: Int? = nil,
        rateLimitResetCreditExpiries: [Date?]? = nil
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
        self.planType = AgentAccount.normalizedPlanType(planType)
        self.rateLimitResetCreditsAvailableCount = rateLimitResetCreditsAvailableCount.map { max(0, $0) }
        self.rateLimitResetCreditExpiries = rateLimitResetCreditExpiries
    }
}

protocol CodexUsageClient {
    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage
}

struct CodexUsageSyncService<Client: CodexUsageClient> {
    let client: Client
    let maxRetries: Int
    let oauthRefreshClient: (any OAuthTokenRefreshing)?
    let oauthConfiguration: OAuthClientConfiguration?

    init(
        client: Client,
        maxRetries: Int = 0,
        oauthRefreshClient: (any OAuthTokenRefreshing)? = nil,
        oauthConfiguration: OAuthClientConfiguration? = nil
    ) {
        self.client = client
        self.maxRetries = max(0, maxRetries)
        self.oauthRefreshClient = oauthRefreshClient
        self.oauthConfiguration = oauthConfiguration
    }

    func sync(state: inout AccountPoolState, now: Date = .now) async throws {
        let missingTokenMessage = L10n.text("usage.sync.excluded.missing_token")
        let missingAccountIDMessage = L10n.text("usage.sync.excluded.missing_account_id")
        let previousSuccessfulSyncAt = state.lastUsageSyncAt
        for account in state.accounts {
            try Task.checkCancellation()

            guard account.supportsCodexUsageSync else {
                state.setUsageSyncExclusion(
                    for: account.id,
                    reason: AgentAccount.relayUsageSyncUnavailableReason,
                    now: now,
                    shouldEvaluate: false
                )
                continue
            }
            guard !account.apiToken.isEmpty else {
                state.setUsageSyncExclusion(for: account.id, reason: missingTokenMessage, now: now, shouldEvaluate: false)
                continue
            }

            let resolvedAccountID: String
            if let existingAccountID = OAuthIDTokenClaims.nonEmpty(account.chatGPTAccountID) {
                resolvedAccountID = existingAccountID
            } else if let recovered = recoverChatGPTAccountID(from: account) {
                state.updateAccount(
                    account.id,
                    email: recovered.email ?? account.email,
                    chatGPTAccountID: recovered.accountID,
                    now: now,
                    shouldEvaluate: false
                )
                resolvedAccountID = recovered.accountID
            } else {
                state.setUsageSyncExclusion(for: account.id, reason: missingAccountIDMessage, now: now, shouldEvaluate: false)
                continue
            }
            let chatGPTAccountID = resolvedAccountID

            do {
                let usage = try await fetchUsageWithRetry(
                    accessToken: account.apiToken,
                    accountID: chatGPTAccountID
                )
                state.replaceUsageSnapshot(
                    for: account.id,
                    quota: usage.quota,
                    usedUnits: usage.usedUnits,
                    usageWindowName: usage.usageWindowName,
                    usageWindowResetAt: usage.usageWindowResetAt,
                    primaryUsagePercent: usage.primaryUsagePercent,
                    primaryUsageResetAt: usage.primaryUsageResetAt,
                    secondaryUsagePercent: usage.secondaryUsagePercent,
                    secondaryUsageResetAt: usage.secondaryUsageResetAt,
                    isPaid: usage.isPaid,
                    planType: usage.planType,
                    now: now,
                    shouldEvaluate: false
                )
                state.updateRateLimitResetCredits(
                    for: account.id,
                    availableCount: usage.rateLimitResetCreditsAvailableCount,
                    apiExpiries: usage.rateLimitResetCreditExpiries,
                    previousSuccessfulSyncAt: previousSuccessfulSyncAt,
                    now: now
                )
                state.setUsageSyncExclusion(for: account.id, reason: nil, now: now, shouldEvaluate: false)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let mapped = mapSyncError(error)
                if mapped == .unauthorized {
                    do {
                        if let refreshed = try await refreshOAuthTokenAndFetchUsageIfPossible(
                            account: account,
                            chatGPTAccountID: chatGPTAccountID,
                            now: now
                        ) {
                            state.updateAccount(
                                account.id,
                                apiToken: refreshed.tokens.accessToken,
                                email: refreshed.usage.accountEmail,
                                chatGPTAccountID: refreshed.usage.accountID ?? chatGPTAccountID,
                                oauthRefreshToken: refreshed.refreshToken,
                                oauthIDToken: refreshed.idToken,
                                oauthLastRefreshAt: now,
                                now: now,
                                shouldEvaluate: false
                            )
                            state.replaceUsageSnapshot(
                                for: account.id,
                                quota: refreshed.usage.quota,
                                usedUnits: refreshed.usage.usedUnits,
                                usageWindowName: refreshed.usage.usageWindowName,
                                usageWindowResetAt: refreshed.usage.usageWindowResetAt,
                                primaryUsagePercent: refreshed.usage.primaryUsagePercent,
                                primaryUsageResetAt: refreshed.usage.primaryUsageResetAt,
                                secondaryUsagePercent: refreshed.usage.secondaryUsagePercent,
                                secondaryUsageResetAt: refreshed.usage.secondaryUsageResetAt,
                                isPaid: refreshed.usage.isPaid,
                                planType: refreshed.usage.planType,
                                now: now,
                                shouldEvaluate: false
                            )
                            state.updateRateLimitResetCredits(
                                for: account.id,
                                availableCount: refreshed.usage.rateLimitResetCreditsAvailableCount,
                                apiExpiries: refreshed.usage.rateLimitResetCreditExpiries,
                                previousSuccessfulSyncAt: previousSuccessfulSyncAt,
                                now: now
                            )
                            state.setUsageSyncExclusion(for: account.id, reason: nil, now: now, shouldEvaluate: false)
                            continue
                        }
                        if shouldReportOAuthLoginExpired(for: account) {
                            state.setUsageSyncExclusion(
                                for: account.id,
                                reason: CodexSyncError.oauthLoginExpired.localizedDescription,
                                now: now,
                                shouldEvaluate: false
                            )
                            continue
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let reason = shouldReportOAuthLoginExpired(for: account)
                            ? CodexSyncError.oauthLoginExpired.localizedDescription
                            : mapSyncError(error).localizedDescription
                        state.setUsageSyncExclusion(
                            for: account.id,
                            reason: reason,
                            now: now,
                            shouldEvaluate: false
                        )
                        continue
                    }
                }
                state.setUsageSyncExclusion(
                    for: account.id,
                    reason: mapped.localizedDescription,
                    now: now,
                    shouldEvaluate: false
                )
            }
        }

        try Task.checkCancellation()
        state.evaluate(now: now)
        state.markUsageSynced(at: now)
    }

    private func recoverChatGPTAccountID(
        from account: AgentAccount
    ) -> (accountID: String, email: String?)? {
        let claims = OAuthIDTokenClaimsParser.merge(
            OAuthIDTokenClaimsParser.parse(account.oauthIDToken),
            OAuthIDTokenClaimsParser.parse(account.apiToken)
        )
        guard let accountID = claims?.resolvedChatGPTAccountID else {
            return nil
        }
        return (accountID, claims?.email)
    }

    private func fetchUsageWithRetry(accessToken: String, accountID: String) async throws -> CodexUsage {
        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                return try await client.fetchUsage(accessToken: accessToken, accountID: accountID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if attempt >= maxRetries {
                    throw mapSyncError(error)
                }
                attempt += 1
            }
        }
    }

    private func refreshOAuthTokenAndFetchUsageIfPossible(
        account: AgentAccount,
        chatGPTAccountID: String,
        now: Date
    ) async throws -> (tokens: OAuthTokens, refreshToken: String?, idToken: String?, usage: CodexUsage)? {
        guard account.supportsCodexUsageSync,
              let oauthRefreshClient,
              let oauthConfiguration
        else {
            return nil
        }
        let refreshToken = account.oauthRefreshToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !refreshToken.isEmpty else { return nil }

        let refreshedTokens: OAuthTokens
        do {
            refreshedTokens = try await oauthRefreshClient.refreshTokens(
                refreshToken: refreshToken,
                configuration: oauthConfiguration
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CodexSyncError.unauthorized
        }

        let freshAccessToken = refreshedTokens.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !freshAccessToken.isEmpty else {
            throw CodexSyncError.unauthorized
        }

        let usage = try await fetchUsageWithRetry(
            accessToken: freshAccessToken,
            accountID: chatGPTAccountID
        )
        let nextRefreshToken = refreshedTokens.refreshToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nextIDToken = refreshedTokens.idToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            tokens: OAuthTokens(
                accessToken: freshAccessToken,
                refreshToken: nextRefreshToken?.isEmpty == false ? nextRefreshToken : account.oauthRefreshToken,
                idToken: nextIDToken?.isEmpty == false ? nextIDToken : account.oauthIDToken
            ),
            refreshToken: nextRefreshToken?.isEmpty == false ? nextRefreshToken : account.oauthRefreshToken,
            idToken: nextIDToken?.isEmpty == false ? nextIDToken : account.oauthIDToken,
            usage: usage
        )
    }

    private func mapSyncError(_ error: Error) -> CodexSyncError {
        if let syncError = error as? CodexSyncError {
            return syncError
        }
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

    private func shouldReportOAuthLoginExpired(for account: AgentAccount) -> Bool {
        account.supportsCodexUsageSync
            && oauthRefreshClient != nil
            && oauthConfiguration != nil
    }
}

struct OpenAICodexUsageClient: CodexUsageClient {
    var endpoint: URL
    var resetCreditsEndpoint: URL
    var session: URLSession = .shared
    var onRawResponse: ((String) -> Void)?

    init(
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        resetCreditsEndpoint: URL? = nil,
        session: URLSession = .shared,
        onRawResponse: ((String) -> Void)? = nil
    ) {
        self.endpoint = endpoint
        self.resetCreditsEndpoint = resetCreditsEndpoint ?? Self.makeResetCreditsEndpoint(from: endpoint)
        self.session = session
        self.onRawResponse = onRawResponse
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        let request = makeRequest(url: endpoint, accessToken: accessToken, accountID: accountID)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CodexClientHTTPError(statusCode: statusCode)
        }
        if let raw = String(data: data, encoding: .utf8) {
            onRawResponse?(raw)
        }

        let payload = try JSONDecoder().decode(UsagePayload.self, from: data)
        let resetCreditDetails = try await fetchResetCreditDetails(
            accessToken: accessToken,
            accountID: accountID,
            summaryAvailableCount: payload.rateLimitResetCredits?.availableCount
        )
        let resetCreditsAvailableCount = resetCreditDetails?.availableCount
            ?? payload.rateLimitResetCredits?.availableCount
        let isPaid = inferPaidStatus(from: payload)
        let planType = AgentAccount.normalizedPlanType(payload.planType)
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
        let responseAccountID = payload.accountID
        let accountEmail = payload.email
        if let usedUnits = payload.usedUnits, let quota = payload.quota {
            return CodexUsage(
                usedUnits: usedUnits,
                quota: quota,
                usageWindowName: usageWindowName,
                usageWindowResetAt: usageWindowResetAt,
                accountID: responseAccountID,
                accountEmail: accountEmail,
                primaryUsagePercent: primaryUsagePercent,
                primaryUsageResetAt: resolvedWindows.fiveHourWindow?.resetAt,
                secondaryUsagePercent: secondaryUsagePercent,
                secondaryUsageResetAt: resolvedWindows.weeklyWindow?.resetAt,
                isPaid: isPaid,
                planType: planType,
                rateLimitResetCreditsAvailableCount: resetCreditsAvailableCount,
                rateLimitResetCreditExpiries: resetCreditDetails?.expiries
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
                accountID: responseAccountID,
                accountEmail: accountEmail,
                primaryUsagePercent: primaryUsagePercent,
                primaryUsageResetAt: resolvedWindows.fiveHourWindow?.resetAt,
                secondaryUsagePercent: secondaryUsagePercent,
                secondaryUsageResetAt: resolvedWindows.weeklyWindow?.resetAt,
                isPaid: isPaid,
                planType: planType,
                rateLimitResetCreditsAvailableCount: resetCreditsAvailableCount,
                rateLimitResetCreditExpiries: resetCreditDetails?.expiries
            )
        }
        throw CodexSyncError.unknown
    }

    private enum RequestPolicy {
        static let timeout: TimeInterval = 30
    }

    private struct ResetCreditDetailsResult {
        let availableCount: Int
        let expiries: [Date?]
    }

    private func makeRequest(url: URL, accessToken: String, accountID: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = RequestPolicy.timeout
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func fetchResetCreditDetails(
        accessToken: String,
        accountID: String,
        summaryAvailableCount: Int?
    ) async throws -> ResetCreditDetailsResult? {
        guard let summaryAvailableCount, summaryAvailableCount > 0 else { return nil }

        do {
            let request = makeRequest(
                url: resetCreditsEndpoint,
                accessToken: accessToken,
                accountID: accountID
            )
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }

            let payload = try JSONDecoder().decode(RateLimitResetCreditsDetails.self, from: data)
            let availableCredits = payload.credits.filter { credit in
                credit.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "available"
            }
            return ResetCreditDetailsResult(
                availableCount: max(0, payload.availableCount ?? summaryAvailableCount),
                expiries: availableCredits.map(\.expiresAt)
            )
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    private static func makeResetCreditsEndpoint(from usageEndpoint: URL) -> URL {
        let fallback = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
        guard var components = URLComponents(url: usageEndpoint, resolvingAgainstBaseURL: false) else {
            return fallback
        }

        let path = components.path
        if path.hasSuffix("/wham/usage") {
            components.path = path.replacingOccurrences(
                of: "/wham/usage",
                with: "/wham/rate-limit-reset-credits"
            )
        } else if path.hasSuffix("/api/codex/usage") {
            components.path = path.replacingOccurrences(
                of: "/api/codex/usage",
                with: "/api/codex/rate-limit-reset-credits"
            )
        } else {
            return fallback
        }
        components.query = nil
        components.fragment = nil
        return components.url ?? fallback
    }

    private struct ResolvedUsageWindows {
        let selectedWindow: Window?
        let fiveHourWindow: Window?
        let weeklyWindow: Window?
        let defaultWindowName: String
    }

    private enum UsageWindowRole {
        case fiveHour
        case weekly
    }

    private func resolveUsageWindows(
        isPaid: Bool,
        primaryWindow: Window?,
        secondaryWindow: Window?
    ) -> ResolvedUsageWindows {
        let roles = resolveWindowRoles(primaryWindow: primaryWindow, secondaryWindow: secondaryWindow)
        let defaultWindowName: String
        if roles.weekly != nil {
            defaultWindowName = "weekly_window"
        } else if roles.fiveHour != nil {
            defaultWindowName = "five_hour_window"
        } else {
            defaultWindowName = isPaid ? "weekly_window" : "primary_window"
        }

        return ResolvedUsageWindows(
            // Prefer the longer window as the account's primary usage value.
            // Some plans expose only the weekly window in primary_window.
            selectedWindow: roles.weekly ?? roles.fiveHour,
            fiveHourWindow: roles.fiveHour,
            weeklyWindow: roles.weekly,
            defaultWindowName: defaultWindowName
        )
    }

    private func resolveWindowRoles(
        primaryWindow: Window?,
        secondaryWindow: Window?
    ) -> (fiveHour: Window?, weekly: Window?) {
        switch (primaryWindow, secondaryWindow) {
        case (nil, nil):
            return (nil, nil)
        case let (window?, nil):
            return rolesForSingleWindow(window, fallback: .fiveHour)
        case let (nil, window?):
            return rolesForSingleWindow(window, fallback: .weekly)
        case let (primary?, secondary?):
            if let roles = rolesFromWindowMetadata(primary: primary, secondary: secondary) {
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

    private func rolesForSingleWindow(
        _ window: Window,
        fallback: UsageWindowRole
    ) -> (fiveHour: Window?, weekly: Window?) {
        switch inferRole(from: window) ?? fallback {
        case .fiveHour:
            return (window, nil)
        case .weekly:
            return (nil, window)
        }
    }

    private func rolesFromWindowMetadata(primary: Window, secondary: Window) -> (fiveHour: Window, weekly: Window)? {
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
            if let primaryRole = role(forLimitWindowSeconds: primaryDuration),
               let secondaryRole = role(forLimitWindowSeconds: secondaryDuration),
               primaryRole != secondaryRole {
                return primaryRole == .fiveHour
                    ? (primary, secondary)
                    : (secondary, primary)
            }
        }
        if primary.limitWindowSeconds == nil,
           secondary.limitWindowSeconds == nil,
           let primaryDuration = primary.resetAfterSeconds,
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

    private func inferRole(from window: Window) -> UsageWindowRole? {
        if let role = window.limitWindowSeconds.flatMap(role(forLimitWindowSeconds:)) {
            return role
        }

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

    private func role(forLimitWindowSeconds seconds: Double) -> UsageWindowRole? {
        // The API currently uses 18,000 seconds for 5h and 604,800 seconds
        // for weekly. Keep a tolerance band so unknown future durations are
        // not silently presented as one of those two windows.
        if seconds <= 6 * 60 * 60 {
            return .fiveHour
        }
        if seconds >= 6 * 24 * 60 * 60 {
            return .weekly
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
        let rateLimitResetCredits: RateLimitResetCredits?

        private enum CodingKeys: String, CodingKey {
            case usedUnits = "used_units"
            case quota
            case rateLimit = "rate_limit"
            case accountID = "account_id"
            case email
            case planType = "plan_type"
            case credits
            case rateLimitResetCredits = "rate_limit_reset_credits"
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

    private struct RateLimitResetCredits: Decodable {
        let availableCount: Int?

        private enum CodingKeys: String, CodingKey {
            case availableCount = "available_count"
        }
    }

    private struct RateLimitResetCreditsDetails: Decodable {
        let credits: [RateLimitResetCreditDetails]
        let availableCount: Int?

        private enum CodingKeys: String, CodingKey {
            case credits
            case availableCount = "available_count"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            credits = try container.decodeIfPresent([RateLimitResetCreditDetails].self, forKey: .credits) ?? []
            availableCount = try container.decodeIfPresent(Int.self, forKey: .availableCount)
        }
    }

    private struct RateLimitResetCreditDetails: Decodable {
        let status: String
        let expiresAt: Date?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            status = try container.decodeIfPresent(String.self, forKeys: ["status"]) ?? ""
            expiresAt = try container.decodeDateIfPresent(forKeys: ["expires_at", "expiresAt"])
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

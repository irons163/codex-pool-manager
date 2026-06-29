# Menu Bar Reset Credit Expiry Estimate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the duplicated current-account card and show each eligible menu bar account's banked reset count with a compact expiry estimate based on the previous successful sync plus 30 days.

**Architecture:** Decode `rate_limit_reset_credits.available_count` from the existing `/wham/usage` response, persist the count and one estimated earliest expiry on `AgentAccount`, and update those values only after successful account usage responses. Format localized badge/detail text in `MenuBarDashboardPresenter`; keep `MenuBarDashboardView` responsible only for the compact button, explanatory popover, and removal of the duplicated active-account section.

**Tech Stack:** Swift, Foundation `Codable`, SwiftUI, Swift Testing, Xcode/macOS test targets.

---

## File Map

- `Infrastructure/Usage/CodexUsageSyncService.swift`: decode the server count and apply the first-observation estimate during successful syncs.
- `Domain/Pool/AgentPool.swift`: persist reset-credit state, calculate/clear the estimated expiry, and preserve it through copies and merges.
- `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`: turn model values into compact and detailed localized strings.
- `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`: remove the active-account card and add the clickable reset-credit badge.
- `CodexPoolManager/*.lproj/Localizable.strings`: localize the badge, detail popover, and accessibility label.
- `CodexPoolManagerTests/CodexPoolManagerTests.swift`: cover decoding, estimation, clearing, persistence, and failed-sync behavior.
- `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`: cover localized presentation.
- `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`: guard the compact two-line layout and removal of the duplicate section.

### Task 1: Decode banked reset counts from the usage response

**Files:**
- Modify: `Infrastructure/Usage/CodexUsageSyncService.swift`
- Test: `CodexPoolManagerTests/CodexPoolManagerTests.swift`

- [ ] **Step 1: Write failing decoder tests**

Add these tests beside the existing `openAICodexUsageClientParsesRateLimitPayloadAndCapturesRawJSON()` test:

```swift
@Test
func openAICodexUsageClientParsesAvailableResetCredits() async throws {
    let responseJSON = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": { "used_percent": 12 }
      },
      "rate_limit_reset_credits": {
        "available_count": 2
      }
    }
    """
    let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=reset-credits"))
    let session = makeMockedURLSession(
        endpoint: endpoint,
        statusCode: 200,
        data: Data(responseJSON.utf8)
    )

    let client = OpenAICodexUsageClient(endpoint: endpoint, session: session)
    let usage = try await client.fetchUsage(accessToken: "token", accountID: "acct")

    #expect(usage.rateLimitResetCreditsAvailableCount == 2)
}

@Test
func openAICodexUsageClientClampsNegativeResetCreditsToZero() async throws {
    let responseJSON = """
    {
      "rate_limit": {
        "primary_window": { "used_percent": 12 }
      },
      "rate_limit_reset_credits": {
        "available_count": -3
      }
    }
    """
    let endpoint = try #require(URL(string: "https://chatgpt.com/backend-api/wham/usage?case=negative-reset-credits"))
    let session = makeMockedURLSession(
        endpoint: endpoint,
        statusCode: 200,
        data: Data(responseJSON.utf8)
    )

    let client = OpenAICodexUsageClient(endpoint: endpoint, session: session)
    let usage = try await client.fetchUsage(accessToken: "token", accountID: "acct")

    #expect(usage.rateLimitResetCreditsAvailableCount == 0)
}
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/openAICodexUsageClientParsesAvailableResetCredits -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/openAICodexUsageClientClampsNegativeResetCreditsToZero
```

Expected: compilation FAIL because `CodexUsage` has no `rateLimitResetCreditsAvailableCount` property.

- [ ] **Step 3: Add the payload and domain fields**

Add this stored property to `CodexUsage` after `planType`:

```swift
let rateLimitResetCreditsAvailableCount: Int?
```

Add this final initializer parameter after `planType`:

```swift
rateLimitResetCreditsAvailableCount: Int? = nil
```

Add this assignment after the existing `planType` assignment to normalize at the boundary:

```swift
self.rateLimitResetCreditsAvailableCount = rateLimitResetCreditsAvailableCount.map { max(0, $0) }
```

Extend `UsagePayload` and its coding keys:

```swift
let rateLimitResetCredits: RateLimitResetCredits?

case rateLimitResetCredits = "rate_limit_reset_credits"
```

Add the nested payload type:

```swift
private struct RateLimitResetCredits: Decodable {
    let availableCount: Int?

    private enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
    }
}
```

In both `CodexUsage(...)` return paths in `fetchUsage`, pass:

```swift
rateLimitResetCreditsAvailableCount: payload.rateLimitResetCredits?.availableCount
```

- [ ] **Step 4: Run the decoder tests and verify GREEN**

Run the command from Step 2.

Expected: both tests PASS.

- [ ] **Step 5: Commit the decoder change**

```bash
git add Infrastructure/Usage/CodexUsageSyncService.swift CodexPoolManagerTests/CodexPoolManagerTests.swift
git commit -m "feat(usage): decode reset credit count"
```

### Task 2: Persist and estimate reset-credit expiry

**Files:**
- Modify: `Domain/Pool/AgentPool.swift`
- Modify: `Infrastructure/Usage/CodexUsageSyncService.swift`
- Test: `CodexPoolManagerTests/CodexPoolManagerTests.swift`

- [ ] **Step 1: Write failing estimation and compatibility tests**

Add these focused tests to `CodexPoolManagerTests`:

```swift
@Test
func codexSyncEstimatesResetCreditExpiryFromPreviousSuccessfulSync() async throws {
    let accountID = UUID()
    let previousSync = Date(timeIntervalSince1970: 1_000)
    let currentSync = Date(timeIntervalSince1970: 2_000)
    var state = AccountPoolState(
        accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 0, quota: 100, apiToken: "token")],
        mode: .manual
    )
    state.updateAccount(accountID, chatGPTAccountID: "acct")
    state.markUsageSynced(at: previousSync)
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [
        "token": CodexUsage(
            usedUnits: 10,
            quota: 100,
            rateLimitResetCreditsAvailableCount: 2
        )
    ]))

    try await sync.sync(state: &state, now: currentSync)

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == 2)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == previousSync.addingTimeInterval(30 * 24 * 60 * 60))
}

@Test
func codexSyncUsesCurrentTimeWhenNoPreviousSuccessfulSyncExists() async throws {
    let accountID = UUID()
    let currentSync = Date(timeIntervalSince1970: 2_000)
    var state = AccountPoolState(
        accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 0, quota: 100, apiToken: "token")],
        mode: .manual
    )
    state.updateAccount(accountID, chatGPTAccountID: "acct")
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [
        "token": CodexUsage(usedUnits: 10, quota: 100, rateLimitResetCreditsAvailableCount: 1)
    ]))

    try await sync.sync(state: &state, now: currentSync)

    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == currentSync.addingTimeInterval(30 * 24 * 60 * 60))
}

@Test
func codexSyncRetainsFirstResetCreditEstimateWhileCountRemainsPositive() async throws {
    let accountID = UUID()
    let firstEstimate = Date(timeIntervalSince1970: 500_000)
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 0,
                quota: 100,
                apiToken: "token",
                chatGPTAccountID: "acct",
                rateLimitResetCreditsAvailableCount: 1,
                rateLimitResetCreditsEstimatedExpiresAt: firstEstimate
            )
        ],
        mode: .manual
    )
    state.markUsageSynced(at: Date(timeIntervalSince1970: 10_000))
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [
        "token": CodexUsage(usedUnits: 10, quota: 100, rateLimitResetCreditsAvailableCount: 3)
    ]))

    try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 20_000))

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == 3)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == firstEstimate)
}

@Test
func codexSyncClearsResetCreditEstimateWhenCountBecomesZero() async throws {
    let accountID = UUID()
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 0,
                quota: 100,
                apiToken: "token",
                chatGPTAccountID: "acct",
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: Date(timeIntervalSince1970: 500_000)
            )
        ],
        mode: .manual
    )
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [
        "token": CodexUsage(usedUnits: 10, quota: 100, rateLimitResetCreditsAvailableCount: 0)
    ]))

    try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 20_000))

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == 0)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == nil)
}

@Test
func agentAccountDecodesMissingResetCreditFieldsAsUnavailable() throws {
    let json = """
    {
      "id": "00000000-0000-0000-0000-0000000000A1",
      "name": "legacy",
      "usedUnits": 0,
      "quota": 100
    }
    """

    let account = try JSONDecoder().decode(AgentAccount.self, from: Data(json.utf8))

    #expect(account.rateLimitResetCreditsAvailableCount == nil)
    #expect(account.rateLimitResetCreditsEstimatedExpiresAt == nil)
}
```

Add these failure, unavailable-field, timestamp-clamp, and copy-path tests in the same suite:

```swift
@Test
func codexSyncPreservesResetCreditEstimateWhenClientFails() async {
    let accountID = UUID()
    let estimate = Date(timeIntervalSince1970: 500_000)
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 10,
                quota: 100,
                apiToken: "bad-token",
                chatGPTAccountID: "acct",
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: estimate
            )
        ],
        mode: .manual
    )
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [:], shouldThrow: true))

    try? await sync.sync(state: &state, now: Date(timeIntervalSince1970: 20_000))

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == 2)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == estimate)
}

@Test
func codexSyncClearsResetCreditMetadataWhenFieldIsUnavailable() async throws {
    let accountID = UUID()
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 0,
                quota: 100,
                apiToken: "token",
                chatGPTAccountID: "acct",
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: Date(timeIntervalSince1970: 500_000)
            )
        ],
        mode: .manual
    )
    let sync = CodexUsageSyncService(client: MockCodexUsageClient(responseByToken: [
        "token": CodexUsage(usedUnits: 10, quota: 100)
    ]))

    try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 20_000))

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == nil)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == nil)
}

@Test
func resetCreditEstimateClampsFuturePreviousSyncToCurrentTime() {
    let accountID = UUID()
    let now = Date(timeIntervalSince1970: 20_000)
    var state = AccountPoolState(
        accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 0, quota: 100)],
        mode: .manual
    )

    state.updateRateLimitResetCredits(
        for: accountID,
        availableCount: 1,
        previousSuccessfulSyncAt: Date(timeIntervalSince1970: 30_000),
        now: now
    )

    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == now.addingTimeInterval(30 * 24 * 60 * 60))
}

@Test
func agentAccountRedactionPreservesResetCreditMetadata() {
    let estimate = Date(timeIntervalSince1970: 500_000)
    let account = AgentAccount(
        id: UUID(),
        name: "A",
        usedUnits: 0,
        quota: 100,
        apiToken: "secret",
        rateLimitResetCreditsAvailableCount: 2,
        rateLimitResetCreditsEstimatedExpiresAt: estimate
    )

    let redacted = account.redactingAPIToken()

    #expect(redacted.rateLimitResetCreditsAvailableCount == 2)
    #expect(redacted.rateLimitResetCreditsEstimatedExpiresAt == estimate)
}

@Test
func duplicateAccountPreservesResetCreditMetadata() throws {
    let accountID = UUID()
    let estimate = Date(timeIntervalSince1970: 500_000)
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 0,
                quota: 100,
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: estimate
            )
        ],
        mode: .manual
    )

    let duplicateID = try #require(state.duplicateAccount(accountID))
    let duplicate = try #require(state.accounts.first(where: { $0.id == duplicateID }))

    #expect(duplicate.rateLimitResetCreditsAvailableCount == 2)
    #expect(duplicate.rateLimitResetCreditsEstimatedExpiresAt == estimate)
}

@Test
func mergeUsageSyncStateCopiesResetCreditMetadata() {
    let accountID = UUID()
    let estimate = Date(timeIntervalSince1970: 500_000)
    var state = AccountPoolState(
        accounts: [AgentAccount(id: accountID, name: "A", usedUnits: 0, quota: 100)],
        mode: .manual
    )
    let syncedState = AccountPoolState(
        accounts: [
            AgentAccount(
                id: accountID,
                name: "A",
                usedUnits: 10,
                quota: 100,
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: estimate
            )
        ],
        mode: .manual
    )

    state.mergeUsageSyncState(from: syncedState)

    #expect(state.accounts[0].rateLimitResetCreditsAvailableCount == 2)
    #expect(state.accounts[0].rateLimitResetCreditsEstimatedExpiresAt == estimate)
}
```

- [ ] **Step 2: Run the tests and verify RED**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests
```

Expected: compilation FAIL because `AgentAccount` has no reset-credit properties or initializer parameters.

- [ ] **Step 3: Add backward-compatible account persistence**

In `AgentAccount`, add:

```swift
var rateLimitResetCreditsAvailableCount: Int?
var rateLimitResetCreditsEstimatedExpiresAt: Date?
```

Add matching optional initializer parameters after `planType`:

```swift
rateLimitResetCreditsAvailableCount: Int? = nil,
rateLimitResetCreditsEstimatedExpiresAt: Date? = nil,
```

Normalize them in the initializer:

```swift
let normalizedResetCount = rateLimitResetCreditsAvailableCount.map { max(0, $0) }
self.rateLimitResetCreditsAvailableCount = normalizedResetCount
self.rateLimitResetCreditsEstimatedExpiresAt = (normalizedResetCount ?? 0) > 0
    ? rateLimitResetCreditsEstimatedExpiresAt
    : nil
```

Decode them with safe defaults:

```swift
let decodedResetCount = try container.decodeIfPresent(Int.self, forKey: .rateLimitResetCreditsAvailableCount)
rateLimitResetCreditsAvailableCount = decodedResetCount.map { max(0, $0) }
rateLimitResetCreditsEstimatedExpiresAt = (rateLimitResetCreditsAvailableCount ?? 0) > 0
    ? try container.decodeIfPresent(Date.self, forKey: .rateLimitResetCreditsEstimatedExpiresAt)
    : nil
```

In both `redactingAPIToken()` and `duplicateAccount(...)`, pass these arguments immediately after `planType`:

```swift
rateLimitResetCreditsAvailableCount: rateLimitResetCreditsAvailableCount,
rateLimitResetCreditsEstimatedExpiresAt: rateLimitResetCreditsEstimatedExpiresAt,
```

Inside `mergeUsageSyncState(from:)`, copy both values after `planType`:

```swift
accounts[index].rateLimitResetCreditsAvailableCount = synced.rateLimitResetCreditsAvailableCount
accounts[index].rateLimitResetCreditsEstimatedExpiresAt = synced.rateLimitResetCreditsEstimatedExpiresAt
```

- [ ] **Step 4: Add the state transition and wire successful syncs**

Add this focused mutation to `AccountPoolState`:

```swift
mutating func updateRateLimitResetCredits(
    for accountID: UUID,
    availableCount: Int?,
    previousSuccessfulSyncAt: Date?,
    now: Date = .now
) {
    guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
    guard let availableCount else {
        accounts[index].rateLimitResetCreditsAvailableCount = nil
        accounts[index].rateLimitResetCreditsEstimatedExpiresAt = nil
        return
    }

    let normalizedCount = max(0, availableCount)
    let hadPositiveCount = (accounts[index].rateLimitResetCreditsAvailableCount ?? 0) > 0
    accounts[index].rateLimitResetCreditsAvailableCount = normalizedCount

    guard normalizedCount > 0 else {
        accounts[index].rateLimitResetCreditsEstimatedExpiresAt = nil
        return
    }
    guard !hadPositiveCount || accounts[index].rateLimitResetCreditsEstimatedExpiresAt == nil else {
        return
    }

    let baseline = min(previousSuccessfulSyncAt ?? now, now)
    accounts[index].rateLimitResetCreditsEstimatedExpiresAt = baseline.addingTimeInterval(30 * 24 * 60 * 60)
}
```

At the start of `CodexUsageSyncService.sync`, before the account loop, capture:

```swift
let previousSuccessfulSyncAt = state.lastUsageSyncAt
```

After each successful `state.updateAccount(...)` call, including the refreshed-OAuth success path, call:

```swift
state.updateRateLimitResetCredits(
    for: account.id,
    availableCount: usage.rateLimitResetCreditsAvailableCount,
    previousSuccessfulSyncAt: previousSuccessfulSyncAt,
    now: now
)
```

Use `refreshed.usage.rateLimitResetCreditsAvailableCount` in the refreshed-OAuth branch.

- [ ] **Step 5: Run the domain tests and verify GREEN**

Run the command from Step 2.

Expected: the complete `CodexPoolManagerTests` Swift Testing suite PASSes, including all new reset-credit tests.

- [ ] **Step 6: Commit persistence and estimation**

```bash
git add Domain/Pool/AgentPool.swift Infrastructure/Usage/CodexUsageSyncService.swift CodexPoolManagerTests/CodexPoolManagerTests.swift
git commit -m "feat(usage): estimate reset credit expiry"
```

### Task 3: Format localized reset-credit presentation

**Files:**
- Modify: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
- Modify: `CodexPoolManager/en.lproj/Localizable.strings`
- Modify: `CodexPoolManager/zh-Hant.lproj/Localizable.strings`
- Modify: `CodexPoolManager/zh-Hans.lproj/Localizable.strings`
- Modify: `CodexPoolManager/fr.lproj/Localizable.strings`
- Modify: `CodexPoolManager/es.lproj/Localizable.strings`
- Modify: `CodexPoolManager/ja.lproj/Localizable.strings`
- Modify: `CodexPoolManager/ko.lproj/Localizable.strings`
- Test: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`

- [ ] **Step 1: Write the failing presenter test**

Add these parameters to `makeAccount(...)` immediately before `usageSyncError`:

```swift
rateLimitResetCreditsAvailableCount: Int? = nil,
rateLimitResetCreditsEstimatedExpiresAt: Date? = nil,
```

Forward them in the helper's `AgentAccount(...)` call immediately after `planType`:

```swift
rateLimitResetCreditsAvailableCount: rateLimitResetCreditsAvailableCount,
rateLimitResetCreditsEstimatedExpiresAt: rateLimitResetCreditsEstimatedExpiresAt,
```

Then add:

```swift
@Test
func presenterFormatsEstimatedResetCreditExpiry() throws {
    try withMenuBarLanguageOverride("zh-Hant") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let expiry = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 29,
            hour: 23,
            minute: 15
        )))
        let accountID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let state = AccountPoolState(
            accounts: [
                makeAccount(
                    id: accountID,
                    planType: "pro",
                    rateLimitResetCreditsAvailableCount: 2,
                    rateLimitResetCreditsEstimatedExpiresAt: expiry
                )
            ],
            mode: .manual
        )

        let row = try #require(MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: expiry
        ).accountRows.first)

        #expect(row.resetCreditBadgeText?.contains("2") == true)
        #expect(row.resetCreditBadgeText?.contains("約") == true)
        #expect(row.resetCreditBadgeText?.contains("7/29") == true)
        #expect(row.resetCreditDetailText?.contains("30 天") == true)
        #expect(row.resetCreditAccessibilityLabel?.contains("2") == true)
    }
}

@Test
func presenterHidesResetCreditBadgeForRelayAccounts() throws {
    let expiry = Date(timeIntervalSince1970: 1_800_000_000)
    let relayID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let state = AccountPoolState(
        accounts: [
            makeAccount(
                id: relayID,
                name: "relay",
                isPaid: false,
                rateLimitResetCreditsAvailableCount: 2,
                rateLimitResetCreditsEstimatedExpiresAt: expiry,
                credentialType: .relayAPIKey
            )
        ],
        mode: .manual
    )

    let row = try #require(MenuBarDashboardPresenter.makeSnapshot(
        from: state,
        isSyncing: false,
        lastSyncError: nil,
        now: expiry
    ).accountRows.first)

    #expect(row.resetCreditBadgeText == nil)
    #expect(row.resetCreditDetailText == nil)
}
```

- [ ] **Step 2: Run the presenter test and verify RED**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests
```

Expected: compilation FAIL because `MenuBarAccountRow` has no reset-credit presentation fields.

- [ ] **Step 3: Add presenter fields and formatting**

Add to `MenuBarAccountRow`:

```swift
let resetCreditBadgeText: String?
let resetCreditDetailText: String?
let resetCreditAccessibilityLabel: String?
```

Add a private presentation value:

```swift
private struct ResetCreditPresentation {
    let badgeText: String
    let detailText: String
    let accessibilityLabel: String
}
```

At the start of `makeAccountRow`, compute:

```swift
let resetCredit = resetCreditPresentation(for: account)
```

Pass these values in `MenuBarAccountRow(...)` immediately after `planBadgeText`:

```swift
resetCreditBadgeText: resetCredit?.badgeText,
resetCreditDetailText: resetCredit?.detailText,
resetCreditAccessibilityLabel: resetCredit?.accessibilityLabel,
```

Add this formatter helper:

```swift
private static func resetCreditPresentation(for account: AgentAccount) -> ResetCreditPresentation? {
    guard account.supportsCodexUsageSync,
          let count = account.rateLimitResetCreditsAvailableCount,
          count > 0,
          let expiry = account.rateLimitResetCreditsEstimatedExpiresAt
    else {
        return nil
    }

    let compactFormatter = DateFormatter()
    compactFormatter.locale = L10n.locale()
    compactFormatter.dateFormat = "M/d"
    let fullFormatter = DateFormatter()
    fullFormatter.locale = L10n.locale()
    fullFormatter.dateFormat = "yyyy/M/d HH:mm"
    let compactDate = compactFormatter.string(from: expiry)
    let fullDate = fullFormatter.string(from: expiry)

    return ResetCreditPresentation(
        badgeText: L10n.text("menu_bar.reset_credit.badge_format", count, compactDate),
        detailText: L10n.text("menu_bar.reset_credit.detail_format", count, fullDate),
        accessibilityLabel: L10n.text("menu_bar.reset_credit.accessibility_format", count, fullDate)
    )
}
```

- [ ] **Step 4: Add every supported localization**

Append these exact lines to each file.

`CodexPoolManager/en.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d · est. %@";
"menu_bar.reset_credit.detail.title" = "Banked resets";
"menu_bar.reset_credit.detail_format" = "%d resets available\nEstimated expiry: %@\nEstimated from the previous successful sync plus 30 days; the actual expiry may differ.";
"menu_bar.reset_credit.accessibility_format" = "%d banked resets, estimated expiry %@";
```

`CodexPoolManager/zh-Hant.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d 次 · 約 %@ 到期";
"menu_bar.reset_credit.detail.title" = "可用重置額度";
"menu_bar.reset_credit.detail_format" = "可重置 %d 次\n推估到期：%@\n依前次成功同步時間加 30 天推估，實際期限可能不同。";
"menu_bar.reset_credit.accessibility_format" = "可重置 %d 次，推估 %@ 到期";
```

`CodexPoolManager/zh-Hans.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d 次 · 约 %@ 到期";
"menu_bar.reset_credit.detail.title" = "可用重置额度";
"menu_bar.reset_credit.detail_format" = "可重置 %d 次\n预计到期：%@\n根据上次成功同步时间加 30 天估算，实际期限可能不同。";
"menu_bar.reset_credit.accessibility_format" = "可重置 %d 次，预计 %@ 到期";
```

`CodexPoolManager/fr.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d · exp. est. %@";
"menu_bar.reset_credit.detail.title" = "Réinitialisations disponibles";
"menu_bar.reset_credit.detail_format" = "%d réinitialisations disponibles\nExpiration estimée : %@\nEstimation basée sur la dernière synchronisation réussie plus 30 jours ; l’expiration réelle peut différer.";
"menu_bar.reset_credit.accessibility_format" = "%d réinitialisations, expiration estimée %@";
```

`CodexPoolManager/es.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d · vence aprox. %@";
"menu_bar.reset_credit.detail.title" = "Restablecimientos disponibles";
"menu_bar.reset_credit.detail_format" = "%d restablecimientos disponibles\nVencimiento estimado: %@\nEstimado desde la sincronización correcta anterior más 30 días; el vencimiento real puede variar.";
"menu_bar.reset_credit.accessibility_format" = "%d restablecimientos, vencimiento estimado %@";
```

`CodexPoolManager/ja.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d回 · 約%@まで";
"menu_bar.reset_credit.detail.title" = "利用可能なリセット";
"menu_bar.reset_credit.detail_format" = "利用可能なリセット：%d回\n推定有効期限：%@\n前回の同期成功時刻に30日を加えて推定しているため、実際の期限とは異なる場合があります。";
"menu_bar.reset_credit.accessibility_format" = "利用可能なリセット%d回、推定有効期限%@";
```

`CodexPoolManager/ko.lproj/Localizable.strings`:

```text
"menu_bar.reset_credit.badge_format" = "%d회 · 약 %@ 만료";
"menu_bar.reset_credit.detail.title" = "사용 가능한 초기화";
"menu_bar.reset_credit.detail_format" = "사용 가능한 초기화 %d회\n예상 만료: %@\n이전 동기화 성공 시각에 30일을 더해 추정하므로 실제 만료 시각과 다를 수 있습니다.";
"menu_bar.reset_credit.accessibility_format" = "사용 가능한 초기화 %d회, 예상 만료 %@";
```

- [ ] **Step 5: Run presenter tests and localization lint**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests
for file in CodexPoolManager/*.lproj/Localizable.strings; do plutil -lint "$file"; done
```

Expected: presenter tests PASS and every localization reports `OK`.

- [ ] **Step 6: Commit presenter and localization changes**

```bash
git add CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift CodexPoolManager/*.lproj/Localizable.strings CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift
git commit -m "feat(menu-bar): present reset credit expiry"
```

### Task 4: Remove the duplicate section and add the compact badge popover

**Files:**
- Modify: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
- Test: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Write the failing structural view test**

Add beside the existing compact-account-row smoke test:

```swift
@Test
func richMenuBarDashboardUsesSingleAccountSectionAndResetCreditPopover() throws {
    let testFile = URL(fileURLWithPath: #filePath)
    let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
    let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
    let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

    #expect(!source.contains("activeAccountSection"))
    #expect(source.contains("resetCreditIndicator"))
    #expect(source.contains("isResetCreditPopoverPresented"))
    #expect(source.contains("menu_bar.reset_credit.detail.title"))
    #expect(source.contains("row.resetCreditAccessibilityLabel"))
}
```

- [ ] **Step 2: Run the view test and verify RED**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardUsesSingleAccountSectionAndResetCreditPopover
```

Expected: FAIL because the duplicate section still exists and the reset-credit popover does not.

- [ ] **Step 3: Remove the duplicated current-account section**

Change the non-empty body branch to:

```swift
if snapshot.accountRows.isEmpty {
    emptyState
} else {
    accountsSection
}
```

Delete the complete `activeAccountSection` computed property. Keep `snapshot.activeAccount` in the presenter because the group-switcher default still uses its group.

- [ ] **Step 4: Add the compact clickable indicator**

Add to `AccountRowView`:

```swift
@State private var isResetCreditPopoverPresented = false
```

Render `resetCreditIndicator` after the plan badge and before `accountWarningIndicator`. Add:

```swift
@ViewBuilder
private var resetCreditIndicator: some View {
    if let badgeText = row.resetCreditBadgeText,
       let detailText = row.resetCreditDetailText {
        Button {
            isResetCreditPopoverPresented.toggle()
        } label: {
            Label {
                Text(badgeText)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "arrow.counterclockwise.circle")
            }
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(detailText)
        .accessibilityLabel(row.resetCreditAccessibilityLabel ?? detailText)
        .popover(isPresented: $isResetCreditPopoverPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("menu_bar.reset_credit.detail.title"))
                    .font(.headline)
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 280, alignment: .leading)
        }
    }
}
```

Do not add a third row; leave `accountUsageResetLine` unchanged.

- [ ] **Step 5: Run view and presenter tests**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardUsesSingleAccountSectionAndResetCreditPopover -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardKeepsAccountRowsCompact -only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests
```

Expected: all selected tests PASS.

- [ ] **Step 6: Commit the SwiftUI change**

```bash
git add CodexPoolManager/MenuBar/MenuBarDashboardView.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift
git commit -m "feat(menu-bar): show reset credit estimate"
```

### Task 5: Full verification

**Files:**
- Verify: `Domain/Pool/AgentPool.swift`
- Verify: `Infrastructure/Usage/CodexUsageSyncService.swift`
- Verify: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
- Verify: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
- Verify: `CodexPoolManagerTests/CodexPoolManagerTests.swift`
- Verify: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`
- Verify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Check diffs and localizations**

```bash
git diff --check
for file in CodexPoolManager/*.lproj/Localizable.strings; do plutil -lint "$file"; done
```

Expected: no diff errors and every localization reports `OK`.

- [ ] **Step 2: Run all non-UI tests**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -skip-testing:CodexPoolManagerUITests
```

Expected: all unit and smoke tests PASS.

- [ ] **Step 3: Run UI tests**

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -only-testing:CodexPoolManagerUITests
```

Expected: all UI tests PASS.

- [ ] **Step 4: Build the app**

```bash
xcodebuild build -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS'
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Inspect the final branch**

```bash
git status --short --branch
git log --oneline --decorate -6
```

Expected: clean worktree on `codex/menu-bar-reset-credit-expiry`, with the design, decoder, estimate, presenter, and SwiftUI commits visible.

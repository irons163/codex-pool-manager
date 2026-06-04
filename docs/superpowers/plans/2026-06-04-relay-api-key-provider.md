# Relay API Key Provider Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Relay/API Key accounts that can switch Codex CLI to an OpenAI-compatible custom provider without mixing those accounts into ChatGPT OAuth usage sync.

**Architecture:** Extend the existing `AgentAccount` model with a credential type and relay metadata, then route relay switching through a new focused Codex config/login service. Existing OAuth accounts keep the current `auth.json` rewrite path; relay accounts update `~/.codex/config.toml` and call `codex login --with-api-key`. Usage sync treats relay accounts as intentionally unsupported and excludes them from automatic switching by setting a stable sync-exclusion reason.

**Tech Stack:** Swift 5, SwiftUI, Swift Testing, macOS `Process`, UserDefaults token vault, Codex CLI `config.toml` and `codex login --with-api-key`.

---

## File Structure

- Modify `Domain/Pool/AgentPool.swift`: add `AgentAccountCredentialType`, relay metadata, relay account helpers, snapshot compatibility, account creation/update/duplication support, and automatic-switch exclusion behavior.
- Modify `Infrastructure/Usage/CodexUsageSyncService.swift`: skip relay accounts with a stable non-error exclusion reason before OAuth token/account-id checks.
- Create `Infrastructure/Auth/CodexProviderConfigService.swift`: validate provider config, merge provider table into `config.toml`, and write the file.
- Create `Infrastructure/Auth/CodexAPIKeyLoginService.swift`: call `codex login --with-api-key` using stdin, with testable process abstraction.
- Modify `Features/PoolDashboard/PoolDashboardFormState.swift`: add relay form fields and reset helpers.
- Create `Features/PoolDashboard/PoolDashboardRelayAccountCoordinator.swift`: add/update relay accounts and perform relay switch orchestration.
- Create `Features/PoolDashboard/Components/RelayAPIKeyPanelView.swift`: compact Authentication workspace panel for relay profile input.
- Modify `Features/PoolDashboard/PoolDashboardViewState.swift`: add relay success/error state.
- Modify `Features/PoolDashboard/PoolDashboardView.swift`: render the relay panel, wire actions, and route account switching to OAuth or relay paths by credential type.
- Modify `Features/PoolDashboard/Components/AccountUsagePanelView.swift`: label relay cards as sync-unavailable and allow manual switch.
- Modify localization files under `CodexPoolManager/*.lproj/Localizable.strings`: add relay UI and error strings.
- Modify tests in `CodexPoolManagerTests/CodexPoolManagerTests.swift`, `CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift`, and add `CodexPoolManagerTests/CodexProviderConfigServiceTests.swift` if splitting keeps tests readable.
- Modify `README.zh-Hant.md` and `README.md`: document relay/API key provider support and usage-sync limitation.

---

### Task 1: Domain Model And Backward-Compatible Snapshot Decoding

**Files:**
- Modify: `Domain/Pool/AgentPool.swift`
- Test: `CodexPoolManagerTests/CodexPoolManagerTests.swift`

- [ ] **Step 1: Write failing model compatibility tests**

Add these tests near existing `AgentAccount`/snapshot decoding tests in `CodexPoolManagerTests/CodexPoolManagerTests.swift`:

```swift
@Test
func agentAccountDecodesMissingCredentialTypeAsChatGPTOAuth() throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
    let json = """
    {
      "id": "\(id.uuidString)",
      "createdAt": "2026-06-04T00:00:00Z",
      "name": "legacy@example.com",
      "groupName": "Default",
      "usedUnits": 1,
      "quota": 100,
      "apiToken": "oauth-token",
      "chatGPTAccountID": "acct-legacy"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let account = try decoder.decode(AgentAccount.self, from: Data(json.utf8))

    #expect(account.credentialType == .chatGPTOAuth)
    #expect(!account.isRelayAPIKeyAccount)
    #expect(account.apiToken == "oauth-token")
    #expect(account.chatGPTAccountID == "acct-legacy")
}

@Test
func relayAPIKeyAccountKeepsProviderMetadataAndRedactsKey() {
    let account = AgentAccount(
        id: UUID(),
        name: "Mirror",
        usedUnits: 0,
        quota: 100,
        apiToken: "sk-relay-secret",
        credentialType: .relayAPIKey,
        relayProviderID: "mirror",
        relayProviderName: "mirror",
        relayBaseURL: "https://ai.liaryai.com/api/codex",
        relayWireAPI: "responses",
        relayRequiresOpenAIAuth: true,
        isUsageSyncExcluded: true,
        usageSyncError: AgentAccount.relayUsageSyncUnavailableReason
    )

    let redacted = account.redactingAPIToken()

    #expect(account.isRelayAPIKeyAccount)
    #expect(account.relayProviderID == "mirror")
    #expect(account.relayBaseURL == "https://ai.liaryai.com/api/codex")
    #expect(redacted.apiToken == "")
    #expect(redacted.credentialType == .relayAPIKey)
    #expect(redacted.relayProviderID == "mirror")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/agentAccountDecodesMissingCredentialTypeAsChatGPTOAuth -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/relayAPIKeyAccountKeepsProviderMetadataAndRedactsKey
```

Expected: compile failure because `AgentAccountCredentialType`, `credentialType`, and relay metadata do not exist.

- [ ] **Step 3: Add credential type and relay metadata**

In `Domain/Pool/AgentPool.swift`, add this enum above `AgentAccount`:

```swift
enum AgentAccountCredentialType: String, Codable, Equatable {
    case chatGPTOAuth = "chatgpt_oauth"
    case relayAPIKey = "relay_api_key"
}
```

Extend `AgentAccount` properties:

```swift
    var credentialType: AgentAccountCredentialType
    var relayProviderID: String?
    var relayProviderName: String?
    var relayBaseURL: String?
    var relayWireAPI: String?
    var relayRequiresOpenAIAuth: Bool
```

Add defaults and helpers inside `AgentAccount`:

```swift
    static let defaultRelayWireAPI = "responses"
    static let relayUsageSyncUnavailableReason = "API key relay account: usage sync unavailable"

    var isRelayAPIKeyAccount: Bool {
        credentialType == .relayAPIKey
    }

    var supportsCodexUsageSync: Bool {
        credentialType == .chatGPTOAuth
    }
```

Update the main initializer signature with defaults:

```swift
        credentialType: AgentAccountCredentialType = .chatGPTOAuth,
        relayProviderID: String? = nil,
        relayProviderName: String? = nil,
        relayBaseURL: String? = nil,
        relayWireAPI: String? = nil,
        relayRequiresOpenAIAuth: Bool = true,
```

Assign normalized values in the initializer:

```swift
        self.credentialType = credentialType
        self.relayProviderID = relayProviderID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayProviderName = relayProviderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayBaseURL = relayBaseURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.relayWireAPI = (relayWireAPI?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? relayWireAPI?.trimmingCharacters(in: .whitespacesAndNewlines)
            : Self.defaultRelayWireAPI
        self.relayRequiresOpenAIAuth = relayRequiresOpenAIAuth
```

Update `init(from:)` to decode missing fields safely:

```swift
        credentialType = try container.decodeIfPresent(AgentAccountCredentialType.self, forKey: .credentialType) ?? .chatGPTOAuth
        relayProviderID = try container.decodeIfPresent(String.self, forKey: .relayProviderID)
        relayProviderName = try container.decodeIfPresent(String.self, forKey: .relayProviderName)
        relayBaseURL = try container.decodeIfPresent(String.self, forKey: .relayBaseURL)
        relayWireAPI = try container.decodeIfPresent(String.self, forKey: .relayWireAPI) ?? AgentAccount.defaultRelayWireAPI
        relayRequiresOpenAIAuth = try container.decodeIfPresent(Bool.self, forKey: .relayRequiresOpenAIAuth) ?? true
```

Update `redactingAPIToken()`, `duplicateAccount`, `addAccount`, and `updateAccount` to preserve and accept the new fields. `updateAccount` should add optional parameters with these names:

```swift
        credentialType: AgentAccountCredentialType? = nil,
        relayProviderID: String? = nil,
        relayProviderName: String? = nil,
        relayBaseURL: String? = nil,
        relayWireAPI: String? = nil,
        relayRequiresOpenAIAuth: Bool? = nil,
```

Inside `updateAccount`, assign each optional value when provided.

- [ ] **Step 4: Run focused tests**

Run the same command from Step 2.

Expected: both tests pass.

- [ ] **Step 5: Run domain snapshot tests around sensitive export**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/snapshotExportCanIncludeApiTokenForRefetchExport
```

Expected: pass, proving existing token export behavior still works.

- [ ] **Step 6: Commit**

```bash
git add Domain/Pool/AgentPool.swift CodexPoolManagerTests/CodexPoolManagerTests.swift
git commit -m "feat: add relay account model"
```

---

### Task 2: Usage Sync Skips Relay Accounts Cleanly

**Files:**
- Modify: `Infrastructure/Usage/CodexUsageSyncService.swift`
- Modify: `Domain/Pool/AgentPool.swift`
- Test: `CodexPoolManagerTests/CodexPoolManagerTests.swift`

- [ ] **Step 1: Write failing usage-sync skip test**

Add this test near existing `CodexUsageSyncService` tests:

```swift
@Test
func codexSyncSkipsRelayAPIKeyAccountsWithoutCallingClient() async throws {
    let relayID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
    var state = AccountPoolState(
        accounts: [
            AgentAccount(
                id: relayID,
                name: "Mirror",
                usedUnits: 0,
                quota: 100,
                apiToken: "sk-relay",
                credentialType: .relayAPIKey,
                relayProviderID: "mirror",
                relayProviderName: "mirror",
                relayBaseURL: "https://ai.liaryai.com/api/codex",
                relayWireAPI: "responses",
                relayRequiresOpenAIAuth: true
            )
        ],
        mode: .intelligent
    )

    let requests = LockedValue<[(token: String, accountID: String)]>([])
    struct CapturingClient: CodexUsageClient {
        let requests: LockedValue<[(token: String, accountID: String)]>
        func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
            requests.withLock { $0.append((accessToken, accountID)) }
            return CodexUsage(usedUnits: 99, quota: 100)
        }
    }

    let sync = CodexUsageSyncService(client: CapturingClient(requests: requests))
    try await sync.sync(state: &state, now: Date(timeIntervalSince1970: 10))

    #expect(requests.value.isEmpty)
    #expect(state.accounts[0].isUsageSyncExcluded)
    #expect(state.accounts[0].usageSyncError == AgentAccount.relayUsageSyncUnavailableReason)
    #expect(state.activeAccountID == nil)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/codexSyncSkipsRelayAPIKeyAccountsWithoutCallingClient
```

Expected: fail because sync currently checks token/account id instead of relay type.

- [ ] **Step 3: Skip relay accounts before OAuth checks**

In `Infrastructure/Usage/CodexUsageSyncService.swift`, add this at the top of the `for account in state.accounts` loop, before the missing-token guard:

```swift
            guard account.supportsCodexUsageSync else {
                state.setUsageSyncExclusion(
                    for: account.id,
                    reason: AgentAccount.relayUsageSyncUnavailableReason,
                    now: now,
                    shouldEvaluate: false
                )
                continue
            }
```

In `Domain/Pool/AgentPool.swift`, update `syncIncludedAccounts` so relay accounts are excluded even before the first usage sync has run:

```swift
    private var syncIncludedAccounts: [AgentAccount] {
        accounts.filter { !$0.isUsageSyncExcluded && $0.supportsCodexUsageSync }
    }
```

- [ ] **Step 4: Run focused usage-sync tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/codexSyncSkipsRelayAPIKeyAccountsWithoutCallingClient -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/codexSyncSkipsAccountWithoutChatGPTAccountID -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/codexSyncKeepsStateWhenClientFails
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Domain/Pool/AgentPool.swift Infrastructure/Usage/CodexUsageSyncService.swift CodexPoolManagerTests/CodexPoolManagerTests.swift
git commit -m "fix: skip relay accounts during usage sync"
```

---

### Task 3: Codex Provider Config Service

**Files:**
- Create: `Infrastructure/Auth/CodexProviderConfigService.swift`
- Test: `CodexPoolManagerTests/CodexProviderConfigServiceTests.swift`

- [ ] **Step 1: Write failing config merge tests**

Create `CodexPoolManagerTests/CodexProviderConfigServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import CodexPoolManager

struct CodexProviderConfigServiceTests {
    @Test
    func providerConfigRendersMirrorTable() throws {
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let rendered = config.renderTOMLBlock()

        #expect(rendered.contains("[model_providers.mirror]"))
        #expect(rendered.contains("name = \"mirror\""))
        #expect(rendered.contains("base_url = \"https://ai.liaryai.com/api/codex\""))
        #expect(rendered.contains("wire_api = \"responses\""))
        #expect(rendered.contains("requires_openai_auth = true"))
    }

    @Test
    func configMergeInsertsModelProviderIntoEmptyConfig() throws {
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let merged = CodexProviderConfigMerger.merge(existing: "", provider: config)

        #expect(merged.hasPrefix("model_provider = \"mirror\""))
        #expect(merged.contains("[model_providers.mirror]"))
    }

    @Test
    func configMergeReplacesTopLevelModelProviderAndSameProviderTableOnly() throws {
        let existing = """
        model = "gpt-5.1-codex"
        model_provider = "openai"

        [model_providers.other]
        name = "other"
        base_url = "https://other.example.com/v1"
        wire_api = "responses"
        requires_openai_auth = false

        [model_providers.mirror]
        name = "old"
        base_url = "https://old.example.com/v1"
        wire_api = "chat"
        requires_openai_auth = false
        """
        let config = try CodexProviderConfig(
            providerID: "mirror",
            name: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            requiresOpenAIAuth: true
        )

        let merged = CodexProviderConfigMerger.merge(existing: existing, provider: config)

        #expect(merged.contains("model = \"gpt-5.1-codex\""))
        #expect(merged.contains("model_provider = \"mirror\""))
        #expect(merged.contains("[model_providers.other]"))
        #expect(merged.contains("base_url = \"https://other.example.com/v1\""))
        #expect(!merged.contains("https://old.example.com/v1"))
        #expect(merged.contains("base_url = \"https://ai.liaryai.com/api/codex\""))
    }

    @Test
    func providerConfigRejectsInvalidProviderID() {
        #expect(throws: CodexProviderConfigError.invalidProviderID) {
            _ = try CodexProviderConfig(
                providerID: "mirror-prod",
                name: "mirror-prod",
                baseURL: "https://ai.liaryai.com/api/codex",
                wireAPI: "responses",
                requiresOpenAIAuth: true
            )
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexProviderConfigServiceTests
```

Expected: compile failure because service types do not exist.

- [ ] **Step 3: Implement config types and merge logic**

Create `Infrastructure/Auth/CodexProviderConfigService.swift`:

```swift
import Foundation

enum CodexProviderConfigError: Error, Equatable, LocalizedError {
    case invalidProviderID
    case invalidBaseURL
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidProviderID:
            return L10n.text("relay.error.invalid_provider_id")
        case .invalidBaseURL:
            return L10n.text("relay.error.invalid_base_url")
        case let .writeFailed(message):
            return L10n.text("relay.error.config_write_failed_format", message)
        }
    }
}

struct CodexProviderConfig: Equatable {
    let providerID: String
    let name: String
    let baseURL: URL
    let wireAPI: String
    let requiresOpenAIAuth: Bool

    init(
        providerID: String,
        name: String,
        baseURL: String,
        wireAPI: String = AgentAccount.defaultRelayWireAPI,
        requiresOpenAIAuth: Bool = true
    ) throws {
        let trimmedProviderID = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedProviderID.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil else {
            throw CodexProviderConfigError.invalidProviderID
        }
        guard let parsedBaseURL = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              parsedBaseURL.scheme?.hasPrefix("http") == true,
              parsedBaseURL.host?.isEmpty == false else {
            throw CodexProviderConfigError.invalidBaseURL
        }

        self.providerID = trimmedProviderID
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? trimmedProviderID : name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.baseURL = parsedBaseURL
        let trimmedWireAPI = wireAPI.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wireAPI = trimmedWireAPI.isEmpty ? AgentAccount.defaultRelayWireAPI : trimmedWireAPI
        self.requiresOpenAIAuth = requiresOpenAIAuth
    }

    func renderTOMLBlock() -> String {
        """
        [model_providers.\(providerID)]
        name = \"\(Self.escape(name))\"
        base_url = \"\(Self.escape(baseURL.absoluteString))\"
        wire_api = \"\(Self.escape(wireAPI))\"
        requires_openai_auth = \(requiresOpenAIAuth ? "true" : "false")
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum CodexProviderConfigMerger {
    static func merge(existing: String, provider: CodexProviderConfig) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        replaceTopLevelModelProvider(in: &lines, providerID: provider.providerID)
        removeProviderTable(provider.providerID, from: &lines)
        trimTrailingBlankLines(&lines)
        if !lines.isEmpty { lines.append("") }
        lines.append(provider.renderTOMLBlock())
        return lines.joined(separator: "\n") + "\n"
    }

    private static func replaceTopLevelModelProvider(in lines: inout [String], providerID: String) {
        var insideTable = false
        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { insideTable = true }
            if !insideTable && trimmed.hasPrefix("model_provider") {
                lines[index] = "model_provider = \"\(providerID)\""
                return
            }
        }
        lines.insert("model_provider = \"\(providerID)\"", at: 0)
    }

    private static func removeProviderTable(_ providerID: String, from lines: inout [String]) {
        let header = "[model_providers.\(providerID)]"
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == header }) else { return }
        var end = lines.index(after: start)
        while end < lines.endIndex {
            let trimmed = lines[end].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") { break }
            end = lines.index(after: end)
        }
        lines.removeSubrange(start..<end)
    }

    private static func trimTrailingBlankLines(_ lines: inout [String]) {
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }
    }
}

struct CodexProviderConfigService {
    var configURLProvider: () -> URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex/config.toml")
    }

    func apply(_ provider: CodexProviderConfig) throws {
        let url = configURLProvider()
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let merged = CodexProviderConfigMerger.merge(existing: existing, provider: provider)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try merged.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw CodexProviderConfigError.writeFailed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 4: Add localization strings used by errors**

Add to `CodexPoolManager/en.lproj/Localizable.strings`:

```text
"relay.error.invalid_provider_id" = "Provider ID may contain only letters, numbers, and underscores.";
"relay.error.invalid_base_url" = "Relay base URL must be a valid http or https URL.";
"relay.error.config_write_failed_format" = "Unable to update Codex config: %@";
```

Add matching Traditional Chinese strings to `CodexPoolManager/zh-Hant.lproj/Localizable.strings`:

```text
"relay.error.invalid_provider_id" = "Provider ID 只能包含英文字母、數字與底線。";
"relay.error.invalid_base_url" = "中轉 Base URL 必須是有效的 http 或 https URL。";
"relay.error.config_write_failed_format" = "無法更新 Codex config：%@";
```

For `zh-Hans`, `ja`, `ko`, `fr`, and `es`, add English fallback text if no localized copy is available.

- [ ] **Step 5: Run config tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexProviderConfigServiceTests
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add Infrastructure/Auth/CodexProviderConfigService.swift CodexPoolManagerTests/CodexProviderConfigServiceTests.swift CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat: add codex provider config writer"
```

---

### Task 4: API Key Login Service And Relay Switch Coordinator

**Files:**
- Create: `Infrastructure/Auth/CodexAPIKeyLoginService.swift`
- Create: `Features/PoolDashboard/PoolDashboardRelayAccountCoordinator.swift`
- Modify: `Features/PoolDashboard/PoolDashboardViewState.swift`
- Test: `CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift`

- [ ] **Step 1: Write failing login/coordinator tests**

Add this to `CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift`:

```swift
struct RelayAccountCoordinatorTests {
    @Test
    func relayCoordinatorAddsRelayAccountAndMarksUsageSyncUnavailable() async {
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { _ in },
            apiKeyLogin: { _ in }
        )
        var state = AccountPoolState(accounts: [], mode: .manual)
        var viewState = PoolDashboardViewState()

        let output = await coordinator.addRelayAccount(
            to: state,
            viewState: viewState,
            name: "Mirror",
            providerID: "mirror",
            providerName: "mirror",
            baseURL: "https://ai.liaryai.com/api/codex",
            wireAPI: "responses",
            apiKey: "sk-relay"
        )
        state = output.state
        viewState = output.viewState

        #expect(state.accounts.count == 1)
        #expect(state.accounts[0].credentialType == .relayAPIKey)
        #expect(state.accounts[0].apiToken == "sk-relay")
        #expect(state.accounts[0].relayProviderID == "mirror")
        #expect(state.accounts[0].isUsageSyncExcluded)
        #expect(state.accounts[0].usageSyncError == AgentAccount.relayUsageSyncUnavailableReason)
        #expect(viewState.relaySuccessMessage == L10n.text("relay.status.added"))
    }

    @Test
    func relayCoordinatorSwitchesByApplyingConfigThenLoggingIn() async {
        let events = LockedValue<[String]>([])
        let coordinator = PoolDashboardRelayAccountCoordinator(
            configApplier: { provider in events.withLock { $0.append("config:\(provider.providerID)") } },
            apiKeyLogin: { apiKey in events.withLock { $0.append("login:\(apiKey)") } }
        )
        let account = AgentAccount(
            id: UUID(),
            name: "Mirror",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.liaryai.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true
        )

        let output = await coordinator.switchToRelayAccount(account, viewState: PoolDashboardViewState())

        #expect(events.value == ["config:mirror", "login:sk-relay"])
        #expect(output.viewState.switchLaunchError == nil)
        #expect(output.viewState.lastSwitchLaunchLog.contains("mirror"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/RelayAccountCoordinatorTests
```

Expected: compile failure because coordinator and view-state fields do not exist.

- [ ] **Step 3: Implement API key login service**

Create `Infrastructure/Auth/CodexAPIKeyLoginService.swift`:

```swift
import Foundation

enum CodexAPIKeyLoginError: Error, LocalizedError, Equatable {
    case missingCodexCLI
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCodexCLI:
            return L10n.text("relay.error.codex_cli_missing")
        case let .loginFailed(message):
            return L10n.text("relay.error.login_failed_format", message)
        }
    }
}

struct CodexAPIKeyLoginService {
    var executableURLProvider: () -> URL? = {
        ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    var processRunner: (URL, [String], Data) async throws -> (terminationStatus: Int32, output: String) = { executableURL, arguments, input in
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stdin = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = stdout
            process.standardError = stdout
            process.standardInput = stdin
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (process.terminationStatus, output))
            }
            do {
                try process.run()
                stdin.fileHandleForWriting.write(input)
                try stdin.fileHandleForWriting.close()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func login(apiKey: String) async throws {
        guard let executableURL = executableURLProvider() else {
            throw CodexAPIKeyLoginError.missingCodexCLI
        }
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await processRunner(executableURL, ["login", "--with-api-key"], Data(trimmed.utf8))
        guard result.terminationStatus == 0 else {
            throw CodexAPIKeyLoginError.loginFailed(result.output)
        }
    }
}
```

- [ ] **Step 4: Implement relay coordinator and view-state fields**

In `Features/PoolDashboard/PoolDashboardViewState.swift`, add:

```swift
    var relayError: String?
    var relaySuccessMessage: String?
```

Create `Features/PoolDashboard/PoolDashboardRelayAccountCoordinator.swift`:

```swift
import Foundation

struct PoolDashboardRelayAccountCoordinator {
    struct AddOutput {
        let state: AccountPoolState
        let viewState: PoolDashboardViewState
    }

    struct SwitchOutput {
        let viewState: PoolDashboardViewState
    }

    private let configApplier: (CodexProviderConfig) throws -> Void
    private let apiKeyLogin: (String) async throws -> Void

    init(
        configApplier: @escaping (CodexProviderConfig) throws -> Void = { try CodexProviderConfigService().apply($0) },
        apiKeyLogin: @escaping (String) async throws -> Void = { try await CodexAPIKeyLoginService().login(apiKey: $0) }
    ) {
        self.configApplier = configApplier
        self.apiKeyLogin = apiKeyLogin
    }

    func addRelayAccount(
        to state: AccountPoolState,
        viewState: PoolDashboardViewState,
        name: String,
        providerID: String,
        providerName: String,
        baseURL: String,
        wireAPI: String,
        apiKey: String
    ) async -> AddOutput {
        var nextState = state
        var nextViewState = viewState
        do {
            let provider = try CodexProviderConfig(providerID: providerID, name: providerName, baseURL: baseURL, wireAPI: wireAPI)
            let accountID = nextState.addAccount(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? provider.name : name,
                quota: 100,
                usedUnits: 0,
                credentialType: .relayAPIKey,
                relayProviderID: provider.providerID,
                relayProviderName: provider.name,
                relayBaseURL: provider.baseURL.absoluteString,
                relayWireAPI: provider.wireAPI,
                relayRequiresOpenAIAuth: provider.requiresOpenAIAuth
            )
            nextState.updateAccount(
                accountID,
                apiToken: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                credentialType: .relayAPIKey,
                relayProviderID: provider.providerID,
                relayProviderName: provider.name,
                relayBaseURL: provider.baseURL.absoluteString,
                relayWireAPI: provider.wireAPI,
                relayRequiresOpenAIAuth: provider.requiresOpenAIAuth,
                shouldEvaluate: false
            )
            nextState.setUsageSyncExclusion(for: accountID, reason: AgentAccount.relayUsageSyncUnavailableReason)
            nextViewState.relayError = nil
            nextViewState.relaySuccessMessage = L10n.text("relay.status.added")
        } catch {
            nextViewState.relaySuccessMessage = nil
            nextViewState.relayError = error.localizedDescription
        }
        return AddOutput(state: nextState, viewState: nextViewState)
    }

    func switchToRelayAccount(_ account: AgentAccount, viewState: PoolDashboardViewState) async -> SwitchOutput {
        var nextViewState = viewState
        var logLines = [L10n.text("relay.switch.start_format", account.name)]
        do {
            guard account.isRelayAPIKeyAccount else { throw CodexProviderConfigError.invalidProviderID }
            guard !account.apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CodexAPIKeyLoginError.loginFailed(L10n.text("relay.error.missing_api_key")) }
            let provider = try CodexProviderConfig(
                providerID: account.relayProviderID ?? "",
                name: account.relayProviderName ?? account.relayProviderID ?? "",
                baseURL: account.relayBaseURL ?? "",
                wireAPI: account.relayWireAPI ?? AgentAccount.defaultRelayWireAPI,
                requiresOpenAIAuth: account.relayRequiresOpenAIAuth
            )
            try configApplier(provider)
            logLines.append(L10n.text("relay.switch.config_updated_format", provider.providerID))
            try await apiKeyLogin(account.apiToken)
            logLines.append(L10n.text("relay.switch.login_completed"))
            nextViewState.switchLaunchError = nil
            nextViewState.switchLaunchWarning = nil
        } catch {
            logLines.append(L10n.text("relay.switch.failed_format", error.localizedDescription))
            nextViewState.switchLaunchError = error.localizedDescription
        }
        nextViewState.lastSwitchLaunchLog = logLines.joined(separator: "\n")
        return SwitchOutput(viewState: nextViewState)
    }
}
```

`switchToRelayAccount` must not create or return a replacement `AccountPoolState`; switching only mutates `PoolDashboardViewState` and writes Codex CLI config/auth side effects.

- [ ] **Step 5: Add localization strings**

Add to English and Traditional Chinese localization files, with English fallbacks for the remaining locales:

```text
"relay.status.added" = "Relay account added.";
"relay.error.codex_cli_missing" = "Codex CLI was not found.";
"relay.error.login_failed_format" = "Codex API key login failed: %@";
"relay.error.missing_api_key" = "API key is required.";
"relay.switch.start_format" = "Switching Codex provider to %@";
"relay.switch.config_updated_format" = "Updated Codex config provider: %@";
"relay.switch.login_completed" = "Codex API key login completed.";
"relay.switch.failed_format" = "Relay switch failed: %@";
```

- [ ] **Step 6: Run coordinator tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/RelayAccountCoordinatorTests
```

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add Infrastructure/Auth/CodexAPIKeyLoginService.swift Features/PoolDashboard/PoolDashboardRelayAccountCoordinator.swift Features/PoolDashboard/PoolDashboardViewState.swift CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat: add relay account switch coordinator"
```

---

### Task 5: Authentication UI For Relay Accounts

**Files:**
- Modify: `Features/PoolDashboard/PoolDashboardFormState.swift`
- Create: `Features/PoolDashboard/Components/RelayAPIKeyPanelView.swift`
- Modify: `Features/PoolDashboard/PoolDashboardView.swift`
- Test: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Write failing form-state test**

Add a small test near form-state coverage:

```swift
@Test
func relayFormStateDefaultsAndReset() {
    var form = PoolDashboardFormState()
    #expect(form.relayProviderID == "mirror")
    #expect(form.relayProviderName == "mirror")
    #expect(form.relayBaseURL == "https://ai.liaryai.com/api/codex")
    #expect(form.relayWireAPI == "responses")

    form.relayAccountName = "Custom"
    form.relayAPIKey = "sk-test"
    form.resetRelayInput()

    #expect(form.relayAccountName == "")
    #expect(form.relayAPIKey == "")
    #expect(form.relayProviderID == "mirror")
}
```

- [ ] **Step 2: Add relay form fields**

In `Features/PoolDashboard/PoolDashboardFormState.swift`, add:

```swift
    static let defaultRelayProviderID = "mirror"
    static let defaultRelayBaseURL = "https://ai.liaryai.com/api/codex"

    var relayAccountName = ""
    var relayProviderID = Self.defaultRelayProviderID
    var relayProviderName = Self.defaultRelayProviderID
    var relayBaseURL = Self.defaultRelayBaseURL
    var relayWireAPI = AgentAccount.defaultRelayWireAPI
    var relayAPIKey = ""

    mutating func resetRelayInput() {
        relayAccountName = ""
        relayProviderID = Self.defaultRelayProviderID
        relayProviderName = Self.defaultRelayProviderID
        relayBaseURL = Self.defaultRelayBaseURL
        relayWireAPI = AgentAccount.defaultRelayWireAPI
        relayAPIKey = ""
    }
```

- [ ] **Step 3: Create RelayAPIKeyPanelView**

Create `Features/PoolDashboard/Components/RelayAPIKeyPanelView.swift`:

```swift
import SwiftUI

struct RelayAPIKeyPanelView: View {
    @Binding var accountName: String
    @Binding var providerID: String
    @Binding var providerName: String
    @Binding var baseURL: String
    @Binding var wireAPI: String
    @Binding var apiKey: String

    let successMessage: String?
    let errorMessage: String?
    let onAddRelayAccount: () -> Void

    var body: some View {
        GroupBox(L10n.text("relay.title")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.oauthPanelSpacing) {
                Text(L10n.text("relay.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)

                advancedField(L10n.text("relay.account_name.label"), placeholder: "Mirror", text: $accountName)
                advancedField(L10n.text("relay.provider_id.label"), placeholder: "mirror", text: $providerID)
                advancedField(L10n.text("relay.provider_name.label"), placeholder: "mirror", text: $providerName)
                advancedField(L10n.text("relay.base_url.label"), placeholder: "https://ai.liaryai.com/api/codex", text: $baseURL)
                advancedField(L10n.text("relay.wire_api.label"), placeholder: "responses", text: $wireAPI)
                SecureField(L10n.text("relay.api_key.placeholder"), text: $apiKey)
                    .dashboardInputFieldStyle()
                    .accessibilityIdentifier("auth.relay.apiKey")

                Button(L10n.text("relay.add_button")) {
                    onAddRelayAccount()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("auth.relay.addButton")

                if let successMessage {
                    PanelStatusCalloutView(message: successMessage, title: L10n.text("relay.status.title"), tone: .success)
                }
                if let errorMessage {
                    PanelStatusCalloutView(message: errorMessage, title: L10n.text("relay.error.title"), tone: .danger)
                }
            }
        }
        .sectionCardStyle()
    }

    private func advancedField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            TextField(placeholder, text: text)
                .dashboardInputFieldStyle()
        }
    }
}
```

- [ ] **Step 4: Wire panel into Authentication workspace**

In `Features/PoolDashboard/PoolDashboardView.swift`, add a property:

```swift
    private let relayAccountCoordinator = PoolDashboardRelayAccountCoordinator()
```

Add `relayAPIKeyPanel` below `oauthLoginPanel` in the authentication workspace stack:

```swift
            relayAPIKeyPanel
```

Add the panel builder:

```swift
    private var relayAPIKeyPanel: some View {
        RelayAPIKeyPanelView(
            accountName: $formState.relayAccountName,
            providerID: $formState.relayProviderID,
            providerName: $formState.relayProviderName,
            baseURL: $formState.relayBaseURL,
            wireAPI: $formState.relayWireAPI,
            apiKey: $formState.relayAPIKey,
            successMessage: viewState.relaySuccessMessage,
            errorMessage: viewState.relayError,
            onAddRelayAccount: {
                addRelayAccount()
            }
        )
    }
```

Add `addRelayAccount()`:

```swift
    @MainActor
    private func addRelayAccount() {
        Task { @MainActor in
            let output = await relayAccountCoordinator.addRelayAccount(
                to: state,
                viewState: viewState,
                name: formState.relayAccountName,
                providerID: formState.relayProviderID,
                providerName: formState.relayProviderName,
                baseURL: formState.relayBaseURL,
                wireAPI: formState.relayWireAPI,
                apiKey: formState.relayAPIKey
            )
            state = output.state
            viewState = output.viewState
            if viewState.relayError == nil {
                formState.resetRelayInput()
            }
        }
    }
```

- [ ] **Step 5: Add localization strings**

Add to each localization file, with English fallback where needed:

```text
"relay.title" = "API Key Relay";
"relay.subtitle" = "Add an OpenAI-compatible relay provider for Codex CLI. Usage sync is unavailable for relay accounts.";
"relay.account_name.label" = "Account Name";
"relay.provider_id.label" = "Provider ID";
"relay.provider_name.label" = "Provider Name";
"relay.base_url.label" = "Base URL";
"relay.wire_api.label" = "Wire API";
"relay.api_key.placeholder" = "OpenAI API key";
"relay.add_button" = "Add Relay Account";
"relay.status.title" = "Relay Account";
"relay.error.title" = "Relay Error";
```

- [ ] **Step 6: Run focused UI/form tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/relayFormStateDefaultsAndReset
```

Expected: pass. If no existing view-smoke hook fits the panel, keep the form-state test and add a preview-free compile test by instantiating `RelayAPIKeyPanelView` with `.constant` bindings.

- [ ] **Step 7: Commit**

```bash
git add Features/PoolDashboard/PoolDashboardFormState.swift Features/PoolDashboard/Components/RelayAPIKeyPanelView.swift Features/PoolDashboard/PoolDashboardView.swift CodexPoolManagerTests CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat: add relay api key panel"
```

---

### Task 6: Route Manual Switching By Account Type

**Files:**
- Modify: `Features/PoolDashboard/PoolDashboardView.swift`
- Modify: `Features/PoolDashboard/Components/AccountUsagePanelView.swift`
- Test: `CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift`

- [ ] **Step 1: Write failing switch routing test**

Add a pure coordinator test if possible, or add this to `RelayAccountCoordinatorTests` to prove relay switch output is non-OAuth:

```swift
@Test
func relaySwitchDoesNotRequireAuthJSONFields() async {
    let coordinator = PoolDashboardRelayAccountCoordinator(
        configApplier: { _ in },
        apiKeyLogin: { _ in }
    )
    let account = AgentAccount(
        id: UUID(),
        name: "Mirror",
        usedUnits: 0,
        quota: 100,
        apiToken: "sk-relay",
        credentialType: .relayAPIKey,
        relayProviderID: "mirror",
        relayProviderName: "mirror",
        relayBaseURL: "https://ai.liaryai.com/api/codex",
        relayWireAPI: "responses",
        relayRequiresOpenAIAuth: true
    )

    let output = await coordinator.switchToRelayAccount(account, viewState: PoolDashboardViewState())

    #expect(output.viewState.switchLaunchError == nil)
    #expect(output.viewState.lastSwitchLaunchLog.contains("Codex API key login completed") || output.viewState.lastSwitchLaunchLog.contains(L10n.text("relay.switch.login_completed")))
}
```

- [ ] **Step 2: Route `switchAndLaunchCodex` by credential type**

In `Features/PoolDashboard/PoolDashboardView.swift`, locate `switchAndLaunchCodex(using:)`. At its start add:

```swift
        if account.isRelayAPIKeyAccount {
            await switchToRelayProvider(using: account)
            return
        }
```

Add the helper:

```swift
    @MainActor
    private func switchToRelayProvider(using account: AgentAccount) async {
        let output = await relayAccountCoordinator.switchToRelayAccount(
            account,
            viewState: viewState
        )
        viewState = output.viewState
        state.selectAccount(account.id)
    }
```

If `state.selectAccount` requires mode-specific behavior, use the existing account selection method currently used by manual switching. Preserve the behavior that manual click makes the selected relay account active.

- [ ] **Step 3: Add relay visual indicator in account cards**

In `Features/PoolDashboard/Components/AccountUsagePanelView.swift`, inside `accountCard(_:)` near the account name or status chips, add:

```swift
        if account.isRelayAPIKeyAccount {
            Text(L10n.text("relay.card.badge"))
                .font(.caption2.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(PoolDashboardTheme.cardStroke.opacity(0.35)))
        }
```

Update `syncExcludedWarning(_:)` so relay accounts use an info/success-ish tone if available. If `PanelStatusCalloutView` only supports existing tones, keep `.warning` but rely on the explicit message.

- [ ] **Step 4: Add localization**

```text
"relay.card.badge" = "Relay";
```

- [ ] **Step 5: Run switch tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/RelayAccountCoordinatorTests
```

Expected: pass.

- [ ] **Step 6: Run a full compile build**

Run:

```bash
xcodebuild -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -configuration Debug -sdk macosx build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Features/PoolDashboard/PoolDashboardView.swift Features/PoolDashboard/Components/AccountUsagePanelView.swift CodexPoolManagerTests/PoolDashboardCoordinatorTests.swift CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat: route relay account switching"
```

---

### Task 7: Docs, Release Notes, And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `README.zh-Hant.md`
- Modify: `docs/release-notes/v1.0.10.md`

- [ ] **Step 1: Update docs**

Add to `README.md` under Authentication or Runtime Strategy:

```markdown
### API Key Relay Providers

Codex Pool Manager can add an API Key / Relay account for Codex CLI custom providers. Relay accounts write a Codex provider block to `~/.codex/config.toml` and authenticate Codex through `codex login --with-api-key`.

Relay accounts do not support ChatGPT/Codex subscription usage sync. They are available for manual switching, but are excluded from automatic intelligent/focus switching until a relay-specific usage source is configured.
```

Add to `README.zh-Hant.md`:

```markdown
### API Key 中轉 Provider

Codex Pool Manager 可以新增 API Key / 中轉帳號，供 Codex CLI custom provider 使用。中轉帳號會寫入 `~/.codex/config.toml` 的 provider 區塊，並透過 `codex login --with-api-key` 讓 Codex 使用該 API key。

中轉帳號不支援 ChatGPT/Codex 訂閱用量同步。它可以手動切換，但在尚未支援中轉用量來源前，不會納入自動智慧/專注切換候選。
```

- [ ] **Step 2: Update release notes**

Append to the active release notes:

```markdown
- Added API Key / Relay provider accounts for Codex CLI custom provider switching. Relay accounts use `codex login --with-api-key` and are manual-switch only because ChatGPT subscription usage sync does not apply to API-key relay credentials.
```

- [ ] **Step 3: Run targeted tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/CodexProviderConfigServiceTests -only-testing:CodexPoolManagerTests/RelayAccountCoordinatorTests -only-testing:CodexPoolManagerTests/CodexPoolManagerTests/codexSyncSkipsRelayAPIKeyAccountsWithoutCallingClient
```

Expected: all pass.

- [ ] **Step 4: Run broader affected tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS,arch=arm64' -only-testing:CodexPoolManagerTests/AppUpdateServiceTests -only-testing:CodexPoolManagerTests/PoolDashboardSwitchLaunchCoordinatorTests -only-testing:CodexPoolManagerTests/PoolDashboardViewMutationCoordinatorTests
```

Expected: all pass.

- [ ] **Step 5: Run build**

Run:

```bash
xcodebuild -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -configuration Debug -sdk macosx build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Check dirty files and whitespace**

Run:

```bash
git diff --check
git status --short
```

Expected: `git diff --check` has no output. `git status --short` shows only intentional tracked changes and the pre-existing `.tmp/` untracked directory.

- [ ] **Step 7: Commit docs and final integration**

```bash
git add README.md README.zh-Hant.md docs/release-notes/v1.0.10.md
git commit -m "docs: document relay api key providers"
```

---

## Self-Review

- Spec coverage: account model, UI, switching, config writer, API key storage, usage sync behavior, error handling, tests, and release notes each map to at least one task.
- Red-flag scan: no `TBD`, `TODO`, or intentionally vague implementation placeholders remain.
- Type consistency: `AgentAccountCredentialType`, `CodexProviderConfig`, `CodexProviderConfigService`, `CodexAPIKeyLoginService`, `PoolDashboardRelayAccountCoordinator`, and relay form fields use the same names across tasks.

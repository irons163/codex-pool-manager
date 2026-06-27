# Menu Bar Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a rich macOS menu bar dashboard that keeps showing pool status and can sync/open/switch accounts after the main dashboard window is closed.

**Architecture:** Introduce one app-owned `AppPoolRuntimeModel` as the shared source of truth for the main dashboard and the menu bar. Keep existing dashboard coordinators and auth/switch services, then add a compact `.window` menu bar UI that consumes presenter snapshots from the shared runtime model.

**Tech Stack:** SwiftUI, Combine/Observation via `ObservableObject`, macOS `MenuBarExtra`, existing `AccountPoolState`/`DeveloperAwareAccountPoolStore`, existing PoolDashboard coordinators, Swift Testing, Xcode synchronized root groups.

---

## File Structure

Create app files under `CodexPoolManager/` because that directory is a `PBXFileSystemSynchronizedRootGroup` in `CodexPoolManager.xcodeproj/project.pbxproj`. Do not add new app source files under `Features/` for this feature unless the project file is intentionally updated.

- Create: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`
  - Pure formatting and row-model generation for the menu bar popover.
- Create: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
  - Rich SwiftUI popover shown by `MenuBarExtra`.
- Create: `CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift`
  - App-level pool state owner, background sync owner, widget publisher, and menu bar action surface.
- Modify: `CodexPoolManager/CodexPoolManagerApp.swift`
  - Replace polling `MenuBarSnapshotModel` with `AppPoolRuntimeModel`; use a named dashboard window and `.menuBarExtraStyle(.window)`.
- Modify: `ContentView.swift`
  - Accept an optional runtime model and pass it into `PoolDashboardView`.
- Modify: `Features/PoolDashboard/PoolDashboardView.swift`
  - Accept an optional runtime model, mirror state changes into runtime, and disable duplicate view-owned auto-sync when runtime is present.
- Modify: `Features/PoolDashboard/PoolDashboardRuntimeCoordinator.swift`
  - Add small injectable protocol wrappers only if the runtime model needs test seams around sync.
- Modify: `CodexPoolManager/en.lproj/Localizable.strings`
- Modify: `CodexPoolManager/zh-Hant.lproj/Localizable.strings`
- Modify: `CodexPoolManager/zh-Hans.lproj/Localizable.strings`
- Modify: `CodexPoolManager/ja.lproj/Localizable.strings`
- Modify: `CodexPoolManager/ko.lproj/Localizable.strings`
- Modify: `CodexPoolManager/fr.lproj/Localizable.strings`
- Modify: `CodexPoolManager/es.lproj/Localizable.strings`
- Create: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`
- Create: `CodexPoolManagerTests/AppPoolRuntimeModelTests.swift`
- Modify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`
  - Add smoke coverage for the new popover view while retaining the existing legacy menu tests until the old menu is removed.

## Task 1: Add Menu Bar Presenter Tests

**Files:**
- Create: `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift`
- Create later in Task 2: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`

- [ ] **Step 1: Write the failing presenter tests**

Create `CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift` with this complete content:

```swift
import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct MenuBarDashboardPresenterTests {
    private func makeAccount(
        id: UUID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        name: String = "paid@example.com",
        usedUnits: Int = 20,
        quota: Int = 100,
        isPaid: Bool = true,
        weeklyResetAt: Date? = Date(timeIntervalSince1970: 1_800),
        fiveHourWindowResetAt: Date? = Date(timeIntervalSince1970: 1_200),
        fiveHourUsedPercent: Int? = 25,
        usageSyncError: String? = nil,
        isUsageSyncExcluded: Bool = false,
        credentialType: AccountCredentialType = .oauth
    ) -> AgentAccount {
        AgentAccount(
            id: id,
            name: name,
            usedUnits: usedUnits,
            quota: quota,
            resetAt: weeklyResetAt,
            isPaid: isPaid,
            lastSyncedAt: Date(timeIntervalSince1970: 1_000),
            chatGPTAccountID: "user-\(id.uuidString)",
            credentialType: credentialType,
            fiveHourWindowResetAt: fiveHourWindowResetAt,
            fiveHourUsedPercent: fiveHourUsedPercent,
            usageSyncError: usageSyncError,
            isUsageSyncExcluded: isUsageSyncExcluded
        )
    }

    @Test
    func presenterBuildsPaidActiveAccountSummary() {
        let activeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        var state = AccountPoolState(
            accounts: [
                makeAccount(id: activeID),
                makeAccount(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    name: "backup@example.com",
                    usedUnits: 80,
                    quota: 100,
                    isPaid: false
                )
            ],
            mode: .manual
        )
        state.markActiveAccountForSwitchLaunch(activeID, now: Date(timeIntervalSince1970: 1_010))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: nil,
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.title == "Codex w 80% · 5h 75% · 30s")
        #expect(snapshot.totalAccountsText == "2")
        #expect(snapshot.availableAccountsText == "2")
        #expect(snapshot.modeText == L10n.text("mode.manual"))
        #expect(snapshot.activeAccount?.name == "paid@example.com")
        #expect(snapshot.activeAccount?.weeklyRemainingText == "80%")
        #expect(snapshot.activeAccount?.fiveHourRemainingText == "75%")
        #expect(snapshot.accountRows.map(\\.name) == ["paid@example.com", "backup@example.com"])
    }

    @Test
    func presenterSurfacesWarningsWithoutCountingRelayAsHardFailure() {
        var state = AccountPoolState(
            accounts: [
                makeAccount(
                    name: "relay",
                    usedUnits: 0,
                    quota: 100,
                    isPaid: false,
                    usageSyncError: AgentAccount.relayUsageSyncUnavailableReason,
                    isUsageSyncExcluded: true,
                    credentialType: .relayAPIKey
                ),
                makeAccount(
                    id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                    name: "expired@example.com",
                    usedUnits: 90,
                    quota: 100,
                    isPaid: true,
                    usageSyncError: L10n.text("usage.sync.error.oauth_login_expired")
                )
            ],
            mode: .intelligent
        )
        state.evaluate(now: Date(timeIntervalSince1970: 1_000))

        let snapshot = MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: false,
            lastSyncError: "network offline",
            now: Date(timeIntervalSince1970: 1_030)
        )

        #expect(snapshot.warningRows.contains(where: { $0.kind == .relayUsageUnavailable }))
        #expect(snapshot.warningRows.contains(where: { $0.kind == .oauthExpired }))
        #expect(snapshot.warningRows.contains(where: { $0.kind == .syncFailed }))
        #expect(snapshot.accountRows.first?.credentialLabel == L10n.text("account.api_key_badge"))
    }
}
```

- [ ] **Step 2: Run the failing tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' -quiet
```

Expected: FAIL because `MenuBarDashboardPresenter` and the menu bar row models do not exist.

## Task 2: Implement Menu Bar Presenter

**Files:**
- Create: `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift`

- [ ] **Step 1: Add the presenter implementation**

Create `CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift` with this complete content:

```swift
import Foundation

struct MenuBarDashboardSnapshot: Equatable {
    let title: String
    let totalAccountsText: String
    let availableAccountsText: String
    let usageText: String
    let modeText: String
    let updatedText: String
    let activeAccount: MenuBarAccountRow?
    let accountRows: [MenuBarAccountRow]
    let warningRows: [MenuBarWarningRow]
    let isSyncing: Bool
    let lastSyncError: String?
}

struct MenuBarAccountRow: Identifiable, Equatable {
    let id: UUID
    let name: String
    let isActive: Bool
    let isPaid: Bool
    let credentialLabel: String?
    let weeklyRemainingText: String
    let fiveHourRemainingText: String?
    let resetText: String
    let warningText: String?
}

struct MenuBarWarningRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case oauthExpired
        case relayUsageUnavailable
        case syncFailed
        case excluded
    }

    let id: String
    let kind: Kind
    let title: String
    let message: String
}

enum MenuBarDashboardPresenter {
    static func makeSnapshot(
        from state: AccountPoolState,
        isSyncing: Bool,
        lastSyncError: String?,
        now: Date = Date()
    ) -> MenuBarDashboardSnapshot {
        let activeAccount = state.activeAccount
        let rows = state.accounts.map { account in
            makeAccountRow(
                account,
                activeAccountID: state.activeAccountID,
                now: now
            )
        }
        let availableCount = state.accounts.filter { $0.isAvailable }.count
        let totalQuota = state.accounts.reduce(0) { $0 + max(0, $1.quota) }
        let totalUsed = state.accounts.reduce(0) { $0 + max(0, $1.usedUnits) }
        let usedPercent = totalQuota > 0 ? Int((Double(totalUsed) / Double(totalQuota) * 100).rounded()) : 0

        let bridgeSnapshot = MenuBarBridgeSnapshot(
            updatedAt: activeAccount?.lastSyncedAt ?? now,
            activeAccountName: activeAccount?.name,
            activeIsPaid: activeAccount?.isPaid,
            activeRemainingUnits: activeAccount.map { max(0, $0.quota - $0.usedUnits) },
            activeQuota: activeAccount?.quota,
            activeFiveHourRemainingPercent: activeAccount?.fiveHourRemainingPercent,
            activeWeeklyResetAt: activeAccount?.resetAt,
            activeFiveHourResetAt: activeAccount?.fiveHourWindowResetAt
        )

        return MenuBarDashboardSnapshot(
            title: MenuBarSnapshotFormatter.menuBarTitle(snapshot: bridgeSnapshot, now: now),
            totalAccountsText: "\(state.accounts.count)",
            availableAccountsText: "\(availableCount)",
            usageText: "\(max(0, min(100, usedPercent)))%",
            modeText: modeText(state.mode),
            updatedText: updatedText(from: activeAccount?.lastSyncedAt, now: now),
            activeAccount: activeAccount.map {
                makeAccountRow($0, activeAccountID: state.activeAccountID, now: now)
            },
            accountRows: rows,
            warningRows: warningRows(
                accounts: state.accounts,
                lastSyncError: lastSyncError
            ),
            isSyncing: isSyncing,
            lastSyncError: lastSyncError
        )
    }

    private static func makeAccountRow(
        _ account: AgentAccount,
        activeAccountID: UUID?,
        now: Date
    ) -> MenuBarAccountRow {
        let remaining = max(0, account.quota - account.usedUnits)
        let weeklyPercent = account.quota > 0
            ? max(0, min(100, Int((Double(remaining) / Double(account.quota) * 100).rounded())))
            : 0

        return MenuBarAccountRow(
            id: account.id,
            name: account.name,
            isActive: account.id == activeAccountID,
            isPaid: account.isPaid,
            credentialLabel: credentialLabel(for: account),
            weeklyRemainingText: "\(weeklyPercent)%",
            fiveHourRemainingText: account.isPaid ? account.fiveHourRemainingPercent.map { "\($0)%" } : nil,
            resetText: resetText(for: account, now: now),
            warningText: account.usageSyncError?.isEmpty == false ? account.usageSyncError : nil
        )
    }

    private static func warningRows(
        accounts: [AgentAccount],
        lastSyncError: String?
    ) -> [MenuBarWarningRow] {
        var rows: [MenuBarWarningRow] = []
        if let lastSyncError,
           !lastSyncError.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            rows.append(MenuBarWarningRow(
                id: "sync-failed",
                kind: .syncFailed,
                title: L10n.text("menu_bar.warning.sync_failed.title"),
                message: lastSyncError
            ))
        }

        for account in accounts {
            if account.isRelayAPIKeyAccount {
                rows.append(MenuBarWarningRow(
                    id: "relay-\(account.id.uuidString)",
                    kind: .relayUsageUnavailable,
                    title: L10n.text("menu_bar.warning.relay_usage.title"),
                    message: L10n.text("menu_bar.warning.relay_usage.message")
                ))
            } else if account.usageSyncError == L10n.text("usage.sync.error.oauth_login_expired") {
                rows.append(MenuBarWarningRow(
                    id: "oauth-\(account.id.uuidString)",
                    kind: .oauthExpired,
                    title: L10n.text("menu_bar.warning.oauth_expired.title"),
                    message: L10n.text("menu_bar.warning.oauth_expired.message")
                ))
            } else if account.isUsageSyncExcluded {
                rows.append(MenuBarWarningRow(
                    id: "excluded-\(account.id.uuidString)",
                    kind: .excluded,
                    title: L10n.text("sync.excluded.title"),
                    message: account.usageSyncError ?? L10n.text("sync.excluded.default_message")
                ))
            }
        }
        return rows
    }

    private static func modeText(_ mode: SwitchMode) -> String {
        switch mode {
        case .manual: return L10n.text("mode.manual")
        case .intelligent: return L10n.text("mode.intelligent")
        case .focus: return L10n.text("mode.focus")
        }
    }

    private static func credentialLabel(for account: AgentAccount) -> String? {
        if account.isRelayAPIKeyAccount {
            return L10n.text("account.api_key_badge")
        }
        if account.isPaid {
            return L10n.text("account.paid_badge")
        }
        return nil
    }

    private static func resetText(for account: AgentAccount, now: Date) -> String {
        guard let date = account.isPaid ? account.fiveHourWindowResetAt ?? account.resetAt : account.resetAt else {
            return "--"
        }
        return shortRelativeText(until: date, now: now)
    }

    private static func updatedText(from date: Date?, now: Date) -> String {
        guard let date else { return L10n.text("menu_bar.updated.never") }
        return L10n.text("menu_bar.updated.format", MenuBarSnapshotFormatter.shortAgeText(since: date, now: now))
    }

    private static func shortRelativeText(until date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return L10n.text("menu_bar.reset.now") }
        if seconds < 3_600 { return L10n.text("menu_bar.reset.minutes_format", max(1, seconds / 60)) }
        if seconds < 86_400 { return L10n.text("menu_bar.reset.hours_format", max(1, seconds / 3_600)) }
        return L10n.text("menu_bar.reset.days_format", max(1, seconds / 86_400))
    }
}
```

- [ ] **Step 2: Add localization keys for presenter text**

Add these keys to all seven `Localizable.strings` files. Use the translations below exactly for this pass.

English, `CodexPoolManager/en.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "Never synced";
"menu_bar.updated.format" = "Updated %@ ago";
"menu_bar.reset.now" = "now";
"menu_bar.reset.minutes_format" = "%d min";
"menu_bar.reset.hours_format" = "%d hr";
"menu_bar.reset.days_format" = "%d d";
"menu_bar.warning.sync_failed.title" = "Sync failed";
"menu_bar.warning.relay_usage.title" = "Relay usage unavailable";
"menu_bar.warning.relay_usage.message" = "API key relay accounts can be switched manually, but usage sync is not available.";
"menu_bar.warning.oauth_expired.title" = "Login expired";
"menu_bar.warning.oauth_expired.message" = "Open the dashboard and sign in again to restore usage sync.";
"account.api_key_badge" = "API Key";
```

Traditional Chinese, `CodexPoolManager/zh-Hant.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "尚未同步";
"menu_bar.updated.format" = "%@ 前更新";
"menu_bar.reset.now" = "現在";
"menu_bar.reset.minutes_format" = "%d 分";
"menu_bar.reset.hours_format" = "%d 小時";
"menu_bar.reset.days_format" = "%d 天";
"menu_bar.warning.sync_failed.title" = "同步失敗";
"menu_bar.warning.relay_usage.title" = "中轉用量無法同步";
"menu_bar.warning.relay_usage.message" = "API key 中轉帳號可手動切換，但不支援用量同步。";
"menu_bar.warning.oauth_expired.title" = "登入已過期";
"menu_bar.warning.oauth_expired.message" = "請開啟主畫面並重新登入，以恢復用量同步。";
"account.api_key_badge" = "API Key";
```

Simplified Chinese, `CodexPoolManager/zh-Hans.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "尚未同步";
"menu_bar.updated.format" = "%@ 前更新";
"menu_bar.reset.now" = "现在";
"menu_bar.reset.minutes_format" = "%d 分";
"menu_bar.reset.hours_format" = "%d 小时";
"menu_bar.reset.days_format" = "%d 天";
"menu_bar.warning.sync_failed.title" = "同步失败";
"menu_bar.warning.relay_usage.title" = "中转用量无法同步";
"menu_bar.warning.relay_usage.message" = "API key 中转账号可手动切换，但不支持用量同步。";
"menu_bar.warning.oauth_expired.title" = "登录已过期";
"menu_bar.warning.oauth_expired.message" = "请打开主界面并重新登录，以恢复用量同步。";
"account.api_key_badge" = "API Key";
```

Japanese, `CodexPoolManager/ja.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "未同期";
"menu_bar.updated.format" = "%@ 前に更新";
"menu_bar.reset.now" = "今";
"menu_bar.reset.minutes_format" = "%d 分";
"menu_bar.reset.hours_format" = "%d 時間";
"menu_bar.reset.days_format" = "%d 日";
"menu_bar.warning.sync_failed.title" = "同期に失敗";
"menu_bar.warning.relay_usage.title" = "リレー使用量は同期不可";
"menu_bar.warning.relay_usage.message" = "API key リレーアカウントは手動切替できますが、使用量同期には対応していません。";
"menu_bar.warning.oauth_expired.title" = "ログイン期限切れ";
"menu_bar.warning.oauth_expired.message" = "ダッシュボードを開いて再ログインすると使用量同期が復旧します。";
"account.api_key_badge" = "API Key";
```

Korean, `CodexPoolManager/ko.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "아직 동기화 안 됨";
"menu_bar.updated.format" = "%@ 전에 업데이트됨";
"menu_bar.reset.now" = "지금";
"menu_bar.reset.minutes_format" = "%d분";
"menu_bar.reset.hours_format" = "%d시간";
"menu_bar.reset.days_format" = "%d일";
"menu_bar.warning.sync_failed.title" = "동기화 실패";
"menu_bar.warning.relay_usage.title" = "릴레이 사용량 동기화 불가";
"menu_bar.warning.relay_usage.message" = "API key 릴레이 계정은 수동 전환할 수 있지만 사용량 동기화는 지원하지 않습니다.";
"menu_bar.warning.oauth_expired.title" = "로그인 만료";
"menu_bar.warning.oauth_expired.message" = "대시보드를 열고 다시 로그인하면 사용량 동기화가 복구됩니다.";
"account.api_key_badge" = "API Key";
```

French, `CodexPoolManager/fr.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "Jamais synchronisé";
"menu_bar.updated.format" = "Mis à jour il y a %@";
"menu_bar.reset.now" = "maintenant";
"menu_bar.reset.minutes_format" = "%d min";
"menu_bar.reset.hours_format" = "%d h";
"menu_bar.reset.days_format" = "%d j";
"menu_bar.warning.sync_failed.title" = "Échec de la synchronisation";
"menu_bar.warning.relay_usage.title" = "Usage relais indisponible";
"menu_bar.warning.relay_usage.message" = "Les comptes relais API key peuvent être changés manuellement, mais la synchronisation d’usage n’est pas disponible.";
"menu_bar.warning.oauth_expired.title" = "Connexion expirée";
"menu_bar.warning.oauth_expired.message" = "Ouvrez le tableau de bord et reconnectez-vous pour rétablir la synchronisation.";
"account.api_key_badge" = "API Key";
```

Spanish, `CodexPoolManager/es.lproj/Localizable.strings`:

```text
"menu_bar.updated.never" = "Nunca sincronizado";
"menu_bar.updated.format" = "Actualizado hace %@";
"menu_bar.reset.now" = "ahora";
"menu_bar.reset.minutes_format" = "%d min";
"menu_bar.reset.hours_format" = "%d h";
"menu_bar.reset.days_format" = "%d d";
"menu_bar.warning.sync_failed.title" = "Error de sincronización";
"menu_bar.warning.relay_usage.title" = "Uso de relay no disponible";
"menu_bar.warning.relay_usage.message" = "Las cuentas relay con API key pueden cambiarse manualmente, pero no admiten sincronización de uso.";
"menu_bar.warning.oauth_expired.title" = "Inicio de sesión vencido";
"menu_bar.warning.oauth_expired.message" = "Abre el panel y vuelve a iniciar sesión para restaurar la sincronización.";
"account.api_key_badge" = "API Key";
```

- [ ] **Step 3: Run presenter tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' -quiet
```

Expected: PASS.

- [ ] **Step 4: Commit presenter slice**

```bash
git add CodexPoolManager/MenuBar/MenuBarDashboardPresenter.swift CodexPoolManagerTests/MenuBarDashboardPresenterTests.swift CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat(menu-bar): add dashboard presenter"
```

## Task 3: Add App Runtime Model Tests

**Files:**
- Create: `CodexPoolManagerTests/AppPoolRuntimeModelTests.swift`
- Create later in Task 4: `CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift`

- [ ] **Step 1: Write failing runtime model tests**

Create `CodexPoolManagerTests/AppPoolRuntimeModelTests.swift` with this complete content:

```swift
import Foundation
import Testing
@testable import CodexPoolManager

@MainActor
struct AppPoolRuntimeModelTests {
    final class SpyStore: AccountPoolStoring {
        var loadedSnapshot: AccountPoolSnapshot?
        var savedSnapshots: [AccountPoolSnapshot] = []
        var tokens: [UUID: String] = [:]

        func load() -> AccountPoolSnapshot? {
            loadedSnapshot
        }

        func save(_ snapshot: AccountPoolSnapshot) {
            savedSnapshots.append(snapshot)
            loadedSnapshot = snapshot
        }

        func removeToken(for accountID: UUID) {
            tokens[accountID] = nil
        }

        func apiToken(for accountID: UUID) -> String? {
            tokens[accountID]
        }
    }

    private func makeState(name: String = "alpha@example.com") -> AccountPoolState {
        let account = AgentAccount(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: name,
            usedUnits: 40,
            quota: 100,
            resetAt: Date(timeIntervalSince1970: 2_000),
            isPaid: true,
            lastSyncedAt: Date(timeIntervalSince1970: 1_000),
            chatGPTAccountID: "user-alpha",
            credentialType: .oauth,
            fiveHourWindowResetAt: Date(timeIntervalSince1970: 1_600),
            fiveHourUsedPercent: 30
        )
        var state = AccountPoolState(accounts: [account], mode: .manual)
        state.markActiveAccountForSwitchLaunch(account.id, now: Date(timeIntervalSince1970: 1_000))
        return state
    }

    @Test
    func loadUsesStoreSnapshotAndPublishesWidgetSnapshot() {
        let store = SpyStore()
        store.loadedSnapshot = makeState(name: "loaded@example.com").snapshot
        var publishedNames: [String] = []
        let model = AppPoolRuntimeModel(
            store: store,
            widgetPublisher: { snapshot in
                publishedNames.append(snapshot.accounts.first?.name ?? "")
            }
        )

        model.load()

        #expect(model.state.accounts.first?.name == "loaded@example.com")
        #expect(store.savedSnapshots.isEmpty)
        #expect(publishedNames == ["loaded@example.com"])
        #expect(model.menuBarSnapshot.activeAccount?.name == "loaded@example.com")
    }

    @Test
    func replaceFromDashboardSavesAndPublishesOnce() {
        let store = SpyStore()
        var publishedCount = 0
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "initial@example.com"),
            widgetPublisher: { _ in publishedCount += 1 }
        )

        model.replaceStateFromDashboard(makeState(name: "dashboard@example.com"))

        #expect(model.state.accounts.first?.name == "dashboard@example.com")
        #expect(store.savedSnapshots.count == 1)
        #expect(publishedCount == 1)
    }

    @Test
    func syncNowUsesInjectedRunnerAndSavesReturnedState() async {
        let store = SpyStore()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "before@example.com"),
            syncRunner: { state, viewState in
                _ = viewState
                var next = state
                let id = next.accounts[0].id
                next.updateUsage(for: id, usedUnits: 10, resetAt: Date(timeIntervalSince1970: 3_000))
                var nextViewState = PoolDashboardViewState()
                nextViewState.syncError = nil
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: next,
                    viewState: nextViewState
                )
            }
        )

        await model.syncNow()

        #expect(model.isSyncingUsage == false)
        #expect(model.lastSyncError == nil)
        #expect(model.state.accounts.first?.usedUnits == 10)
        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func syncNowStoresErrorWithoutDroppingPreviousState() async {
        let store = SpyStore()
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: makeState(name: "stable@example.com"),
            syncRunner: { state, _ in
                var nextViewState = PoolDashboardViewState()
                nextViewState.syncError = "offline"
                return PoolDashboardUsageSyncFlowCoordinator.Output(
                    state: state,
                    viewState: nextViewState
                )
            }
        )

        await model.syncNow()

        #expect(model.lastSyncError == "offline")
        #expect(model.state.accounts.first?.name == "stable@example.com")
        #expect(store.savedSnapshots.count == 1)
    }
}
```

- [ ] **Step 2: Run failing runtime tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests' -quiet
```

Expected: FAIL because `AppPoolRuntimeModel` does not exist.

## Task 4: Implement App Runtime Model

**Files:**
- Create: `CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift`

- [ ] **Step 1: Add the runtime model**

Create `CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift` with this complete content:

```swift
import Foundation

@MainActor
final class AppPoolRuntimeModel: ObservableObject {
    typealias SyncRunner = @MainActor (
        _ state: AccountPoolState,
        _ viewState: PoolDashboardViewState
    ) async -> PoolDashboardUsageSyncFlowCoordinator.Output
    typealias WidgetPublisher = @MainActor (_ snapshot: AccountPoolSnapshot) -> Void

    @Published private(set) var state: AccountPoolState
    @Published private(set) var isSyncingUsage = false
    @Published private(set) var lastSyncError: String?
    @Published private(set) var lastSwitchMessage: String?

    private let store: AccountPoolStoring
    private let syncRunner: SyncRunner
    private let widgetPublisher: WidgetPublisher
    private var autoSyncTask: Task<Void, Never>?

    var menuBarSnapshot: MenuBarDashboardSnapshot {
        MenuBarDashboardPresenter.makeSnapshot(
            from: state,
            isSyncing: isSyncingUsage,
            lastSyncError: lastSyncError
        )
    }

    init(
        store: AccountPoolStoring = AppRuntimeStorage.accountPoolStore,
        initialState: AccountPoolState? = nil,
        syncRunner: SyncRunner? = nil,
        widgetPublisher: @escaping WidgetPublisher = { WidgetBridgePublisher.publish(from: $0) }
    ) {
        self.store = store
        if let initialState {
            self.state = initialState
        } else if let snapshot = store.load() {
            self.state = AccountPoolState(snapshot: snapshot)
        } else {
            var emptyState = AccountPoolState(accounts: [], mode: .intelligent)
            emptyState.evaluate(now: .now)
            self.state = emptyState
        }
        self.syncRunner = syncRunner ?? { state, viewState in
            await PoolDashboardUsageSyncFlowCoordinator().syncCodexUsage(
                from: state,
                viewState: viewState
            )
        }
        self.widgetPublisher = widgetPublisher
    }

    deinit {
        autoSyncTask?.cancel()
    }

    func load() {
        if let snapshot = store.load() {
            state = AccountPoolState(snapshot: snapshot)
        }
        publishWidgetSnapshot()
    }

    func replaceStateFromDashboard(_ nextState: AccountPoolState) {
        state = nextState
        saveAndPublish()
    }

    func startAutoSyncIfNeeded() {
        guard autoSyncTask == nil else { return }
        guard state.autoSyncEnabled else { return }
        autoSyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.syncNow()
            while !Task.isCancelled {
                let seconds = max(15, self.state.autoSyncIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { break }
                await self.syncNow()
            }
        }
    }

    func stopAutoSync() {
        autoSyncTask?.cancel()
        autoSyncTask = nil
    }

    func restartAutoSyncIfNeeded() {
        stopAutoSync()
        startAutoSyncIfNeeded()
    }

    func syncNow() async {
        guard !isSyncingUsage else { return }
        isSyncingUsage = true
        defer { isSyncingUsage = false }

        let output = await syncRunner(state, PoolDashboardViewState())
        state = output.state
        let error = output.viewState.syncError?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastSyncError = error?.isEmpty == false ? error : nil
        saveAndPublish()
    }

    func saveAndPublish() {
        store.save(state.snapshot)
        publishWidgetSnapshot()
    }

    private func publishWidgetSnapshot() {
        widgetPublisher(state.snapshot)
    }
}
```

- [ ] **Step 2: Run runtime tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests' -quiet
```

Expected: PASS.

- [ ] **Step 3: Run existing menu bar formatter tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarSnapshotFormatterTests' -quiet
```

Expected: PASS.

- [ ] **Step 4: Commit runtime model slice**

```bash
git add CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift CodexPoolManagerTests/AppPoolRuntimeModelTests.swift
git commit -m "feat(menu-bar): add shared pool runtime model"
```

## Task 5: Wire App Runtime Into App and Dashboard

**Files:**
- Modify: `CodexPoolManager/CodexPoolManagerApp.swift`
- Modify: `ContentView.swift`
- Modify: `Features/PoolDashboard/PoolDashboardView.swift`
- Modify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Update `ContentView` to accept runtime model**

Change `ContentView.swift` to this complete content:

```swift
import SwiftUI

struct ContentView: View {
    @ObservedObject var runtimeModel: AppPoolRuntimeModel

    var body: some View {
        if AppRuntimeStorage.isRunningXCTest {
            PoolDashboardView(
                store: AppRuntimeStorage.accountPoolStore,
                runtimeModel: runtimeModel
            )
        } else {
            PoolDashboardView(runtimeModel: runtimeModel)
        }
    }
}

#Preview {
    let store = UserDefaultsAccountPoolStore(
        defaults: .standard,
        key: "preview_account_pool_snapshot"
    )
    let model = AppPoolRuntimeModel(store: store)
    PoolDashboardView(store: store, runtimeModel: model)
}
```

- [ ] **Step 2: Update `PoolDashboardView` initializer and runtime storage**

In `Features/PoolDashboard/PoolDashboardView.swift`, add this property next to `private let store`:

```swift
    private let runtimeModel: AppPoolRuntimeModel?
```

Replace the existing initializer with:

```swift
    init(
        store: AccountPoolStoring = DeveloperAwareAccountPoolStore(),
        runtimeModel: AppPoolRuntimeModel? = nil
    ) {
        self.store = store
        self.runtimeModel = runtimeModel
        if let runtimeModel {
            _state = State(initialValue: runtimeModel.state)
        } else if let snapshot = store.load() {
            _state = State(initialValue: AccountPoolState(snapshot: snapshot))
        } else {
            var defaultState = Self.makeDefaultState(accounts: Self.defaultAccounts)
            defaultState.evaluate(now: .now)
            _state = State(initialValue: defaultState)
        }
    }
```

- [ ] **Step 3: Disable duplicate dashboard auto-sync when runtime exists**

Replace the dashboard auto-sync task body:

```swift
        .task(id: autoSyncTaskID) {
            guard state.autoSyncEnabled else { return }
            await syncCodexUsage()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(state.autoSyncIntervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await syncCodexUsage()
            }
        }
```

with:

```swift
        .task(id: autoSyncTaskID) {
            guard runtimeModel == nil else { return }
            guard state.autoSyncEnabled else { return }
            await syncCodexUsage()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(state.autoSyncIntervalSeconds * 1_000_000_000))
                if Task.isCancelled { break }
                await syncCodexUsage()
            }
        }
```

- [ ] **Step 4: Mirror dashboard snapshot changes into runtime**

At the end of `handleSnapshotChange(_:)`, after `applyLifecycleSnapshotChangeOutput(output)`, add:

```swift
        runtimeModel?.replaceStateFromDashboard(state)
```

- [ ] **Step 5: Let runtime sync button path update dashboard state**

At the top of `syncCodexUsage()`, before `guard asyncStateCoordinator.beginUsageSync`, add:

```swift
        if let runtimeModel {
            await runtimeModel.syncNow()
            state = runtimeModel.state
            viewState.syncError = runtimeModel.lastSyncError
            return
        }
```

- [ ] **Step 6: Update `CodexPoolManagerApp` to own the runtime model**

Replace `@StateObject private var menuBarModel = MenuBarSnapshotModel()` with:

```swift
    @StateObject private var runtimeModel = AppPoolRuntimeModel()
```

Replace the `WindowGroup` block:

```swift
        WindowGroup {
            ContentView()
                .id(appLanguageOverride)
                .environment(\.locale, L10n.locale(for: appLanguageOverride))
        }
```

with:

```swift
        WindowGroup("Dashboard", id: "dashboard") {
            ContentView(runtimeModel: runtimeModel)
                .id(appLanguageOverride)
                .environment(\.locale, L10n.locale(for: appLanguageOverride))
                .task {
                    runtimeModel.load()
                    runtimeModel.startAutoSyncIfNeeded()
                }
        }
```

Keep the old `MenuBarExtra` for this task. Task 6 replaces the UI.

- [ ] **Step 7: Add dashboard smoke test for runtime injection**

In `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`, add this test near the existing dashboard smoke tests:

```swift
    @MainActor
    @Test
    func poolDashboardAcceptsSharedRuntimeModel() {
        let account = AgentAccount(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "runtime@example.com",
            usedUnits: 10,
            quota: 100
        )
        let state = AccountPoolState(accounts: [account], mode: .manual)
        let store = ViewSmokeStore(snapshot: state.snapshot)
        let model = AppPoolRuntimeModel(store: store, initialState: state)

        _ = PoolDashboardView(store: store, runtimeModel: model)
    }
```

- [ ] **Step 8: Run wiring tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/poolDashboardAcceptsSharedRuntimeModel()' -quiet
```

Expected: PASS.

- [ ] **Step 9: Commit wiring slice**

```bash
git add CodexPoolManager/CodexPoolManagerApp.swift ContentView.swift Features/PoolDashboard/PoolDashboardView.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift
git commit -m "feat(menu-bar): share runtime state with dashboard"
```

## Task 6: Build Rich Menu Bar Window UI

**Files:**
- Create: `CodexPoolManager/MenuBar/MenuBarDashboardView.swift`
- Modify: `CodexPoolManager/CodexPoolManagerApp.swift`
- Modify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`
- Modify: all seven `Localizable.strings` files

- [ ] **Step 1: Add menu bar UI localization keys**

Add these keys to every locale file with matching translations:

English:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "Menu bar dashboard";
"menu_bar.action.sync_now" = "Sync Now";
"menu_bar.action.open_dashboard" = "Open Dashboard";
"menu_bar.action.switch" = "Switch";
"menu_bar.summary.accounts" = "Accounts";
"menu_bar.summary.available" = "Available";
"menu_bar.summary.usage" = "Usage";
"menu_bar.summary.mode" = "Mode";
"menu_bar.section.active" = "Active Account";
"menu_bar.section.accounts" = "Accounts";
"menu_bar.section.warnings" = "Needs Attention";
"menu_bar.empty.title" = "No accounts yet";
"menu_bar.empty.message" = "Open the dashboard to import or add an account.";
```

Traditional Chinese:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "選單列儀表板";
"menu_bar.action.sync_now" = "立即同步";
"menu_bar.action.open_dashboard" = "開啟主畫面";
"menu_bar.action.switch" = "切換";
"menu_bar.summary.accounts" = "帳號";
"menu_bar.summary.available" = "可用";
"menu_bar.summary.usage" = "用量";
"menu_bar.summary.mode" = "模式";
"menu_bar.section.active" = "目前帳號";
"menu_bar.section.accounts" = "帳號";
"menu_bar.section.warnings" = "需要注意";
"menu_bar.empty.title" = "尚未加入帳號";
"menu_bar.empty.message" = "開啟主畫面以匯入或新增帳號。";
```

Simplified Chinese:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "菜单栏仪表板";
"menu_bar.action.sync_now" = "立即同步";
"menu_bar.action.open_dashboard" = "打开主界面";
"menu_bar.action.switch" = "切换";
"menu_bar.summary.accounts" = "账号";
"menu_bar.summary.available" = "可用";
"menu_bar.summary.usage" = "用量";
"menu_bar.summary.mode" = "模式";
"menu_bar.section.active" = "当前账号";
"menu_bar.section.accounts" = "账号";
"menu_bar.section.warnings" = "需要注意";
"menu_bar.empty.title" = "尚未添加账号";
"menu_bar.empty.message" = "打开主界面以导入或添加账号。";
```

Japanese:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "メニューバーダッシュボード";
"menu_bar.action.sync_now" = "今すぐ同期";
"menu_bar.action.open_dashboard" = "ダッシュボードを開く";
"menu_bar.action.switch" = "切替";
"menu_bar.summary.accounts" = "アカウント";
"menu_bar.summary.available" = "利用可能";
"menu_bar.summary.usage" = "使用量";
"menu_bar.summary.mode" = "モード";
"menu_bar.section.active" = "現在のアカウント";
"menu_bar.section.accounts" = "アカウント";
"menu_bar.section.warnings" = "要確認";
"menu_bar.empty.title" = "アカウント未追加";
"menu_bar.empty.message" = "ダッシュボードを開いてアカウントをインポートまたは追加してください。";
```

Korean:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "메뉴 막대 대시보드";
"menu_bar.action.sync_now" = "지금 동기화";
"menu_bar.action.open_dashboard" = "대시보드 열기";
"menu_bar.action.switch" = "전환";
"menu_bar.summary.accounts" = "계정";
"menu_bar.summary.available" = "사용 가능";
"menu_bar.summary.usage" = "사용량";
"menu_bar.summary.mode" = "모드";
"menu_bar.section.active" = "현재 계정";
"menu_bar.section.accounts" = "계정";
"menu_bar.section.warnings" = "확인 필요";
"menu_bar.empty.title" = "계정 없음";
"menu_bar.empty.message" = "대시보드를 열어 계정을 가져오거나 추가하세요.";
```

French:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "Tableau de bord menu bar";
"menu_bar.action.sync_now" = "Synchroniser";
"menu_bar.action.open_dashboard" = "Ouvrir le tableau";
"menu_bar.action.switch" = "Changer";
"menu_bar.summary.accounts" = "Comptes";
"menu_bar.summary.available" = "Disponibles";
"menu_bar.summary.usage" = "Usage";
"menu_bar.summary.mode" = "Mode";
"menu_bar.section.active" = "Compte actif";
"menu_bar.section.accounts" = "Comptes";
"menu_bar.section.warnings" = "À vérifier";
"menu_bar.empty.title" = "Aucun compte";
"menu_bar.empty.message" = "Ouvrez le tableau pour importer ou ajouter un compte.";
```

Spanish:

```text
"menu_bar.header.title" = "Codex Pool";
"menu_bar.header.subtitle" = "Panel de barra de menús";
"menu_bar.action.sync_now" = "Sincronizar";
"menu_bar.action.open_dashboard" = "Abrir panel";
"menu_bar.action.switch" = "Cambiar";
"menu_bar.summary.accounts" = "Cuentas";
"menu_bar.summary.available" = "Disponibles";
"menu_bar.summary.usage" = "Uso";
"menu_bar.summary.mode" = "Modo";
"menu_bar.section.active" = "Cuenta activa";
"menu_bar.section.accounts" = "Cuentas";
"menu_bar.section.warnings" = "Revisar";
"menu_bar.empty.title" = "Sin cuentas";
"menu_bar.empty.message" = "Abre el panel para importar o agregar una cuenta.";
```

- [ ] **Step 2: Add the menu bar view**

Create `CodexPoolManager/MenuBar/MenuBarDashboardView.swift` with this complete content:

```swift
import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var runtimeModel: AppPoolRuntimeModel
    let openDashboard: () -> Void
    let switchAccount: (UUID) -> Void

    private var snapshot: MenuBarDashboardSnapshot {
        runtimeModel.menuBarSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryGrid

            if let activeAccount = snapshot.activeAccount {
                sectionTitle(L10n.text("menu_bar.section.active"))
                accountRow(activeAccount, prominent: true)
            } else {
                emptyState
            }

            if !snapshot.warningRows.isEmpty {
                sectionTitle(L10n.text("menu_bar.section.warnings"))
                ForEach(snapshot.warningRows) { warning in
                    warningRow(warning)
                }
            }

            if !snapshot.accountRows.isEmpty {
                sectionTitle(L10n.text("menu_bar.section.accounts"))
                ForEach(snapshot.accountRows) { row in
                    accountRow(row, prominent: false)
                }
            }
        }
        .padding(16)
        .frame(width: 410, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("menu_bar.header.title"))
                    .font(.headline)
                Text(snapshot.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await runtimeModel.syncNow() }
            } label: {
                Label(L10n.text("menu_bar.action.sync_now"), systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(snapshot.isSyncing)
            Button {
                openDashboard()
            } label: {
                Label(L10n.text("menu_bar.action.open_dashboard"), systemImage: "macwindow")
            }
        }
    }

    private var summaryGrid: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                summaryTile(L10n.text("menu_bar.summary.accounts"), snapshot.totalAccountsText, "person.2")
                summaryTile(L10n.text("menu_bar.summary.available"), snapshot.availableAccountsText, "checkmark.circle")
            }
            GridRow {
                summaryTile(L10n.text("menu_bar.summary.usage"), snapshot.usageText, "gauge.medium")
                summaryTile(L10n.text("menu_bar.summary.mode"), snapshot.modeText, "dial.medium")
            }
        }
    }

    private func summaryTile(_ label: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("menu_bar.empty.title"))
                .font(.callout.weight(.semibold))
            Text(L10n.text("menu_bar.empty.message"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func accountRow(_ row: MenuBarAccountRow, prominent: Bool) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(prominent ? .callout.weight(.semibold) : .caption.weight(.semibold))
                        .lineLimit(1)
                    if row.isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    if let credentialLabel = row.credentialLabel {
                        Text(credentialLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.15), in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text("W \(row.weeklyRemainingText)")
                    if let fiveHourRemainingText = row.fiveHourRemainingText {
                        Text("5h \(fiveHourRemainingText)")
                    }
                    Text(row.resetText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .monospacedDigit()
                if let warningText = row.warningText {
                    Text(warningText)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button(L10n.text("menu_bar.action.switch")) {
                switchAccount(row.id)
            }
            .disabled(row.isActive)
        }
        .padding(10)
        .background(
            row.isActive ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private func warningRow(_ warning: MenuBarWarningRow) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title)
                    .font(.caption.weight(.semibold))
                Text(warning.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
```

- [ ] **Step 3: Replace `MenuBarExtra` with rich window style**

In `CodexPoolManager/CodexPoolManagerApp.swift`, add:

```swift
    @Environment(\.openWindow) private var openWindow
```

Replace the `MenuBarExtra` block with:

```swift
        MenuBarExtra {
            MenuBarDashboardView(
                runtimeModel: runtimeModel,
                openDashboard: {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                },
                switchAccount: { accountID in
                    Task { @MainActor in
                        await runtimeModel.switchAccount(accountID)
                    }
                }
            )
            .environment(\.locale, L10n.locale(for: appLanguageOverride))
        } label: {
            Text(runtimeModel.menuBarSnapshot.title)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
```

The call to `runtimeModel.switchAccount(_:)` is added in Task 7. For this task, add this temporary method to `AppPoolRuntimeModel` so the build remains green:

```swift
    func switchAccount(_ accountID: UUID) async {
        guard state.accounts.contains(where: { $0.id == accountID }) else { return }
        state.markActiveAccountForSwitchLaunch(accountID)
        saveAndPublish()
    }
```

Task 7 replaces the temporary method body with real existing coordinator calls.

- [ ] **Step 4: Add view smoke test**

In `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`, add:

```swift
    @MainActor
    @Test
    func richMenuBarDashboardViewRendersWithRuntimeModel() {
        let account = AgentAccount(
            id: UUID(uuidString: "ABCDEFAB-CDEF-CDEF-CDEF-ABCDEFABCDEF")!,
            name: "menu@example.com",
            usedUnits: 10,
            quota: 100,
            resetAt: Date(timeIntervalSince1970: 2_000),
            isPaid: true,
            lastSyncedAt: Date(timeIntervalSince1970: 1_000),
            chatGPTAccountID: "user-menu",
            credentialType: .oauth,
            fiveHourWindowResetAt: Date(timeIntervalSince1970: 1_600),
            fiveHourUsedPercent: 20
        )
        var state = AccountPoolState(accounts: [account], mode: .manual)
        state.markActiveAccountForSwitchLaunch(account.id)
        let model = AppPoolRuntimeModel(initialState: state)
        _ = MenuBarDashboardView(
            runtimeModel: model,
            openDashboard: {},
            switchAccount: { _ in }
        )
    }
```

- [ ] **Step 5: Run menu bar view smoke test and presenter tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardViewRendersWithRuntimeModel()' -quiet
```

Expected: PASS.

- [ ] **Step 6: Commit menu bar UI slice**

```bash
git add CodexPoolManager/CodexPoolManagerApp.swift CodexPoolManager/MenuBar/MenuBarDashboardView.swift CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift CodexPoolManager/*.lproj/Localizable.strings
git commit -m "feat(menu-bar): render rich dashboard popover"
```

## Task 7: Add Real Menu Bar Account Switching

**Files:**
- Modify: `CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift`
- Modify: `CodexPoolManagerTests/AppPoolRuntimeModelTests.swift`

- [ ] **Step 1: Add failing switching tests**

Append these tests to `AppPoolRuntimeModelTests`:

```swift
    @Test
    func switchAccountMarksOfficialAccountActiveAfterSuccessfulSwitch() async {
        let store = SpyStore()
        let account = AgentAccount(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "official@example.com",
            usedUnits: 20,
            quota: 100,
            apiToken: "access-token",
            chatGPTAccountID: "user-official",
            credentialType: .oauth
        )
        let model = AppPoolRuntimeModel(
            store: store,
            initialState: AccountPoolState(accounts: [account], mode: .manual),
            officialSwitchRunner: { request in
                #expect(request.account.id == account.id)
                return .success("official switched")
            },
            relaySwitchRunner: { _ in
                Issue.record("relay runner must not be used for an OAuth account")
                return .failure("wrong runner")
            }
        )

        await model.switchAccount(account.id)

        #expect(model.state.activeAccountID == account.id)
        #expect(model.lastSwitchMessage == "official switched")
        #expect(store.savedSnapshots.count == 1)
    }

    @Test
    func switchAccountUsesRelayRunnerForRelayAccount() async {
        let relayID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let account = AgentAccount(
            id: relayID,
            name: "relay",
            usedUnits: 0,
            quota: 100,
            apiToken: "relay-key",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://relay.example.test/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true,
            isUsageSyncExcluded: true,
            usageSyncError: AgentAccount.relayUsageSyncUnavailableReason
        )
        let model = AppPoolRuntimeModel(
            initialState: AccountPoolState(accounts: [account], mode: .manual),
            officialSwitchRunner: { _ in
                Issue.record("official runner must not be used for relay account")
                return .failure("wrong runner")
            },
            relaySwitchRunner: { request in
                #expect(request.accountID == relayID)
                #expect(request.apiKey == "relay-key")
                return .success("relay switched")
            }
        )

        await model.switchAccount(relayID)

        #expect(model.state.activeAccountID == relayID)
        #expect(model.lastSwitchMessage == "relay switched")
    }
```

- [ ] **Step 2: Run failing switch tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests/switchAccountMarksOfficialAccountActiveAfterSuccessfulSwitch()' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests/switchAccountUsesRelayRunnerForRelayAccount()' -quiet
```

Expected: FAIL because `officialSwitchRunner` and `relaySwitchRunner` injection points do not exist.

- [ ] **Step 3: Add switch result and request types**

In `AppPoolRuntimeModel.swift`, add these nested types inside `AppPoolRuntimeModel`:

```swift
    struct OfficialSwitchRequest {
        let account: AgentAccount
        let switchWithoutLaunching: Bool
        let launchTarget: CodexLaunchTarget
    }

    enum SwitchResult: Equatable {
        case success(String)
        case failure(String)
    }

    typealias OfficialSwitchRunner = @MainActor (_ request: OfficialSwitchRequest) async -> SwitchResult
    typealias RelaySwitchRunner = @MainActor (_ request: PoolDashboardRelayAccountCoordinator.SwitchRequest) async -> SwitchResult
```

- [ ] **Step 4: Add production switch dependencies**

Add these stored properties:

```swift
    private let officialSwitchRunner: OfficialSwitchRunner
    private let relaySwitchRunner: RelaySwitchRunner
    private let defaults: UserDefaults
```

Extend the initializer signature:

```swift
        officialSwitchRunner: OfficialSwitchRunner? = nil,
        relaySwitchRunner: RelaySwitchRunner? = nil,
        defaults: UserDefaults = AppRuntimeStorage.defaults,
```

Set the stored properties in the initializer:

```swift
        self.defaults = defaults
        self.officialSwitchRunner = officialSwitchRunner ?? Self.makeOfficialSwitchRunner()
        self.relaySwitchRunner = relaySwitchRunner ?? Self.makeRelaySwitchRunner()
```

Add these production runner factories:

```swift
    private static func makeOfficialSwitchRunner() -> OfficialSwitchRunner {
        { request in
            var viewState = PoolDashboardViewState()
            let output = await PoolDashboardSwitchLaunchFlowCoordinator().switchAndLaunch(
                using: request.account,
                switchWithoutLaunching: request.switchWithoutLaunching,
                launchTarget: request.launchTarget,
                currentAuthorizedAuthFileURL: nil,
                authFileAccessService: CodexAuthFileAccessService(bookmarkKey: "codex_auth_json_bookmark"),
                viewModel: LocalOAuthImportViewModel(),
                viewState: viewState,
                authorizeAuthFile: {
                    CodexAuthFilePanelService().pickAuthFileURL()
                }
            )
            viewState = output.viewState
            if output.didSwitchAuth {
                return .success(viewState.lastSwitchLaunchLog)
            }
            return .failure(viewState.switchLaunchError ?? L10n.text("switch.error.prefix"))
        }
    }

    private static func makeRelaySwitchRunner() -> RelaySwitchRunner {
        { request in
            let output = await PoolDashboardRelayAccountCoordinator().switchToRelayAccount(
                request,
                switchWithoutLaunching: false,
                preserveOfficialAuth: false,
                launchTarget: .auto,
                diagnosticLog: nil,
                viewState: PoolDashboardViewState()
            )
            if output.didSwitchAuth {
                return .success(output.viewState.lastSwitchLaunchLog)
            }
            return .failure(output.viewState.switchLaunchError ?? L10n.text("relay.switch.failed_format", ""))
        }
    }
```

- [ ] **Step 5: Replace temporary `switchAccount(_:)` body**

Replace the temporary method with:

```swift
    func switchAccount(_ accountID: UUID) async {
        guard let account = state.accounts.first(where: { $0.id == accountID }) else { return }
        let result: SwitchResult
        if account.isRelayAPIKeyAccount {
            do {
                let request = try PoolDashboardRelayAccountCoordinator.SwitchRequest(
                    account: account,
                    fallbackAPIKey: store.apiToken(for: accountID)
                )
                result = await relaySwitchRunner(request)
            } catch {
                result = .failure(error.localizedDescription)
            }
        } else {
            let launchTarget = CodexLaunchTarget(
                rawValue: CodexLaunchTarget.normalizedRawValue(
                    defaults.string(forKey: "pool_dashboard.switch_launch_target") ?? CodexLaunchTarget.defaultPickerTarget.rawValue
                )
            ) ?? .auto
            result = await officialSwitchRunner(OfficialSwitchRequest(
                account: account,
                switchWithoutLaunching: state.switchWithoutLaunching,
                launchTarget: launchTarget
            ))
        }

        switch result {
        case .success(let message):
            state.markActiveAccountForSwitchLaunch(accountID)
            lastSwitchMessage = message
            saveAndPublish()
        case .failure(let message):
            lastSwitchMessage = message
        }
    }
```

- [ ] **Step 6: Run switching tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests/switchAccountMarksOfficialAccountActiveAfterSuccessfulSwitch()' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests/switchAccountUsesRelayRunnerForRelayAccount()' -quiet
```

Expected: PASS.

- [ ] **Step 7: Commit switching slice**

```bash
git add CodexPoolManager/AppRuntime/AppPoolRuntimeModel.swift CodexPoolManagerTests/AppPoolRuntimeModelTests.swift
git commit -m "feat(menu-bar): switch accounts from popover"
```

## Task 8: Remove Legacy Menu Polling Model

**Files:**
- Modify: `CodexPoolManager/CodexPoolManagerApp.swift`
- Modify: `CodexPoolManagerTests/CoverageBoostTests.swift`
- Modify: `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`

- [ ] **Step 1: Remove old model and simple menu view**

In `CodexPoolManager/CodexPoolManagerApp.swift`, delete these types after all tests have been migrated:

```swift
@MainActor
private final class MenuBarSnapshotModel: ObservableObject
private struct MenuBarStatusMenuView: View
```

Keep `MenuBarBridgeSnapshot` and `MenuBarSnapshotFormatter` because `MenuBarDashboardPresenter` still uses them to compute the compact menu title.

- [ ] **Step 2: Replace old debug menu test helpers**

In the `#if DEBUG` extension of `CodexPoolManagerApp`, delete:

```swift
    @MainActor
    static func debugMenuBarStatusMenuView(snapshot: MenuBarBridgeSnapshot?) -> some View {
        MenuBarStatusMenuView(model: MenuBarSnapshotModel(debugSnapshot: snapshot))
    }
```

Keep:

```swift
    static func debugMenuBarTitle(snapshot: MenuBarBridgeSnapshot?, now: Date = Date()) -> String {
        MenuBarSnapshotFormatter.menuBarTitle(snapshot: snapshot, now: now)
    }
```

- [ ] **Step 3: Remove old smoke test references**

In `CodexPoolManagerTests/ViewSmokeCoverageTests.swift`, remove only the lines that call:

```swift
CodexPoolManagerApp.debugMenuBarStatusMenuView(snapshot:)
```

Keep the assertions that call:

```swift
CodexPoolManagerApp.debugMenuBarTitle(snapshot:now:)
```

- [ ] **Step 4: Run formatter and smoke tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarSnapshotFormatterTests' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardViewRendersWithRuntimeModel()' -quiet
```

Expected: PASS.

- [ ] **Step 5: Commit cleanup slice**

```bash
git add CodexPoolManager/CodexPoolManagerApp.swift CodexPoolManagerTests/CoverageBoostTests.swift CodexPoolManagerTests/ViewSmokeCoverageTests.swift
git commit -m "refactor(menu-bar): remove legacy polling menu"
```

## Task 9: Full Verification and Manual QA

**Files:**
- No new files.

- [ ] **Step 1: Run all targeted menu bar tests**

Run:

```bash
xcodebuild test -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' '-only-testing:CodexPoolManagerTests/MenuBarDashboardPresenterTests' '-only-testing:CodexPoolManagerTests/AppPoolRuntimeModelTests' '-only-testing:CodexPoolManagerTests/MenuBarSnapshotFormatterTests' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/richMenuBarDashboardViewRendersWithRuntimeModel()' '-only-testing:CodexPoolManagerTests/ViewSmokeCoverageTests/poolDashboardAcceptsSharedRuntimeModel()' -quiet
```

Expected: PASS.

- [ ] **Step 2: Run app build**

Run:

```bash
xcodebuild build -project CodexPoolManager.xcodeproj -scheme CodexPoolManager -destination 'platform=macOS' -quiet
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Run localization key check**

Run:

```bash
python3 - <<'PY'
from pathlib import Path
root = Path("CodexPoolManager")
langs = ["en", "zh-Hant", "zh-Hans", "ja", "ko", "fr", "es"]
def keys(path):
    out = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if line.startswith('"') and '" =' in line:
            out.add(line.split('"', 2)[1])
    return out
all_keys = {lang: keys(root / f"{lang}.lproj" / "Localizable.strings") for lang in langs}
base = all_keys["en"]
for lang in langs[1:]:
    missing = sorted(base - all_keys[lang])
    extra = sorted(all_keys[lang] - base)
    if missing or extra:
        print(f"{lang}: missing={missing} extra={extra}")
        raise SystemExit(1)
print("localization keys aligned")
PY
```

Expected: `localization keys aligned`.

- [ ] **Step 4: Manual QA on macOS**

Run the app from Xcode or:

```bash
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/CodexPoolManager.app
```

Verify these exact behaviors:

- The Dock icon remains visible.
- The menu bar title shows `Codex` plus active usage data.
- Closing the main window does not remove the menu bar item.
- Clicking the menu bar item shows the rich popover.
- `Open Dashboard` reopens or focuses the dashboard.
- `Sync Now` disables while syncing and updates account rows after completion.
- Switching an OAuth account from the menu bar uses the same auth file path and launch behavior as the dashboard.
- Switching a relay API key account from the menu bar uses the same relay config/login behavior as the dashboard.
- Relay accounts show usage unavailable as an informational warning, not as a hard crash or red alert.
- Traditional Chinese strings fit inside the 410 px popover width.

- [ ] **Step 5: Commit final verification note if docs are changed**

If manual QA reveals no code changes, do not create an empty commit. If a release note or QA note is added, commit it:

```bash
git add docs
git commit -m "docs(menu-bar): record menu bar dashboard QA"
```

## Self-Review

- Spec coverage:
  - Shared app-level model is covered in Tasks 3-5.
  - Menu bar `.window` popover is covered in Task 6.
  - Background sync owned by app-level runtime is covered in Tasks 4-5.
  - Opening the dashboard through a named `WindowGroup` is covered in Task 5 and Task 6.
  - Account switching from menu bar is covered in Task 7 using existing switch coordinators.
  - Localization is covered in Task 2, Task 6, and Task 9.
  - Manual QA for close-window behavior is covered in Task 9.
- Placeholder scan:
  - The plan contains no unfinished markers and no unnamed tests.
  - Every code-changing task contains concrete code snippets or exact replacement blocks.
- Type consistency:
  - `AppPoolRuntimeModel.menuBarSnapshot` uses `MenuBarDashboardPresenter.makeSnapshot`.
  - `MenuBarDashboardView` calls `runtimeModel.syncNow()` and `runtimeModel.switchAccount(_:)`; both are defined by Task 6 or Task 7.
  - `ContentView(runtimeModel:)` passes the same runtime model into `PoolDashboardView`.

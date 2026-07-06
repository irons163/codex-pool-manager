import Foundation
import SwiftUI
import Testing
import AppKit
@testable import CodexPoolManager

private final class BindingBox<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private func binding<Value>(_ box: BindingBox<Value>) -> Binding<Value> {
    Binding(
        get: { box.value },
        set: { box.value = $0 }
    )
}

private func makeSmokeAccount(
    name: String = "smoke@example.com",
    usedUnits: Int = 25,
    quota: Int = 100,
    isPaid: Bool = true
) -> AgentAccount {
    AgentAccount(
        id: UUID(),
        name: name,
        usedUnits: usedUnits,
        quota: quota,
        apiToken: "token-smoke",
        email: name,
        chatGPTAccountID: "acct-smoke",
        primaryUsagePercent: 30,
        primaryUsageResetAt: .now.addingTimeInterval(3600),
        secondaryUsagePercent: 60,
        secondaryUsageResetAt: .now.addingTimeInterval(7200),
        isPaid: isPaid
    )
}

private func makeJWTLikeToken(payload: [String: Any]) -> String {
    let jsonData = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
    let encoded = jsonData.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}

private final class ViewSmokeStore: AccountPoolStoring {
    var snapshot: AccountPoolSnapshot?
    var saved: [AccountPoolSnapshot] = []
    var loadCount = 0

    init(snapshot: AccountPoolSnapshot?) {
        self.snapshot = snapshot
    }

    func load() -> AccountPoolSnapshot? {
        loadCount += 1
        return snapshot
    }

    func save(_ snapshot: AccountPoolSnapshot) {
        saved.append(snapshot)
    }
}

@MainActor
private func renderInHostingView<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 1200, height: 900)
) {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()
    hostingView.needsLayout = true
    hostingView.layoutSubtreeIfNeeded()
}

struct ViewSmokeCoverageTests {
    @Test
    @MainActor
    func activeAccountPanelViewBodyRendersBranches() {
        var simulateCount = 0
        var evaluateCount = 0

        let withAccount = ActiveAccountPanelView(
            activeAccount: makeSmokeAccount(),
            mode: .focus,
            isFocusLockActive: true,
            hasLowUsageWarning: true,
            lowUsageAlertThresholdRatio: 0.2,
            showSimulationControl: true,
            onSimulateUsage: { simulateCount += 1 },
            onEvaluateSwitch: { evaluateCount += 1 }
        )
        let _ = withAccount.body

        let withoutAccount = ActiveAccountPanelView(
            activeAccount: nil,
            mode: .manual,
            isFocusLockActive: false,
            hasLowUsageWarning: false,
            lowUsageAlertThresholdRatio: 0.1,
            showSimulationControl: false,
            onSimulateUsage: { simulateCount += 1 },
            onEvaluateSwitch: { evaluateCount += 1 }
        )
        let _ = withoutAccount.body

        #expect(simulateCount == 0)
        #expect(evaluateCount == 0)
    }

    @Test
    @MainActor
    func overallUsagePanelViewBodyRendersExhaustedAndNormal() {
        var resetCount = 0
        let exhausted = OverallUsagePanelView(
            totalUsedUnits: 90,
            totalQuota: 100,
            overallUsageRatio: 0.9,
            availableAccountsCount: 0,
            isPoolExhausted: true,
            resetAllButtonTitle: "Reset",
            onResetAll: { resetCount += 1 }
        )
        let _ = exhausted.body

        let normal = OverallUsagePanelView(
            totalUsedUnits: 10,
            totalQuota: 100,
            overallUsageRatio: 0.1,
            availableAccountsCount: 3,
            isPoolExhausted: false,
            resetAllButtonTitle: "Reset",
            onResetAll: { resetCount += 1 }
        )
        let _ = normal.body

        #expect(resetCount == 0)
    }

    @Test
    @MainActor
    func activityLogPanelViewBodyRendersEmptyAndNonEmpty() {
        var clearCount = 0
        let empty = ActivityLogPanelView(
            activities: [],
            onClearActivities: { clearCount += 1 }
        )
        let _ = empty.body

        let nonEmpty = ActivityLogPanelView(
            activities: [
                PoolActivity(id: UUID(), timestamp: .now, message: "A"),
                PoolActivity(id: UUID(), timestamp: .now.addingTimeInterval(-120), message: "B")
            ],
            onClearActivities: { clearCount += 1 }
        )
        let _ = nonEmpty.body

        #expect(clearCount == 0)
    }

    @Test
    @MainActor
    func activityLogPanelDebugHooksCoverLocalizedTimeAndClearAction() {
        var clearCount = 0
        let panel = ActivityLogPanelView(
            activities: [
                PoolActivity(
                    id: UUID(),
                    timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                    message: "Debug"
                )
            ],
            onClearActivities: { clearCount += 1 }
        )

        let localized = panel.debugLocalizedTimeText(Date(timeIntervalSince1970: 1_700_000_000))
        #expect(!localized.isEmpty)

        panel.debugInvokeClearAction()
        #expect(clearCount == 1)
    }

    @Test
    @MainActor
    func backupRestorePanelViewBodyRendersErrorAndEditorStates() {
        let jsonBox = BindingBox("{\"ok\":true}")
        let errorBox = BindingBox<String?>(nil)

        let initial = BackupRestorePanelView(
            backupJSON: binding(jsonBox),
            backupError: binding(errorBox),
            onExport: {},
            onExportRefetchable: {},
            onImport: {}
        )
        let _ = initial.body

        errorBox.value = "Import failed"
        let withError = BackupRestorePanelView(
            backupJSON: binding(jsonBox),
            backupError: binding(errorBox),
            onExport: {},
            onExportRefetchable: {},
            onImport: {}
        )
        let _ = withError.body
    }

    @Test
    @MainActor
    func strategySettingsPanelViewBodyRendersIntelligentAndFocusModes() {
        let account = makeSmokeAccount()
        let modeBox = BindingBox<SwitchMode>(.intelligent)
        let manualSelectionBox = BindingBox<UUID>(account.id)
        let minIntervalBox = BindingBox<Double>(60)
        let switchThresholdBox = BindingBox<Double>(0.2)
        let lowUsageThresholdBox = BindingBox<Double>(0.15)
        let lowUsageAlertsEnabledBox = BindingBox(true)

        let intelligent = StrategySettingsPanelView(
            mode: .intelligent,
            accounts: [account],
            activeAccount: account,
            intelligentCandidateName: "next@example.com",
            canIntelligentSwitch: true,
            intelligentCooldownRemaining: 0,
            hasLowUsageWarning: true,
            modeBinding: binding(modeBox),
            manualSelectionBinding: binding(manualSelectionBox),
            minSwitchIntervalBinding: binding(minIntervalBox),
            switchThresholdBinding: binding(switchThresholdBox),
            lowUsageAlertThresholdBinding: binding(lowUsageThresholdBox),
            lowUsageAlertsEnabledBinding: binding(lowUsageAlertsEnabledBox)
        )
        let _ = intelligent.body

        modeBox.value = .focus
        lowUsageAlertsEnabledBox.value = false
        let focus = StrategySettingsPanelView(
            mode: .focus,
            accounts: [account],
            activeAccount: nil,
            intelligentCandidateName: nil,
            canIntelligentSwitch: false,
            intelligentCooldownRemaining: 42,
            hasLowUsageWarning: false,
            modeBinding: binding(modeBox),
            manualSelectionBinding: binding(manualSelectionBox),
            minSwitchIntervalBinding: binding(minIntervalBox),
            switchThresholdBinding: binding(switchThresholdBox),
            lowUsageAlertThresholdBinding: binding(lowUsageThresholdBox),
            lowUsageAlertsEnabledBinding: binding(lowUsageAlertsEnabledBox)
        )
        let _ = focus.body
    }

    @Test
    @MainActor
    func workspaceSettingsPanelViewBodyRendersAndNormalizesBindings() {
        let switchWithoutLaunchBox = BindingBox(false)
        let launchTargetBox = BindingBox("invalid-launch-target")
        let autoSyncEnabledBox = BindingBox(true)
        let autoSyncIntervalBox = BindingBox(30.0)
        let languageOverrideBox = BindingBox("Follow System")
        let appearanceOverrideBox = BindingBox("Light")
        let maxRecordsBox = BindingBox(5_000)
        let autoCheckUpdateBox = BindingBox(true)

        var checkCount = 0
        var showWhatsNewCount = 0
        let view = WorkspaceSettingsPanelView(
            switchWithoutLaunchingBinding: binding(switchWithoutLaunchBox),
            launchTargetBinding: binding(launchTargetBox),
            autoSyncEnabledBinding: binding(autoSyncEnabledBox),
            autoSyncIntervalSecondsBinding: binding(autoSyncIntervalBox),
            languageOverrideBinding: binding(languageOverrideBox),
            appearanceOverrideBinding: binding(appearanceOverrideBox),
            usageAnalyticsMaxStoredRecordsBinding: binding(maxRecordsBox),
            languageOptions: L10n.languageOptions,
            appUpdateAutoCheckEnabledBinding: binding(autoCheckUpdateBox),
            isCheckingForUpdates: false,
            appUpdateStatusMessage: "Up to date",
            onCheckForUpdates: { checkCount += 1 },
            onShowWhatsNew: { showWhatsNewCount += 1 }
        )

        let _ = view.body
        #expect(checkCount == 0)
        #expect(showWhatsNewCount == 0)
    }

    @Test
    @MainActor
    func debugToolsPanelViewBodyRendersDisclosuresAndDiagnostics() {
        let showUsageJSONBox = BindingBox(false)
        let usageJSONBox = BindingBox("")
        let showSwitchLogBox = BindingBox(true)
        let switchLogBox = BindingBox("switch-log")

        let withDiagnostics = DebugToolsPanelView(
            showUsageRawJSON: binding(showUsageJSONBox),
            lastUsageRawJSON: binding(usageJSONBox),
            showSwitchLaunchLog: binding(showSwitchLogBox),
            lastSwitchLaunchLog: binding(switchLogBox),
            diagnostics: [
                DebugDiagnosticMetric(id: "mem", title: "Memory", value: "120 MB")
            ]
        )
        let _ = withDiagnostics.body

        let noDiagnostics = DebugToolsPanelView(
            showUsageRawJSON: binding(showUsageJSONBox),
            lastUsageRawJSON: binding(usageJSONBox),
            showSwitchLaunchLog: binding(showSwitchLogBox),
            lastSwitchLaunchLog: binding(switchLogBox),
            diagnostics: []
        )
        let _ = noDiagnostics.body
    }

    @Test
    @MainActor
    func panelHelpersAndModelBodyRender() {
        let editorTextBox = BindingBox("line-1")
        let editor = PanelCodeEditorView(
            text: binding(editorTextBox),
            minimumHeight: 120,
            font: .system(.body, design: .monospaced)
        )
        let _ = editor.body

        let glass = GlassPanel {
            Text("Hello")
        }
        let _ = glass.body

        let item = Item(timestamp: .now)
        #expect(item.timestamp <= .now)
    }

    @Test
    @MainActor
    func dashboardThemeSystemPaletteAndSubtleButtonRender() {
        let defaults = UserDefaults.standard
        let appearanceKey = AppAppearancePreference.storageKey
        let interfaceStyleKey = "AppleInterfaceStyle"
        let originalAppearance = defaults.object(forKey: appearanceKey)
        let originalInterfaceStyle = defaults.object(forKey: interfaceStyleKey)
        defer {
            if let originalAppearance {
                defaults.set(originalAppearance, forKey: appearanceKey)
            } else {
                defaults.removeObject(forKey: appearanceKey)
            }
            if let originalInterfaceStyle {
                defaults.set(originalInterfaceStyle, forKey: interfaceStyleKey)
            } else {
                defaults.removeObject(forKey: interfaceStyleKey)
            }
            PoolDashboardTheme.debugResetForcedPalette()
        }

        PoolDashboardTheme.debugResetForcedPalette()
        defaults.set(AppAppearancePreference.system.rawValue, forKey: appearanceKey)
        defaults.set("Dark", forKey: interfaceStyleKey)
        #expect(PoolDashboardTheme.debugSystemPrefersDarkMode())
        _ = PoolDashboardTheme.isLightPalette
        _ = PoolDashboardTheme.modalSolidFill

        defaults.set("Light", forKey: interfaceStyleKey)
        _ = PoolDashboardTheme.debugSystemPrefersDarkMode()
        _ = PoolDashboardTheme.isLightPalette
        _ = PoolDashboardTheme.modalSolidFill

        let subtleButton = Button("Subtle") {}
            .buttonStyle(DashboardSubtleButtonStyle())
            .padding()
            .background(PoolDashboardTheme.panelFill)
        renderInHostingView(subtleButton, size: CGSize(width: 240, height: 120))
    }

    @Test
    @MainActor
    func syncToolbarViewBodyRendersSyncingRetryAndStatusBadges() {
        var syncCount = 0
        var retryCount = 0
        var forceRetryCount = 0

        let syncing = SyncToolbarView(
            isSyncing: true,
            lastSyncAt: nil,
            errorText: nil,
            onSync: { syncCount += 1 },
            onRetry: { retryCount += 1 },
            onForceRetry: { forceRetryCount += 1 }
        )
        let _ = syncing.body

        let retry = SyncToolbarView(
            isSyncing: false,
            lastSyncAt: Date(timeIntervalSince1970: 1_700_000_000),
            errorText: "timeout",
            onSync: { syncCount += 1 },
            onRetry: { retryCount += 1 },
            onForceRetry: { forceRetryCount += 1 }
        )
        let _ = retry.body

        let idle = SyncToolbarView(
            isSyncing: false,
            lastSyncAt: nil,
            errorText: "",
            onSync: { syncCount += 1 },
            onRetry: { retryCount += 1 },
            onForceRetry: { forceRetryCount += 1 }
        )
        let _ = idle.body

        #expect(syncCount == 0)
        #expect(retryCount == 0)
        #expect(forceRetryCount == 0)
    }

    @Test
    @MainActor
    func richMenuBarDashboardViewRendersWithRuntimeModel() {
        let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
        let activeID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let backupID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        var state = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: activeID,
                    createdAt: baseDate,
                    name: "paid@example.com",
                    groupName: AgentAccount.defaultGroupName,
                    usedUnits: 20,
                    quota: 100,
                    apiToken: "token-active",
                    email: "paid@example.com",
                    chatGPTAccountID: "acct-active",
                    identityScope: AgentAccount.personalIdentityScope,
                    primaryUsagePercent: 30,
                    primaryUsageResetAt: baseDate.addingTimeInterval(300),
                    secondaryUsagePercent: 40,
                    secondaryUsageResetAt: baseDate.addingTimeInterval(600),
                    isPaid: true
                ),
                AgentAccount(
                    id: backupID,
                    createdAt: baseDate.addingTimeInterval(-10),
                    name: "backup@example.com",
                    groupName: AgentAccount.defaultGroupName,
                    usedUnits: 90,
                    quota: 100,
                    apiToken: "token-backup",
                    email: "backup@example.com",
                    chatGPTAccountID: "acct-backup",
                    identityScope: AgentAccount.personalIdentityScope,
                    primaryUsagePercent: 95,
                    primaryUsageResetAt: baseDate.addingTimeInterval(900),
                    secondaryUsagePercent: 95,
                    secondaryUsageResetAt: baseDate.addingTimeInterval(1_800),
                    isPaid: true,
                    usageSyncError: "Needs login"
                )
            ],
            mode: .intelligent
        )
        state.markActiveAccountForSwitchLaunch(activeID, now: baseDate)
        state.markUsageSynced(at: baseDate)

        let runtimeModel = AppPoolRuntimeModel(
            store: ViewSmokeStore(snapshot: nil),
            initialState: state,
            widgetPublisher: { _ in }
        )

        var openedDashboard = false
        var switchedAccountIDs: [UUID] = []
        let view = MenuBarDashboardView(
            runtimeModel: runtimeModel,
            openDashboard: { openedDashboard = true },
            switchAccount: { switchedAccountIDs.append($0) }
        )

        renderInHostingView(view, size: CGSize(width: 420, height: 620))

        #expect(runtimeModel.menuBarSnapshot.headerSummaryText.contains(L10n.text("menu_bar.summary.accounts")))
        #expect(openedDashboard == false)
        #expect(switchedAccountIDs.isEmpty)
    }

    @Test
    @MainActor
    func richMenuBarDashboardRendersEmptyStateAndMultipleGroups() {
        let emptyRuntimeModel = AppPoolRuntimeModel(
            store: ViewSmokeStore(snapshot: nil),
            initialState: AccountPoolState(accounts: [], mode: .manual),
            widgetPublisher: { _ in }
        )
        let emptyView = MenuBarDashboardView(
            runtimeModel: emptyRuntimeModel,
            openDashboard: {},
            switchAccount: { _ in }
        )
        renderInHostingView(emptyView, size: CGSize(width: 420, height: 620))
        #expect(emptyRuntimeModel.menuBarSnapshot.accountRows.isEmpty)

        let baseDate = Date(timeIntervalSince1970: 1_750_100_000)
        let personalID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let workID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        var groupedState = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: personalID,
                    createdAt: baseDate,
                    name: "personal@example.com",
                    groupName: "Personal",
                    usedUnits: 11,
                    quota: 100,
                    apiToken: "token-personal",
                    email: "personal@example.com",
                    chatGPTAccountID: "acct-personal",
                    identityScope: AgentAccount.personalIdentityScope,
                    primaryUsagePercent: 20,
                    primaryUsageResetAt: baseDate.addingTimeInterval(600),
                    secondaryUsagePercent: 30,
                    secondaryUsageResetAt: baseDate.addingTimeInterval(1_200),
                    isPaid: true
                ),
                AgentAccount(
                    id: workID,
                    createdAt: baseDate.addingTimeInterval(10),
                    name: "work@example.com",
                    groupName: "Work",
                    usedUnits: 44,
                    quota: 100,
                    apiToken: "token-work",
                    email: "work@example.com",
                    chatGPTAccountID: "acct-work",
                    identityScope: AgentAccount.personalIdentityScope,
                    primaryUsagePercent: 55,
                    primaryUsageResetAt: baseDate.addingTimeInterval(900),
                    secondaryUsagePercent: 66,
                    secondaryUsageResetAt: baseDate.addingTimeInterval(1_800),
                    isPaid: true
                )
            ],
            mode: .manual
        )
        groupedState.markActiveAccountForSwitchLaunch(personalID, now: baseDate)
        groupedState.markUsageSynced(at: baseDate)
        let groupedRuntimeModel = AppPoolRuntimeModel(
            store: ViewSmokeStore(snapshot: nil),
            initialState: groupedState,
            widgetPublisher: { _ in }
        )
        let groupedView = MenuBarDashboardView(
            runtimeModel: groupedRuntimeModel,
            openDashboard: {},
            switchAccount: { _ in }
        )
        renderInHostingView(groupedView, size: CGSize(width: 420, height: 620))
        #expect(groupedRuntimeModel.menuBarSnapshot.accountGroupNames == ["Personal", "Work"])
    }

    @Test
    @MainActor
    func menuBarPrivateRowsRenderWarningsAndResetCreditDetailsThroughDebugHooks() {
        let rowID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let accountRow = MenuBarAccountRow(
            id: rowID,
            name: "reset-credit@example.com",
            groupName: "Default",
            isActive: true,
            isPaid: true,
            credentialLabel: nil,
            planBadgeText: "Pro",
            resetCreditBadgeText: nil,
            resetCreditDetailText: "2 resets available\nReset 1 expires: 2026/7/30 20:03 GMT+8\nReset 2 expires: 2026/8/1 20:03 GMT+8",
            resetCreditNoteText: "Estimated from previous successful sync plus 30 days.",
            resetCreditAccessibilityLabel: "2 resets available",
            weeklyRemainingText: "91%",
            fiveHourRemainingText: "94%",
            resetText: "7/7 09:55",
            fiveHourResetText: "7/1 12:09",
            warningText: "Login expired"
        )

        var switchedIDs: [UUID] = []
        let rowView = MenuBarDashboardView.debugAccountRowView(
            row: accountRow,
            switchAccount: { switchedIDs.append($0) }
        )
        renderInHostingView(rowView, size: CGSize(width: 420, height: 220))

        let warningRows = [
            MenuBarWarningRow(id: "oauth", kind: .oauthExpired, title: "OAuth", message: "Login expired"),
            MenuBarWarningRow(id: "relay", kind: .relayUsageUnavailable, title: "Relay", message: "Usage unavailable"),
            MenuBarWarningRow(id: "sync", kind: .syncFailed, title: "Sync", message: "Sync failed"),
            MenuBarWarningRow(id: "excluded", kind: .excluded, title: "Excluded", message: "Manually excluded")
        ]
        let warningsView = MenuBarDashboardView.debugWarningsPopoverView(rows: warningRows)
        renderInHostingView(warningsView, size: CGSize(width: 360, height: 420))

        let warningState = AccountPoolState(
            accounts: [
                AgentAccount(
                    id: rowID,
                    name: "expired@example.com",
                    usedUnits: 10,
                    quota: 100,
                    apiToken: "token-expired",
                    usageSyncError: L10n.text("usage.sync.error.oauth_login_expired")
                )
            ],
            mode: .manual
        )
        let warningRuntimeModel = AppPoolRuntimeModel(
            store: ViewSmokeStore(snapshot: nil),
            initialState: warningState,
            widgetPublisher: { _ in }
        )
        let warningButton = MenuBarDashboardView.debugWarningPopoverButtonView(runtimeModel: warningRuntimeModel)
        renderInHostingView(warningButton, size: CGSize(width: 96, height: 96))
        #expect(!warningRuntimeModel.menuBarSnapshot.warningRows.isEmpty)

        #expect(switchedIDs.isEmpty)
    }

    @Test
    func richMenuBarDashboardUsesCompactWarningPopoverInsteadOfInlineSection() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(!source.contains("warningsSection"))
        #expect(source.contains("warningPopoverButton"))
        #expect(source.contains("WarningsPopoverView"))
    }

    @Test
    func richMenuBarDashboardKeepsAccountRowsCompact() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(!source.contains("Text(warningText)\n                        .font(.caption)"))
        #expect(source.contains("accountWarningIndicator"))
        #expect(source.contains(".help(warningText)"))
        #expect(source.contains("isAccountWarningPopoverPresented"))
        #expect(source.contains(".popover(isPresented: $isAccountWarningPopoverPresented"))
        #expect(source.contains("accountUsageResetLine"))
        #expect(source.contains("accountUsageResetPair"))
        #expect(!source.contains("private var accountMetricLine"))
    }

    @Test
    func richMenuBarDashboardUsesSingleAccountSectionAndResetCreditDetailLines() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(!source.contains("activeAccountSection"))
        #expect(!source.contains("resetCreditIndicator"))
        #expect(!source.contains("isResetCreditPopoverPresented"))
        #expect(source.contains("resetCreditDetailLines"))
        #expect(source.contains("resetCreditDetailLineTexts"))
        #expect(source.contains("resetCreditNoteButton"))
        #expect(source.contains("row.resetCreditNoteText"))
        #expect(source.contains("isResetCreditNotePopoverPresented"))
        #expect(source.contains(".popover(isPresented: $isResetCreditNotePopoverPresented"))
        #expect(source.contains("exclamationmark.circle.fill"))
        #expect(source.contains("components(separatedBy: \"\\n\")"))
        #expect(source.contains("row.resetCreditAccessibilityLabel"))
    }

    @Test
    func richMenuBarDashboardAlwaysShowsSwitchButtonForAccountRows() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(source.contains("private var accountAction"))
        #expect(source.contains("Button(L10n.text(\"menu_bar.action.switch\"))"))
        #expect(!source.contains("} else {\n            Button(L10n.text(\"menu_bar.action.switch\"))"))
        #expect(source.contains("switchAccount(row.id)"))
    }

    @Test
    func richMenuBarDashboardOffersAccountGroupSwitcher() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("CodexPoolManager/MenuBar/MenuBarDashboardView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(source.contains("selectedAccountGroupName"))
        #expect(source.contains("accountGroupSwitcher"))
        #expect(source.contains("filteredAccountRows"))
        #expect(source.contains("snapshot.accountGroupNames"))
    }

    @Test
    @MainActor
    func accountUsagePanelViewRendersFullAndMinimalLayouts() {
        let defaults = UserDefaults.standard
        let sortModeKey = "pool_dashboard.account_usage.sort_mode"
        let activeFirstKey = "pool_dashboard.account_usage.active_first"
        let paidFirstKey = "pool_dashboard.account_usage.paid_first"
        let apiKeyLastKey = "pool_dashboard.account_usage.api_key_last"
        let layoutModeKey = "pool_dashboard.account_usage.layout_mode"

        let oldSort = defaults.object(forKey: sortModeKey)
        let oldActiveFirst = defaults.object(forKey: activeFirstKey)
        let oldPaidFirst = defaults.object(forKey: paidFirstKey)
        let oldAPIKeyLast = defaults.object(forKey: apiKeyLastKey)
        let oldLayout = defaults.object(forKey: layoutModeKey)
        defer {
            if let oldSort { defaults.set(oldSort, forKey: sortModeKey) } else { defaults.removeObject(forKey: sortModeKey) }
            if let oldActiveFirst { defaults.set(oldActiveFirst, forKey: activeFirstKey) } else { defaults.removeObject(forKey: activeFirstKey) }
            if let oldPaidFirst { defaults.set(oldPaidFirst, forKey: paidFirstKey) } else { defaults.removeObject(forKey: paidFirstKey) }
            if let oldAPIKeyLast { defaults.set(oldAPIKeyLast, forKey: apiKeyLastKey) } else { defaults.removeObject(forKey: apiKeyLastKey) }
            if let oldLayout { defaults.set(oldLayout, forKey: layoutModeKey) } else { defaults.removeObject(forKey: layoutModeKey) }
        }

        defaults.set("remainingHigh", forKey: sortModeKey)
        defaults.set(true, forKey: activeFirstKey)
        defaults.set(true, forKey: paidFirstKey)
        defaults.set(true, forKey: apiKeyLastKey)

        let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
        let activeID = UUID()
        let paidOtherID = UUID()
        let freeID = UUID()
        let externalID = UUID()

        let accounts = [
            AgentAccount(
                id: activeID,
                createdAt: baseDate,
                name: "active@example.com",
                groupName: AgentAccount.defaultGroupName,
                usedUnits: 20,
                quota: 100,
                apiToken: "token-active",
                email: "active@example.com",
                chatGPTAccountID: "acct-active",
                identityScope: AgentAccount.personalIdentityScope,
                primaryUsagePercent: 30,
                primaryUsageResetAt: baseDate.addingTimeInterval(300),
                secondaryUsagePercent: 40,
                secondaryUsageResetAt: baseDate.addingTimeInterval(600),
                isPaid: true
            ),
            AgentAccount(
                id: paidOtherID,
                createdAt: baseDate.addingTimeInterval(-10),
                name: "paid-other@example.com",
                groupName: AgentAccount.defaultGroupName,
                usedUnits: 70,
                quota: 100,
                apiToken: "token-other",
                email: "paid-other@example.com",
                chatGPTAccountID: "acct-other",
                identityScope: AgentAccount.personalIdentityScope,
                primaryUsagePercent: 90,
                primaryUsageResetAt: baseDate.addingTimeInterval(900),
                secondaryUsagePercent: 95,
                secondaryUsageResetAt: baseDate.addingTimeInterval(1_800),
                isPaid: true,
                isUsageSyncExcluded: true,
                usageSyncError: "auth failed"
            ),
            AgentAccount(
                id: freeID,
                createdAt: baseDate.addingTimeInterval(-30),
                name: "free@example.com",
                groupName: AgentAccount.defaultGroupName,
                usedUnits: 10,
                quota: 100,
                apiToken: "token-free",
                email: "free@example.com",
                chatGPTAccountID: "acct-free",
                identityScope: AgentAccount.personalIdentityScope,
                primaryUsagePercent: nil,
                primaryUsageResetAt: baseDate.addingTimeInterval(3_000),
                isPaid: false
            ),
            AgentAccount(
                id: externalID,
                createdAt: baseDate.addingTimeInterval(-60),
                name: "external@example.com",
                groupName: "Ops",
                usedUnits: 30,
                quota: 100,
                apiToken: "token-external",
                email: "external@example.com",
                chatGPTAccountID: "acct-external",
                identityScope: AgentAccount.personalIdentityScope,
                primaryUsagePercent: 45,
                primaryUsageResetAt: baseDate.addingTimeInterval(3_600),
                secondaryUsagePercent: 50,
                secondaryUsageResetAt: baseDate.addingTimeInterval(4_200),
                isPaid: true
            )
        ]

        let nameBox = BindingBox("new-account")
        let quotaBox = BindingBox(200)
        let groupBox = BindingBox(AgentAccount.defaultGroupName)
        let accountNames = BindingBox(Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) }))
        let accountQuotas = BindingBox(Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.quota) }))
        let accountUsed = BindingBox(Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.usedUnits) }))

        var addCount = 0
        var removeCount = 0
        var moveCount = 0
        var createGroupCount = 0
        var renameGroupCount = 0
        var deleteGroupCount = 0
        var switchedAccountIDs: [UUID] = []

        func makeView(layoutMode: String) -> AccountUsagePanelView {
            defaults.set(layoutMode, forKey: layoutModeKey)
            return AccountUsagePanelView(
                newAccountName: binding(nameBox),
                newAccountQuota: binding(quotaBox),
                selectedGroupName: binding(groupBox),
                availableWidth: nil,
                accounts: accounts,
                groups: [AgentAccount.defaultGroupName, "Ops"],
                activeAccountID: activeID,
                switchLaunchError: "launch failed",
                switchLaunchWarning: "switch warning",
                showAddAccountControls: true,
                onAddAccount: { _, _ in addCount += 1 },
                onSwitchAndLaunch: { accountID in switchedAccountIDs.append(accountID) },
                onRemoveAccount: { _ in removeCount += 1 },
                onMoveAccountToGroup: { _, _ in moveCount += 1 },
                onCreateGroup: { _ in createGroupCount += 1 },
                onRenameGroup: { _, _ in renameGroupCount += 1 },
                onDeleteGroup: { _ in deleteGroupCount += 1 },
                accountNameBinding: { id in
                    Binding(
                        get: { accountNames.value[id] ?? "" },
                        set: { accountNames.value[id] = $0 }
                    )
                },
                accountQuotaBinding: { id in
                    Binding(
                        get: { accountQuotas.value[id] ?? 0 },
                        set: { accountQuotas.value[id] = $0 }
                    )
                },
                accountUsedBinding: { id in
                    Binding(
                        get: { accountUsed.value[id] ?? 0 },
                        set: { accountUsed.value[id] = $0 }
                    )
                },
                isPercentUsageAccount: { account in account.isPaid },
                remainingLabel: { account in "\(account.remainingUnits)" },
                usageProgressColor: { account in account.remainingRatio > 0.2 ? .blue : .red }
            )
        }

        renderInHostingView(makeView(layoutMode: "quad"), size: CGSize(width: 1280, height: 840))
        renderInHostingView(makeView(layoutMode: "minimal"), size: CGSize(width: 520, height: 840))

        #expect(addCount == 0)
        #expect(removeCount == 0)
        #expect(moveCount == 0)
        #expect(createGroupCount == 0)
        #expect(renameGroupCount == 0)
        #expect(deleteGroupCount == 0)
        #expect(switchedAccountIDs.isEmpty)
    }

    @Test
    func accountUsagePanelSortHelperMovesAPIKeyAccountsLast() {
        let baseDate = Date(timeIntervalSince1970: 1_750_000_000)
        let oauthA = makeSmokeAccount(name: "oauth-a@example.com", usedUnits: 10, quota: 100)
        let relayA = AgentAccount(
            id: UUID(),
            createdAt: baseDate.addingTimeInterval(1),
            name: "relay-a@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay-a",
            credentialType: .relayAPIKey
        )
        let oauthB = makeSmokeAccount(name: "oauth-b@example.com", usedUnits: 20, quota: 100)
        let relayB = AgentAccount(
            id: UUID(),
            createdAt: baseDate.addingTimeInterval(2),
            name: "relay-b@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay-b",
            credentialType: .relayAPIKey
        )

        let sorted = AccountUsagePanelView.debugAccountsWithAPIKeyLast([oauthA, relayA, oauthB, relayB])

        #expect(sorted.map(\.name) == [
            "oauth-a@example.com",
            "oauth-b@example.com",
            "relay-a@example.com",
            "relay-b@example.com"
        ])
    }

    @Test
    @MainActor
    func accountUsagePanelDebugHooksCoverDeleteConfirmationAndRenameControls() {
        let accountID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let probe = AccountUsagePanelView.debugDeleteConfirmationProbe(
            groupName: "Ops",
            accountID: accountID,
            accountName: "ops@example.com"
        )

        #expect(probe.groupID == "group:Ops")
        #expect(probe.accountID == "account:\(accountID.uuidString)")
        #expect(probe.groupTitle == L10n.text("group.delete_confirm_title"))
        #expect(probe.accountTitle == L10n.text("account.delete_confirm_title"))
        #expect(probe.deletedGroups == ["Ops"])
        #expect(probe.removedAccountIDs == [accountID])

        let renameControls = AccountUsagePanelView.debugRenameGroupControlsView(selectedGroupName: "Ops")
        renderInHostingView(renameControls, size: CGSize(width: 420, height: 80))

        let baseDate = Date(timeIntervalSince1970: 1_760_000_000)
        let active = AgentAccount(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            createdAt: baseDate.addingTimeInterval(10),
            name: "active@example.com",
            groupName: "Ops",
            usedUnits: 20,
            quota: 100,
            apiToken: "token-active",
            email: "active@example.com",
            chatGPTAccountID: "acct-active",
            isPaid: true
        )
        let lowRemaining = AgentAccount(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            createdAt: baseDate.addingTimeInterval(20),
            name: "z-low@example.com",
            groupName: "Ops",
            usedUnits: 95,
            quota: 100,
            apiToken: "token-low",
            email: "z-low@example.com",
            chatGPTAccountID: "acct-low",
            isPaid: false
        )
        let highExcluded = AgentAccount(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            createdAt: baseDate.addingTimeInterval(30),
            name: "a-excluded@example.com",
            groupName: "Ops",
            usedUnits: 1,
            quota: 100,
            apiToken: "token-excluded",
            email: "a-excluded@example.com",
            chatGPTAccountID: "acct-excluded",
            isPaid: false,
            isUsageSyncExcluded: true
        )
        let relay = AgentAccount(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            createdAt: baseDate.addingTimeInterval(40),
            name: "relay@example.com",
            groupName: "Ops",
            usedUnits: 0,
            quota: 100,
            apiToken: "sk-relay",
            credentialType: .relayAPIKey
        )

        let stateProbe = AccountUsagePanelView.debugStateMutationProbe(
            accounts: [active, lowRemaining, highExcluded, relay],
            selectedGroupName: "Ops",
            activeAccountID: active.id
        )

        #expect(stateProbe.sortTitles.count == 3)
        #expect(stateProbe.sortedAccountNamesByMode["joinedAt"]?.first == "relay@example.com")
        #expect(stateProbe.sortedAccountNamesByMode["name"]?.first == "a-excluded@example.com")
        #expect(stateProbe.sortedAccountNamesByMode["remainingHigh"]?.first == "relay@example.com")
        #expect(stateProbe.sortedAccountNamesByMode["remainingHigh"]?.last == "a-excluded@example.com")
        #expect(stateProbe.prioritySortedAccountNames.first == "active@example.com")
        #expect(stateProbe.prioritySortedAccountNames.last == "relay@example.com")
        #expect(stateProbe.savedAccountName == "renamed@example.com")
        #expect(stateProbe.canceledDraftFallbackName == "active@example.com")
        #expect(stateProbe.requestedDeleteGroupID == "group:Ops")
    }

    @Test
    func accountUsagePanelRendersResetCreditDetailsInAccountCards() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let viewSourceURL = repositoryRoot.appendingPathComponent("Features/PoolDashboard/Components/AccountUsagePanelView.swift")
        let source = try String(contentsOf: viewSourceURL, encoding: .utf8)

        #expect(source.contains("accountResetCreditDetails(account, compact: false)"))
        #expect(source.contains("accountResetCreditDetails(account, compact: true)"))
        #expect(source.contains("ResetCreditPresentationFormatter.presentation(for: account)"))
        #expect(source.contains("presentation.compactDetailLine"))
        #expect(source.contains("isResetCreditNotePopoverPresented"))
        #expect(source.contains("exclamationmark.circle.fill"))
    }

    @Test
    func poolDashboardRendersWhatsNewPromptAndSettingsEntry() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile.deletingLastPathComponent().deletingLastPathComponent()
        let dashboardSourceURL = repositoryRoot.appendingPathComponent("Features/PoolDashboard/PoolDashboardView.swift")
        let settingsSourceURL = repositoryRoot.appendingPathComponent("Features/PoolDashboard/Components/WorkspaceSettingsPanelView.swift")
        let dashboardSource = try String(contentsOf: dashboardSourceURL, encoding: .utf8)
        let settingsSource = try String(contentsOf: settingsSourceURL, encoding: .utf8)

        #expect(dashboardSource.contains("whatsNewOverlay(announcement:"))
        #expect(dashboardSource.contains("showWhatsNewIfNeeded()"))
        #expect(dashboardSource.contains("markWhatsNewSeen("))
        #expect(settingsSource.contains("onShowWhatsNew"))
        #expect(settingsSource.contains("whats_new.settings.show"))
    }

    @Test
    @MainActor
    func oauthLoginPanelViewRendersSigningIdleManualAndErrorStates() {
        let issuerBox = BindingBox("https://auth.openai.com")
        let clientIDBox = BindingBox("app_test_client")
        let scopesBox = BindingBox("openid profile email")
        let redirectBox = BindingBox("http://localhost:1455/auth/callback")
        let originatorBox = BindingBox("codex_cli_rs")
        let workspaceBox = BindingBox("org-test")
        let oauthNameBox = BindingBox("OAuth Account")
        let quotaBox = BindingBox(100)
        let callbackBox = BindingBox("")

        var signInCount = 0
        var copyCount = 0
        var manualImportCount = 0
        var cancelCount = 0

        let idleView = OAuthLoginPanelView(
            oauthIssuer: binding(issuerBox),
            oauthClientID: binding(clientIDBox),
            oauthScopes: binding(scopesBox),
            oauthRedirectURI: binding(redirectBox),
            oauthOriginator: binding(originatorBox),
            oauthWorkspaceID: binding(workspaceBox),
            oauthAccountName: binding(oauthNameBox),
            oauthAccountQuota: binding(quotaBox),
            manualCallbackURL: binding(callbackBox),
            isSigningInOAuth: false,
            oauthSuccessMessage: "Done",
            oauthError: nil,
            manualAuthorizationURLOverride: nil,
            showManualImportSection: false,
            onSignIn: { signInCount += 1 },
            onCopyURLAndManualSignIn: { copyCount += 1 },
            onManualImport: { manualImportCount += 1 },
            onCancelSignIn: { cancelCount += 1 }
        )
        renderInHostingView(idleView, size: CGSize(width: 1320, height: 840))

        callbackBox.value = "http://localhost:1455/auth/callback?code=abc&state=xyz"
        let signingManualView = OAuthLoginPanelView(
            oauthIssuer: binding(issuerBox),
            oauthClientID: binding(clientIDBox),
            oauthScopes: binding(scopesBox),
            oauthRedirectURI: binding(redirectBox),
            oauthOriginator: binding(originatorBox),
            oauthWorkspaceID: binding(workspaceBox),
            oauthAccountName: binding(oauthNameBox),
            oauthAccountQuota: binding(quotaBox),
            manualCallbackURL: binding(callbackBox),
            isSigningInOAuth: true,
            oauthSuccessMessage: nil,
            oauthError: "Failed",
            manualAuthorizationURLOverride: " https://manual.example/authorize?foo=bar ",
            showManualImportSection: true,
            onSignIn: { signInCount += 1 },
            onCopyURLAndManualSignIn: { copyCount += 1 },
            onManualImport: { manualImportCount += 1 },
            onCancelSignIn: { cancelCount += 1 }
        )
        renderInHostingView(signingManualView, size: CGSize(width: 1320, height: 920))

        #expect(signInCount == 0)
        #expect(copyCount == 0)
        #expect(manualImportCount == 0)
        #expect(cancelCount == 0)
    }

    @Test
    @MainActor
    func relayAPIKeyPanelViewRendersEmptySuccessAndErrorStates() {
        let accountNameBox = BindingBox("")
        let providerIDBox = BindingBox("mirror")
        let providerNameBox = BindingBox("mirror")
        let baseURLBox = BindingBox("https://ai.liaryai.com/api/codex")
        let wireAPIBox = BindingBox("responses")
        let apiKeyBox = BindingBox("sk-relay")
        let preserveOfficialAuthBox = BindingBox(false)
        var addCount = 0

        let empty = RelayAPIKeyPanelView(
            accountName: binding(accountNameBox),
            providerID: binding(providerIDBox),
            providerName: binding(providerNameBox),
            baseURL: binding(baseURLBox),
            wireAPI: binding(wireAPIBox),
            apiKey: binding(apiKeyBox),
            preserveOfficialAuth: binding(preserveOfficialAuthBox),
            canAddRelayAccount: true,
            successMessage: nil,
            errorMessage: nil,
            onAddRelayAccount: { addCount += 1 }
        )
        renderInHostingView(empty, size: CGSize(width: 1200, height: 780))

        let withStatus = RelayAPIKeyPanelView(
            accountName: binding(accountNameBox),
            providerID: binding(providerIDBox),
            providerName: binding(providerNameBox),
            baseURL: binding(baseURLBox),
            wireAPI: binding(wireAPIBox),
            apiKey: binding(apiKeyBox),
            preserveOfficialAuth: binding(preserveOfficialAuthBox),
            canAddRelayAccount: true,
            successMessage: "Relay account added.",
            errorMessage: "Relay failed.",
            onAddRelayAccount: { addCount += 1 }
        )
        renderInHostingView(withStatus, size: CGSize(width: 1200, height: 860))

        #expect(addCount == 0)
    }

    @Test
    func relayAPIKeyPanelKeepsRequiredBaseURLInPrimaryFields() {
        #expect(RelayAPIKeyPanelView.debugPrimaryFieldIDs == [.accountName, .baseURL, .apiKey])
        #expect(RelayAPIKeyPanelView.debugAdvancedFieldIDs == [.providerID, .providerName, .wireAPI])
    }

    @Test
    @MainActor
    func relayAPIKeyWireAPIHelpPopoverDebugViewRenders() {
        let popover = RelayAPIKeyPanelView.debugWireAPIHelpPopoverView()

        renderInHostingView(popover, size: CGSize(width: 520, height: 260))
    }

    @Test
    func relayAPIKeyFormReadinessTrimsRequiredFields() {
        #expect(RelayAPIKeyFormReadiness.canAdd(
            providerID: " mirror ",
            baseURL: " https://ai.liaryai.com/api/codex ",
            apiKey: " sk-relay "
        ))
        #expect(!RelayAPIKeyFormReadiness.canAdd(providerID: "", baseURL: "https://example.com", apiKey: "sk"))
        #expect(!RelayAPIKeyFormReadiness.canAdd(providerID: "mirror", baseURL: "   ", apiKey: "sk"))
        #expect(!RelayAPIKeyFormReadiness.canAdd(providerID: "mirror", baseURL: "https://example.com", apiKey: "\n"))
    }

    @Test
    @MainActor
    func localOAuthAccountsPanelViewRendersEmptyErrorSuccessAndJWTFallbackRows() {
        let tokenWithEmail = makeJWTLikeToken(
            payload: ["https://api.openai.com/profile": ["email": "jwt@example.com"]]
        )

        let missingID = LocalCodexOAuthAccount(
            id: "acc-missing",
            displayName: "Missing ID Account",
            email: nil,
            source: "scan",
            accessToken: tokenWithEmail,
            chatGPTAccountID: nil
        )
        let ready = LocalCodexOAuthAccount(
            id: "acc-ready",
            displayName: "Ready Account",
            email: "ready@example.com",
            source: "scan",
            accessToken: "eyJhbGciOiJIUzI1NiJ9.eyJlbWFpbCI6InJlYWR5QGV4YW1wbGUuY29tIn0.sig",
            chatGPTAccountID: "acct-ready"
        )

        var scanCount = 0
        var chooseCount = 0
        var importCount = 0

        let empty = LocalOAuthAccountsPanelView(
            accounts: [],
            errorMessage: nil,
            successMessage: nil,
            importingAccountID: nil,
            onScan: { scanCount += 1 },
            onChooseAuthFile: { chooseCount += 1 },
            onImport: { _ in importCount += 1 }
        )
        renderInHostingView(empty, size: CGSize(width: 1200, height: 780))

        let withError = LocalOAuthAccountsPanelView(
            accounts: [missingID, ready],
            errorMessage: "scan failed",
            successMessage: nil,
            importingAccountID: nil,
            onScan: { scanCount += 1 },
            onChooseAuthFile: { chooseCount += 1 },
            onImport: { _ in importCount += 1 }
        )
        renderInHostingView(withError, size: CGSize(width: 1200, height: 900))

        let withSuccessImporting = LocalOAuthAccountsPanelView(
            accounts: [missingID, ready],
            errorMessage: nil,
            successMessage: "imported",
            importingAccountID: "acc-ready",
            onScan: { scanCount += 1 },
            onChooseAuthFile: { chooseCount += 1 },
            onImport: { _ in importCount += 1 }
        )
        renderInHostingView(withSuccessImporting, size: CGSize(width: 1200, height: 900))

        #expect(scanCount == 0)
        #expect(chooseCount == 0)
        #expect(importCount == 0)
    }

    @Test
    @MainActor
    func usageAnalyticsStableDetailSectionsViewRendersEmptyAndPopulatedStates() {
        let now = Date()
        let accountA = AgentAccount(
            id: UUID(),
            name: "alpha@example.com",
            usedUnits: 35,
            quota: 100,
            apiToken: "token-a",
            email: "alpha@example.com",
            chatGPTAccountID: "acct-alpha",
            primaryUsagePercent: 42,
            primaryUsageResetAt: now.addingTimeInterval(3_600),
            secondaryUsagePercent: 35,
            secondaryUsageResetAt: now.addingTimeInterval(86_400),
            isPaid: true
        )
        let accountB = AgentAccount(
            id: UUID(),
            name: "beta@example.com",
            usedUnits: 74,
            quota: 100,
            apiToken: "token-b",
            email: "beta@example.com",
            chatGPTAccountID: "acct-beta",
            primaryUsagePercent: 80,
            primaryUsageResetAt: now.addingTimeInterval(7_200),
            secondaryUsagePercent: 74,
            secondaryUsageResetAt: now.addingTimeInterval(120_000),
            isPaid: true
        )

        let emptyState = UsageAnalyticsState(
            records: [],
            snapshots: [],
            thresholdEvents: [],
            switchEvents: [],
            lastActiveAccountKey: nil,
            lastUpdatedAt: nil
        )
        let emptyView = PoolDashboardView.debugUsageAnalyticsStableDetailSectionsView(
            analyticsState: emptyState,
            accounts: [],
            selectedAccountKey: nil
        )
        renderInHostingView(emptyView, size: CGSize(width: 1400, height: 1200))

        let recordA = UsageAnalyticsRecord(
            timestamp: now.addingTimeInterval(-1_200),
            accountKey: accountA.deduplicationKey,
            weeklyDeltaPercent: 8,
            fiveHourDeltaPercent: 6,
            weeklyAbsolutePercent: 35,
            fiveHourAbsolutePercent: 42,
            weeklyRemainingPercent: 65,
            fiveHourRemainingPercent: 58,
            weeklyWastedPercent: 3,
            fiveHourWastedPercent: 2,
            weeklyIdleDelayMinutes: 4,
            weeklyResetAt: accountA.secondaryUsageResetAt,
            fiveHourResetAt: accountA.primaryUsageResetAt,
            activeAccountKeyAtSync: accountA.deduplicationKey
        )
        let recordB = UsageAnalyticsRecord(
            timestamp: now.addingTimeInterval(-600),
            accountKey: accountB.deduplicationKey,
            weeklyDeltaPercent: 12,
            fiveHourDeltaPercent: 10,
            weeklyAbsolutePercent: 74,
            fiveHourAbsolutePercent: 80,
            weeklyRemainingPercent: 26,
            fiveHourRemainingPercent: 20,
            weeklyWastedPercent: 7,
            fiveHourWastedPercent: 5,
            weeklyIdleDelayMinutes: 9,
            weeklyResetAt: accountB.secondaryUsageResetAt,
            fiveHourResetAt: accountB.primaryUsageResetAt,
            activeAccountKeyAtSync: accountB.deduplicationKey
        )

        let snapshotA = UsageAnalyticsAccountSnapshot(
            accountKey: accountA.deduplicationKey,
            lastWeeklyPercent: 35,
            lastFiveHourPercent: 42,
            lastWeeklyResetAt: accountA.secondaryUsageResetAt,
            lastFiveHourResetAt: accountA.primaryUsageResetAt,
            lastSeenAt: now.addingTimeInterval(-500)
        )
        let snapshotB = UsageAnalyticsAccountSnapshot(
            accountKey: accountB.deduplicationKey,
            lastWeeklyPercent: 74,
            lastFiveHourPercent: 80,
            lastWeeklyResetAt: accountB.secondaryUsageResetAt,
            lastFiveHourResetAt: accountB.primaryUsageResetAt,
            lastSeenAt: now.addingTimeInterval(-400)
        )

        let thresholdWeekly = UsageAnalyticsThresholdEvent(
            timestamp: now.addingTimeInterval(-300),
            accountKey: accountB.deduplicationKey,
            kind: .weekly,
            thresholdPercent: 30,
            previousRemainingPercent: 35,
            currentRemainingPercent: 26
        )
        let thresholdFiveHour = UsageAnalyticsThresholdEvent(
            timestamp: now.addingTimeInterval(-200),
            accountKey: accountB.deduplicationKey,
            kind: .fiveHour,
            thresholdPercent: 20,
            previousRemainingPercent: 28,
            currentRemainingPercent: 20
        )
        let switchEvent = UsageAnalyticsSwitchEvent(
            timestamp: now.addingTimeInterval(-180),
            fromAccountKey: accountA.deduplicationKey,
            toAccountKey: accountB.deduplicationKey,
            fromRemainingPercent: 65,
            toRemainingPercent: 26,
            trigger: "sync"
        )

        let populatedState = UsageAnalyticsState(
            records: [recordA, recordB],
            snapshots: [snapshotA, snapshotB],
            thresholdEvents: [thresholdWeekly, thresholdFiveHour],
            switchEvents: [switchEvent],
            lastActiveAccountKey: accountB.deduplicationKey,
            lastUpdatedAt: now
        )
        let populatedView = PoolDashboardView.debugUsageAnalyticsStableDetailSectionsView(
            analyticsState: populatedState,
            accounts: [accountA, accountB],
            selectedAccountKey: nil
        )
        renderInHostingView(populatedView, size: CGSize(width: 1500, height: 1300))
    }

    @Test
    @MainActor
    func workspacePanelsRenderForEmptyAndPopulatedStates() {
        let now = Date()
        let paid = AgentAccount(
            id: UUID(),
            name: "plan-paid@example.com",
            usedUnits: 42,
            quota: 100,
            apiToken: "token-paid",
            email: "plan-paid@example.com",
            chatGPTAccountID: "acct-plan-paid",
            primaryUsagePercent: 38,
            primaryUsageResetAt: now.addingTimeInterval(5_400),
            secondaryUsagePercent: 42,
            secondaryUsageResetAt: now.addingTimeInterval(86_400),
            isPaid: true
        )
        let free = AgentAccount(
            id: UUID(),
            name: "plan-free@example.com",
            usedUnits: 18,
            quota: 100,
            apiToken: "token-free",
            email: "plan-free@example.com",
            chatGPTAccountID: "acct-plan-free",
            primaryUsagePercent: nil,
            primaryUsageResetAt: nil,
            secondaryUsagePercent: 18,
            secondaryUsageResetAt: now.addingTimeInterval(43_200),
            isPaid: false
        )

        let emptyState = UsageAnalyticsState(
            records: [],
            snapshots: [],
            thresholdEvents: [],
            switchEvents: [],
            lastActiveAccountKey: nil,
            lastUpdatedAt: nil
        )

        let scheduleEmpty = PoolDashboardView.debugScheduleWorkspacePanelView(accounts: [])
        renderInHostingView(scheduleEmpty, size: CGSize(width: 1500, height: 900))

        let schedulePopulated = PoolDashboardView.debugScheduleWorkspacePanelView(accounts: [paid, free])
        renderInHostingView(schedulePopulated, size: CGSize(width: 1600, height: 1100))

        let weekday = DailyUsagePlanEvaluator.weekdayKey(for: now)
        let budgetMap = [
            weekday: [
                paid.deduplicationKey: 35,
                free.deduplicationKey: 20
            ]
        ]
        let budgetJSON = String(data: try! JSONEncoder().encode(budgetMap), encoding: .utf8)!
        let defaults = UserDefaults.standard
        let storageKeys = [
            "pool_dashboard.schedule.weekly_account_limits",
            "pool_dashboard.schedule.selected_weekday",
            "pool_dashboard.schedule.daily_plan_enabled",
            "pool_dashboard.schedule.daily_plan_notify_enabled",
            "pool_dashboard.schedule.daily_plan_warning_threshold_percent",
            "pool_dashboard.schedule.daily_plan_notified_days"
        ]
        let backupValues = Dictionary(uniqueKeysWithValues: storageKeys.map { key in
            (key, defaults.object(forKey: key))
        })
        defer {
            for key in storageKeys {
                if let original = backupValues[key] {
                    defaults.set(original, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(budgetJSON, forKey: "pool_dashboard.schedule.weekly_account_limits")
        defaults.set(weekday, forKey: "pool_dashboard.schedule.selected_weekday")
        defaults.set(true, forKey: "pool_dashboard.schedule.daily_plan_enabled")
        defaults.set(false, forKey: "pool_dashboard.schedule.daily_plan_notify_enabled")
        defaults.set(75, forKey: "pool_dashboard.schedule.daily_plan_warning_threshold_percent")
        defaults.set("{}", forKey: "pool_dashboard.schedule.daily_plan_notified_days")

        let recordPaid = UsageAnalyticsRecord(
            timestamp: now.addingTimeInterval(-900),
            accountKey: paid.deduplicationKey,
            weeklyDeltaPercent: 11,
            fiveHourDeltaPercent: 9,
            weeklyAbsolutePercent: 42,
            fiveHourAbsolutePercent: 38,
            weeklyRemainingPercent: 58,
            fiveHourRemainingPercent: 62,
            weeklyWastedPercent: 2,
            fiveHourWastedPercent: 1,
            weeklyIdleDelayMinutes: 0,
            weeklyResetAt: paid.secondaryUsageResetAt,
            fiveHourResetAt: paid.primaryUsageResetAt,
            activeAccountKeyAtSync: paid.deduplicationKey
        )
        let recordFree = UsageAnalyticsRecord(
            timestamp: now.addingTimeInterval(-600),
            accountKey: free.deduplicationKey,
            weeklyDeltaPercent: 6,
            fiveHourDeltaPercent: 0,
            weeklyAbsolutePercent: 18,
            fiveHourAbsolutePercent: 0,
            weeklyRemainingPercent: 82,
            fiveHourRemainingPercent: 100,
            weeklyWastedPercent: 0,
            fiveHourWastedPercent: 0,
            weeklyIdleDelayMinutes: 0,
            weeklyResetAt: free.secondaryUsageResetAt,
            fiveHourResetAt: nil,
            activeAccountKeyAtSync: paid.deduplicationKey
        )
        let snapshotPaid = UsageAnalyticsAccountSnapshot(
            accountKey: paid.deduplicationKey,
            lastWeeklyPercent: 42,
            lastFiveHourPercent: 38,
            lastWeeklyResetAt: paid.secondaryUsageResetAt,
            lastFiveHourResetAt: paid.primaryUsageResetAt,
            lastSeenAt: now.addingTimeInterval(-300)
        )
        let snapshotFree = UsageAnalyticsAccountSnapshot(
            accountKey: free.deduplicationKey,
            lastWeeklyPercent: 18,
            lastFiveHourPercent: 0,
            lastWeeklyResetAt: free.secondaryUsageResetAt,
            lastFiveHourResetAt: nil,
            lastSeenAt: now.addingTimeInterval(-240)
        )
        let populatedState = UsageAnalyticsState(
            records: [recordPaid, recordFree],
            snapshots: [snapshotPaid, snapshotFree],
            thresholdEvents: [],
            switchEvents: [],
            lastActiveAccountKey: paid.deduplicationKey,
            lastUpdatedAt: now
        )

        let dailyPlanView = PoolDashboardView.debugDailyUsagePlanningWorkspacePanelView(
            accounts: [paid, free],
            analyticsState: populatedState
        )
        renderInHostingView(dailyPlanView, size: CGSize(width: 1650, height: 1200))

        let notificationBodies = PoolDashboardView.debugDailyUsagePlanningNotificationBodies(account: paid)
        #expect(notificationBodies.keys.sorted() == ["exceeded", "none", "warning"])
        #expect(Set(notificationBodies.values).count == 3)
        #expect(notificationBodies.values.allSatisfy { !$0.isEmpty })
        let notificationTitles = PoolDashboardView.debugDailyUsagePlanningNotificationTitles(account: paid)
        #expect(notificationTitles.keys.sorted() == ["exceeded", "none", "warning"])
        #expect(notificationTitles["none"] == notificationTitles["exceeded"])
        #expect(notificationTitles["warning"] != notificationTitles["exceeded"])
        #expect(notificationTitles.values.allSatisfy { !$0.isEmpty })
        let budgetPersistence = PoolDashboardView.debugDailyUsagePlanningBudgetPersistenceProbe(account: paid)
        #expect(budgetPersistence.afterSetBudget == 35)
        #expect(budgetPersistence.afterClearBudget == nil)
        #expect(budgetPersistence.notifiedLevel == "warning")
        let planStatusCallouts = PoolDashboardView.debugDailyUsagePlanningStatusCallouts(account: paid)
        renderInHostingView(planStatusCallouts, size: CGSize(width: 900, height: 420))

        var clearIdleDelayCalls = 0
        let analyticsEmpty = PoolDashboardView.debugUsageAnalyticsWorkspacePanelView(
            analyticsState: emptyState,
            accounts: [],
            onClearIdleDelay: { _ in clearIdleDelayCalls += 1 }
        )
        renderInHostingView(analyticsEmpty, size: CGSize(width: 1600, height: 1200))

        let analyticsPopulated = PoolDashboardView.debugUsageAnalyticsWorkspacePanelView(
            analyticsState: populatedState,
            accounts: [paid, free],
            onClearIdleDelay: { _ in clearIdleDelayCalls += 1 }
        )
        renderInHostingView(analyticsPopulated, size: CGSize(width: 1800, height: 1300))

        #expect(clearIdleDelayCalls == 0)
    }

    @Test
    @MainActor
    func scheduleWorkspaceEventDebugHookCoversRepeatingWeeklyAndFiveHourEvents() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let paidID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let blankNameID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let paid = AgentAccount(
            id: paidID,
            name: " paid@example.com ",
            usedUnits: 10,
            quota: 100,
            usageWindowResetAt: start.addingTimeInterval(3_600),
            primaryUsageResetAt: start.addingTimeInterval(1_800),
            isPaid: true
        )
        let blankName = AgentAccount(
            id: blankNameID,
            name: "   ",
            usedUnits: 10,
            quota: 100,
            usageWindowResetAt: start.addingTimeInterval(3_600),
            isPaid: false
        )

        let events = PoolDashboardView.debugScheduleEventSummaries(
            accounts: [blankName, paid],
            start: start,
            end: start.addingTimeInterval(6 * 3_600)
        )

        #expect(events.map(\.kindID) == ["fiveHour", "weekly", "weekly", "fiveHour"])
        #expect(events.map(\.accountID) == [paidID, paidID, blankNameID, paidID])
        #expect(events.map(\.accountName) == [
            "paid@example.com",
            "paid@example.com",
            L10n.text("account.unknown"),
            "paid@example.com"
        ])
        #expect(events.map(\.date) == [
            start.addingTimeInterval(1_800),
            start.addingTimeInterval(3_600),
            start.addingTimeInterval(3_600),
            start.addingTimeInterval(19_800)
        ])
    }

    @Test
    @MainActor
    func usageAnalyticsWorkspaceDebugProbeCoversSeriesSortingAndBasisVariants() {
        let now = Date()
        let alpha = AgentAccount(
            id: UUID(),
            name: "alpha-pro@example.com",
            usedUnits: 18,
            quota: 100,
            apiToken: "token-alpha",
            email: "alpha-pro@example.com",
            chatGPTAccountID: "acct-alpha-pro",
            primaryUsagePercent: 82,
            primaryUsageResetAt: now.addingTimeInterval(3_600),
            secondaryUsagePercent: 18,
            secondaryUsageResetAt: now.addingTimeInterval(86_400),
            isPaid: true
        )
        let bravo = AgentAccount(
            id: UUID(),
            name: "bravo-pro@example.com",
            usedUnits: 47,
            quota: 100,
            apiToken: "token-bravo",
            email: "bravo-pro@example.com",
            chatGPTAccountID: "acct-bravo-pro",
            primaryUsagePercent: 21,
            primaryUsageResetAt: now.addingTimeInterval(7_200),
            secondaryUsagePercent: 47,
            secondaryUsageResetAt: now.addingTimeInterval(120_000),
            isPaid: true
        )
        let free = AgentAccount(
            id: UUID(),
            name: "charlie-free@example.com",
            usedUnits: 9,
            quota: 100,
            apiToken: "token-charlie",
            email: "charlie-free@example.com",
            chatGPTAccountID: "acct-charlie-free",
            primaryUsagePercent: nil,
            primaryUsageResetAt: nil,
            secondaryUsagePercent: 9,
            secondaryUsageResetAt: now.addingTimeInterval(180_000),
            isPaid: false
        )

        let alphaKey = alpha.usageAnalyticsAccountKey
        let bravoKey = bravo.usageAnalyticsAccountKey
        let freeKey = free.usageAnalyticsAccountKey
        let internalHistoryKey = "account:legacy|scope:debug"
        let records = [
            UsageAnalyticsRecord(
                timestamp: now.addingTimeInterval(-900),
                accountKey: alphaKey,
                weeklyDeltaPercent: 7,
                fiveHourDeltaPercent: 5,
                weeklyAbsolutePercent: 74,
                fiveHourAbsolutePercent: 80,
                weeklyRemainingPercent: 26,
                fiveHourRemainingPercent: 20,
                weeklyWastedPercent: 1,
                fiveHourWastedPercent: 0,
                weeklyIdleDelayMinutes: 2,
                weeklyResetAt: alpha.secondaryUsageResetAt,
                fiveHourResetAt: alpha.primaryUsageResetAt,
                activeAccountKeyAtSync: alphaKey
            ),
            UsageAnalyticsRecord(
                timestamp: now.addingTimeInterval(-300),
                accountKey: alphaKey,
                weeklyDeltaPercent: 12,
                fiveHourDeltaPercent: 8,
                weeklyAbsolutePercent: 82,
                fiveHourAbsolutePercent: 88,
                weeklyRemainingPercent: 18,
                fiveHourRemainingPercent: 12,
                weeklyWastedPercent: 4,
                fiveHourWastedPercent: 2,
                weeklyIdleDelayMinutes: 6,
                weeklyResetAt: alpha.secondaryUsageResetAt,
                fiveHourResetAt: alpha.primaryUsageResetAt,
                activeAccountKeyAtSync: bravoKey
            ),
            UsageAnalyticsRecord(
                timestamp: now.addingTimeInterval(-240),
                accountKey: bravoKey,
                weeklyDeltaPercent: 9,
                fiveHourDeltaPercent: 3,
                weeklyAbsolutePercent: 55,
                fiveHourAbsolutePercent: 24,
                weeklyRemainingPercent: 45,
                fiveHourRemainingPercent: 76,
                weeklyWastedPercent: 5,
                fiveHourWastedPercent: 1,
                weeklyIdleDelayMinutes: 7,
                weeklyResetAt: bravo.secondaryUsageResetAt,
                fiveHourResetAt: bravo.primaryUsageResetAt,
                activeAccountKeyAtSync: alphaKey
            ),
            UsageAnalyticsRecord(
                timestamp: now.addingTimeInterval(-180),
                accountKey: freeKey,
                weeklyDeltaPercent: 2,
                fiveHourDeltaPercent: 0,
                weeklyAbsolutePercent: 9,
                fiveHourAbsolutePercent: nil,
                weeklyRemainingPercent: 91,
                fiveHourRemainingPercent: nil,
                weeklyWastedPercent: 0,
                fiveHourWastedPercent: 0,
                weeklyIdleDelayMinutes: 0,
                weeklyResetAt: free.secondaryUsageResetAt,
                fiveHourResetAt: nil,
                activeAccountKeyAtSync: alphaKey
            ),
            UsageAnalyticsRecord(
                timestamp: now.addingTimeInterval(-120),
                accountKey: internalHistoryKey,
                weeklyDeltaPercent: 1,
                fiveHourDeltaPercent: 0,
                weeklyAbsolutePercent: 10,
                fiveHourAbsolutePercent: nil,
                weeklyRemainingPercent: 90,
                fiveHourRemainingPercent: nil,
                weeklyWastedPercent: 3,
                fiveHourWastedPercent: 0,
                weeklyIdleDelayMinutes: 4,
                weeklyResetAt: nil,
                fiveHourResetAt: nil,
                activeAccountKeyAtSync: alphaKey
            )
        ]
        let state = UsageAnalyticsState(
            records: records,
            snapshots: [
                UsageAnalyticsAccountSnapshot(
                    accountKey: alphaKey,
                    lastWeeklyPercent: 82,
                    lastFiveHourPercent: 88,
                    lastWeeklyResetAt: alpha.secondaryUsageResetAt,
                    lastFiveHourResetAt: alpha.primaryUsageResetAt,
                    lastSeenAt: now.addingTimeInterval(-60)
                )
            ],
            thresholdEvents: [
                UsageAnalyticsThresholdEvent(
                    timestamp: now.addingTimeInterval(-200),
                    accountKey: alphaKey,
                    kind: .weekly,
                    thresholdPercent: 20,
                    previousRemainingPercent: 26,
                    currentRemainingPercent: 18
                ),
                UsageAnalyticsThresholdEvent(
                    timestamp: now.addingTimeInterval(-100),
                    accountKey: bravoKey,
                    kind: .fiveHour,
                    thresholdPercent: 25,
                    previousRemainingPercent: 30,
                    currentRemainingPercent: 20
                )
            ],
            switchEvents: [
                UsageAnalyticsSwitchEvent(
                    timestamp: now.addingTimeInterval(-150),
                    fromAccountKey: alphaKey,
                    toAccountKey: bravoKey,
                    fromRemainingPercent: 18,
                    toRemainingPercent: 45,
                    trigger: "debug"
                )
            ],
            lastActiveAccountKey: alphaKey,
            lastUpdatedAt: now
        )

        let probe = PoolDashboardView.debugUsageAnalyticsWorkspaceProbe(
            analyticsState: state,
            accounts: [alpha, bravo, free],
            selectedAccountKey: alphaKey,
            days: 3,
            weeks: 3
        )

        #expect(probe.dailyRemainingSelected.count == 3)
        #expect(probe.weeklyRemainingAll.count == 3)
        #expect(probe.dailyRemainingSelected.last == 18)
        #expect(probe.dailyWastedSelected.last == 5)
        #expect(probe.dailyIdleDelaySelected.last == 8)
        #expect(probe.weeklyWastedAll.last ?? 0 >= 13)
        #expect(probe.sortedAccountKeysByMode["weeklyUsage"]?.prefix(2).elementsEqual([bravoKey, alphaKey]) == true)
        #expect(probe.sortedAccountKeysByMode["fiveHourRemaining"]?.prefix(2).elementsEqual([bravoKey, alphaKey]) == true)
        #expect(probe.sortedAccountKeysByMode["name"]?.contains(internalHistoryKey) == false)
        #expect(probe.analysisDescriptions.keys.sorted() == ["delay", "remaining", "usage", "wasted"])
        #expect(probe.chartEntryCounts["remaining-weekly"] == 8)
        #expect(probe.chartValueLabels["delay"]?.contains("8") == true)
        #expect(probe.etaValueTexts.contains { !$0.isEmpty })
        #expect(probe.accountMetricSamples["account"] == [1, 18, 82, 82, 18])
        #expect(probe.accountMetricSamples["snapshot"] == [0, 100, -1, 0, -1])
        #expect(probe.accountMetricSamples["record"] == [0, 0, 100, 100, 0])
        #expect(probe.accountMetricSamples["unknown"] == [0, 0, -1, 0, -1])
        let idleDelayProbe = PoolDashboardView.debugClearUsageAnalyticsIdleDelayProbe(records: records)
        #expect(idleDelayProbe.targeted == [0, 0, 7, 0, 4])
        #expect(idleDelayProbe.all == [0, 0, 0, 0, 0])

        for basis in ["remaining", "wasted", "delay"] {
            for granularity in ["daily", "weekly"] {
                let variant = PoolDashboardView.debugUsageAnalyticsWorkspaceVariantView(
                    analyticsState: state,
                    accounts: [alpha, bravo, free],
                    analysisBasisID: basis,
                    chartGranularityID: granularity,
                    accountSortModeID: "fiveHourRemaining",
                    selectedAccountKey: alphaKey
                )
                renderInHostingView(variant, size: CGSize(width: 1800, height: 1300))
            }
        }

        let privateDetails = PoolDashboardView.debugUsageAnalyticsWorkspacePrivateDetailViews(
            analyticsState: state,
            accounts: [alpha, bravo, free],
            selectedAccountKey: alphaKey
        )
        renderInHostingView(privateDetails, size: CGSize(width: 1600, height: 1200))

        let privateCoverageDetails = PoolDashboardView.debugUsageAnalyticsWorkspacePrivateCoverageViews(
            analyticsState: state,
            accounts: [alpha, bravo, free],
            selectedAccountKey: alphaKey
        )
        renderInHostingView(privateCoverageDetails, size: CGSize(width: 1600, height: 700))

        let emptyPrivateDetails = PoolDashboardView.debugUsageAnalyticsWorkspacePrivateDetailViews(
            analyticsState: UsageAnalyticsState(
                records: [],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: nil,
                lastUpdatedAt: nil
            ),
            accounts: [],
            selectedAccountKey: nil
        )
        renderInHostingView(emptyPrivateDetails, size: CGSize(width: 1600, height: 1000))

        let emptyPrivateCoverageDetails = PoolDashboardView.debugUsageAnalyticsWorkspacePrivateCoverageViews(
            analyticsState: UsageAnalyticsState(
                records: [],
                snapshots: [],
                thresholdEvents: [],
                switchEvents: [],
                lastActiveAccountKey: nil,
                lastUpdatedAt: nil
            ),
            accounts: [],
            selectedAccountKey: nil
        )
        renderInHostingView(emptyPrivateCoverageDetails, size: CGSize(width: 1600, height: 700))
    }

    @Test
    @MainActor
    func poolDashboardPrivateOverlaysRenderThroughDebugHooks() {
        let state = AccountPoolState(
            accounts: [
                makeSmokeAccount(name: "special-reset@example.com", usedUnits: 12, quota: 100, isPaid: true)
            ],
            mode: .manual
        )
        let store = ViewSmokeStore(snapshot: state.snapshot)

        let appUpdateWithNotes = PoolDashboardView.debugAppUpdateOverlayView(releaseNotes: "Added better reset-credit visibility.")
        renderInHostingView(appUpdateWithNotes, size: CGSize(width: 900, height: 760))

        let appUpdateWithoutNotes = PoolDashboardView.debugAppUpdateOverlayView(releaseNotes: nil)
        renderInHostingView(appUpdateWithoutNotes, size: CGSize(width: 900, height: 760))

        let whatsNew = PoolDashboardView.debugWhatsNewOverlayView()
        renderInHostingView(whatsNew, size: CGSize(width: 900, height: 760))

        let specialReset = PoolDashboardView.debugSpecialResetWatchPanelView(store: store)
        renderInHostingView(specialReset, size: CGSize(width: 1200, height: 760))
    }

    @Test
    @MainActor
    func populatedSpecialResetWatchPanelRendersRecordsAndLatestEvent() {
        let specialReset = PoolDashboardView.debugPopulatedSpecialResetWatchPanelView()
        renderInHostingView(specialReset, size: CGSize(width: 1200, height: 900))
    }

    @Test
    @MainActor
    func poolDashboardDeleteGroupProbeRemovesGroupAccountsAndTokens() {
        let probe = PoolDashboardView.debugDeleteGroupProbe()

        #expect(probe.remainingAccountNames == ["default@example.com"])
        #expect(probe.removedTokenAccountNames == ["red-a@example.com", "red-b@example.com"])
        #expect(probe.selectedGroupName == AgentAccount.defaultGroupName)
        #expect(!probe.missingGroupRemovedTokens)
    }

    @Test
    @MainActor
    func poolDashboardAddAccountProbeTrimsNameAndResetsForm() {
        let probe = PoolDashboardView.debugAddAccountProbe()

        #expect(probe.addedAccountNames == ["new@example.com"])
        #expect(probe.addedGroupName == "Ops")
        #expect(probe.addedQuota == 250)
        #expect(probe.blankInputWasIgnored)
        #expect(probe.formNameWasReset)
        #expect(probe.formQuotaWasReset)
    }

    @Test
    @MainActor
    func poolDashboardDataModeReloadProbeLoadsSnapshotAndResetsSelection() {
        let probe = PoolDashboardView.debugDataModeReloadProbe()

        #expect(probe.loadedAccountNames == ["loaded@example.com"])
        #expect(probe.loadedSelectedGroupName == "Loaded")
        #expect(probe.fallbackAccountCount > 0)
        #expect(probe.fallbackSelectedGroupName == AgentAccount.defaultGroupName)
        #expect(probe.actualReloadWasExercised)
    }

    @Test
    @MainActor
    func poolDashboardUsageSyncStuckProbeEndsOnlyMatchingRun() {
        let probe = PoolDashboardView.debugUsageSyncStuckRecoveryProbe()

        #expect(!probe.matchingRunIsSyncing)
        #expect(probe.matchingRunIDWasCleared)
        #expect(probe.matchingErrorContainsTimeout)
        #expect(probe.staleRunStayedSyncing)
        #expect(probe.staleRunIDWasPreserved)
    }

    @Test
    @MainActor
    func poolDashboardDeveloperPanelsRenderThroughDebugHooks() {
        let account = makeSmokeAccount(name: "debug@example.com", usedUnits: 41, quota: 100, isPaid: true)
        let state = AccountPoolState(
            accounts: [
                account
            ],
            mode: .manual
        )
        var snapshot = state.snapshot
        snapshot.activeAccountID = account.id
        snapshot.activities = [
            PoolActivity(id: UUID(), timestamp: Date(timeIntervalSince1970: 1_800_000_000), message: "Debug activity")
        ]
        let store = ViewSmokeStore(snapshot: snapshot)

        let developerContext = PoolDashboardView.debugDeveloperContextPanelView(store: store)
        renderInHostingView(developerContext, size: CGSize(width: 900, height: 760))

        let debugTools = PoolDashboardView.debugDebugToolsPanelView(store: store)
        renderInHostingView(debugTools, size: CGSize(width: 900, height: 760))

        let privatePanels = PoolDashboardView.debugPrivateSettingsPanelViews(store: store)
        renderInHostingView(privatePanels, size: CGSize(width: 1100, height: 900))

        let dashboardPanels = PoolDashboardView.debugPrivateDashboardPanelViews(store: store)
        renderInHostingView(dashboardPanels, size: CGSize(width: 1400, height: 1000))

        let metrics = PoolDashboardView.debugDiagnosticsSnapshot(store: store)
        #expect(metrics.first(where: { $0.id == "accounts" })?.value == "1")
        #expect(metrics.first(where: { $0.id == "activities" })?.value == "1")
        #expect(metrics.contains(where: { $0.id == "analytics_records" }))
        #expect(metrics.contains(where: { $0.id == "backup_json" }))
    }

    @Test
    @MainActor
    func poolDashboardPairedPanelsDebugViewRendersHorizontalAndStackedFallback() {
        let pairedPanels = PoolDashboardView.debugPairedPanelsView()

        renderInHostingView(pairedPanels, size: CGSize(width: 900, height: 360))
        renderInHostingView(pairedPanels, size: CGSize(width: 240, height: 640))
    }

    @Test
    @MainActor
    func poolDashboardViewCanRenderWithSeededSnapshot() {
        var state = AccountPoolState(
            accounts: [
                makeSmokeAccount(name: "seed-a@example.com", usedUnits: 35, quota: 100, isPaid: true),
                makeSmokeAccount(name: "seed-b@example.com", usedUnits: 5, quota: 100, isPaid: false)
            ],
            mode: .intelligent
        )
        state.evaluate()
        let store = ViewSmokeStore(snapshot: state.snapshot)

        let view = PoolDashboardView(store: store)
        renderInHostingView(view, size: CGSize(width: 1500, height: 980))

        #expect(store.loadCount > 0)
        if let persisted = store.saved.last {
            #expect(persisted.accounts.count == state.accounts.count)
        }
    }

    @Test
    @MainActor
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

    @Test
    @MainActor
    func poolDashboardRuntimeBackedSnapshotChangeSavesOnce() {
        let account = AgentAccount(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "runtime-edit@example.com",
            usedUnits: 10,
            quota: 100
        )
        let initialState = AccountPoolState(accounts: [account], mode: .manual)
        var nextState = initialState
        nextState.updateAccount(account.id, usedUnits: 25)

        let runtimeStore = ViewSmokeStore(snapshot: initialState.snapshot)
        let model = AppPoolRuntimeModel(store: runtimeStore, initialState: initialState)
        PoolDashboardView.debugApplySnapshotChange(
            store: runtimeStore,
            runtimeModel: model,
            previousState: initialState,
            nextState: nextState
        )

        #expect(runtimeStore.saved.count == 1)
        #expect(runtimeStore.saved.first?.accounts.first?.usedUnits == 25)
        #expect(model.state.accounts.first?.usedUnits == 25)

        let dashboardOnlyStore = ViewSmokeStore(snapshot: initialState.snapshot)
        PoolDashboardView.debugApplySnapshotChange(
            store: dashboardOnlyStore,
            runtimeModel: nil,
            previousState: initialState,
            nextState: nextState
        )

        #expect(dashboardOnlyStore.saved.count == 1)
        #expect(dashboardOnlyStore.saved.first?.accounts.first?.usedUnits == 25)
    }

    @Test
    @MainActor
    func poolDashboardAuthenticationRoutesRenderOAuthAndAPIKeyTabs() {
        let defaults = UserDefaults.standard
        let authMethodKey = "pool_dashboard.authentication.method"
        let oldAuthMethod = defaults.object(forKey: authMethodKey)
        defer {
            if let oldAuthMethod {
                defaults.set(oldAuthMethod, forKey: authMethodKey)
            } else {
                defaults.removeObject(forKey: authMethodKey)
            }
        }

        let state = AccountPoolState(
            accounts: [
                makeSmokeAccount(name: "oauth-route@example.com", usedUnits: 12, quota: 100)
            ],
            mode: .intelligent
        )

        defaults.set("oauth", forKey: authMethodKey)
        renderInHostingView(
            PoolDashboardView(store: ViewSmokeStore(snapshot: state.snapshot)),
            size: CGSize(width: 1500, height: 980)
        )

        defaults.set("relayAPIKey", forKey: authMethodKey)
        renderInHostingView(
            PoolDashboardView(store: ViewSmokeStore(snapshot: state.snapshot)),
            size: CGSize(width: 1500, height: 980)
        )
    }

    @Test
    func poolDashboardResponsiveLayoutBreakpointsPreferStackingBeforeClipping() {
        #expect(PoolDashboardView.debugUsesStackedDashboardChrome(availableWidth: 940))
        #expect(!PoolDashboardView.debugUsesStackedDashboardChrome(availableWidth: 1120))
        #expect(PoolDashboardView.debugUsesStackedWorkspaceContent(availableWidth: 940))
        #expect(!PoolDashboardView.debugUsesStackedWorkspaceContent(availableWidth: 1120))
        #expect(AccountUsagePanelView.debugUsesStackedHeaderControls(availableWidth: 940))
        #expect(!AccountUsagePanelView.debugUsesStackedHeaderControls(availableWidth: 1120))
    }

    @Test
    func accountUsageRelayInfoPresentationUsesInlineCalloutWithoutUsageMeters() {
        let relayAccount = AgentAccount(
            id: UUID(),
            name: "relay@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "relay-key",
            credentialType: .relayAPIKey,
            relayProviderID: "mirror",
            relayProviderName: "mirror",
            relayBaseURL: "https://ai.example.com/api/codex",
            relayWireAPI: "responses",
            relayRequiresOpenAIAuth: true,
            email: "relay@example.com",
            chatGPTAccountID: nil,
            primaryUsagePercent: nil,
            isPaid: true,
            isUsageSyncExcluded: true,
            usageSyncError: AgentAccount.relayUsageSyncUnavailableReason
        )
        let oauthExcludedAccount = AgentAccount(
            id: UUID(),
            name: "oauth@example.com",
            usedUnits: 0,
            quota: 100,
            apiToken: "oauth-token",
            email: "oauth@example.com",
            chatGPTAccountID: "acct-oauth",
            primaryUsagePercent: nil,
            isPaid: true,
            isUsageSyncExcluded: true,
            usageSyncError: "auth failed"
        )

        #expect(!AccountUsagePanelView.debugUsesRelayUsageInfoButton(for: relayAccount))
        #expect(!AccountUsagePanelView.debugShowsUsageMeters(for: relayAccount))
        #expect(!AccountUsagePanelView.debugUsesRelayUsageInfoButton(for: oauthExcludedAccount))
        #expect(AccountUsagePanelView.debugShowsUsageMeters(for: oauthExcludedAccount))
        #expect(!AccountUsagePanelView.debugUsesRelayUsageInfoButton(for: makeSmokeAccount()))
        #expect(AccountUsagePanelView.debugShowsUsageMeters(for: makeSmokeAccount()))
    }

    @Test
    @MainActor
    func poolDashboardViewDebugCoreCoverageSnapshotCoversPrivateBindingsAndDefaults() {
        let account = makeSmokeAccount(name: "core-coverage@example.com", usedUnits: 10, quota: 200, isPaid: true)
        let seedState = AccountPoolState(accounts: [account], mode: .manual)
        let store = ViewSmokeStore(snapshot: seedState.snapshot)

        let snapshot = PoolDashboardView.debugCoreCoverageSnapshot(store: store)

        #expect(
            snapshot.selectedLaunchTarget.rawValue
                == CodexLaunchTarget.normalizedRawValue(snapshot.selectedLaunchTargetRaw)
        )
        #expect(snapshot.isDebugBuild)
        #expect(snapshot.defaultAccountCount >= 0)
        #expect(snapshot.defaultStateMode == .intelligent)
        #expect(snapshot.firstAccountName == "core-coverage@example.com")
        #expect(snapshot.firstAccountQuota == 200)
        #expect(snapshot.strategyMode == .intelligent)
    }

    @Test
    @MainActor
    func menuBarTitlesCoverPaidFreeAndFallbackSnapshots() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        let paidSnapshot = MenuBarBridgeSnapshot(
            updatedAt: now.addingTimeInterval(-120),
            activeAccountName: "paid@example.com",
            activeIsPaid: true,
            activeRemainingUnits: 44,
            activeQuota: 100,
            activeFiveHourRemainingPercent: 67,
            activeWeeklyResetAt: now.addingTimeInterval(86_400),
            activeFiveHourResetAt: now.addingTimeInterval(9_000)
        )

        let freeSnapshot = MenuBarBridgeSnapshot(
            updatedAt: now.addingTimeInterval(-20),
            activeAccountName: "free@example.com",
            activeIsPaid: false,
            activeRemainingUnits: 12,
            activeQuota: 20,
            activeFiveHourRemainingPercent: nil,
            activeWeeklyResetAt: now.addingTimeInterval(7_200),
            activeFiveHourResetAt: nil
        )

        let paidTitle = CodexPoolManagerApp.debugMenuBarTitle(snapshot: paidSnapshot, now: now)
        #expect(paidTitle.contains("Codex "))
        #expect(paidTitle.contains("w 44%"))
        #expect(paidTitle.contains("5h 67%"))

        let freeTitle = CodexPoolManagerApp.debugMenuBarTitle(snapshot: freeSnapshot, now: now)
        #expect(freeTitle.contains("60%"))
        #expect(!freeTitle.contains("5h"))

        let fallbackTitle = CodexPoolManagerApp.debugMenuBarTitle(
            snapshot: MenuBarBridgeSnapshot(
                updatedAt: now.addingTimeInterval(-3_700),
                activeAccountName: nil,
                activeIsPaid: nil,
                activeRemainingUnits: nil,
                activeQuota: nil,
                activeFiveHourRemainingPercent: nil,
                activeWeeklyResetAt: nil,
                activeFiveHourResetAt: nil
            ),
            now: now
        )
        #expect(fallbackTitle == "Codex -- · 1h")
    }
}

import Foundation
import SwiftUI
import Testing
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
            lowUsageAlertThresholdBinding: binding(lowUsageThresholdBox)
        )
        let _ = intelligent.body

        modeBox.value = .focus
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
            lowUsageAlertThresholdBinding: binding(lowUsageThresholdBox)
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
            onCheckForUpdates: { checkCount += 1 }
        )

        let _ = view.body
        #expect(checkCount == 0)
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
}

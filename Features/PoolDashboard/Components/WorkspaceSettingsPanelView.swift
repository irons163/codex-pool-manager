import SwiftUI

struct WorkspaceSettingsPanelView: View {
    let switchWithoutLaunchingBinding: Binding<Bool>
    let launchTargetBinding: Binding<String>
    let autoSyncEnabledBinding: Binding<Bool>
    let autoSyncIntervalSecondsBinding: Binding<Double>
    let languageOverrideBinding: Binding<String>
    let appearanceOverrideBinding: Binding<String>
    let usageAnalyticsMaxStoredRecordsBinding: Binding<Int>
    let languageOptions: [L10n.LanguageOption]
    let appUpdateAutoCheckEnabledBinding: Binding<Bool>
    let isCheckingForUpdates: Bool
    let appUpdateStatusMessage: String?
    let onCheckForUpdates: () -> Void

    private var switchAndLaunchBinding: Binding<Bool> {
        Binding(
            get: { !switchWithoutLaunchingBinding.wrappedValue },
            set: { switchWithoutLaunchingBinding.wrappedValue = !$0 }
        )
    }

    private var normalizedLanguageBinding: Binding<String> {
        Binding(
            get: { L10n.normalizedLanguageOverrideCode(languageOverrideBinding.wrappedValue) },
            set: { languageOverrideBinding.wrappedValue = L10n.normalizedLanguageOverrideCode($0) }
        )
    }

    private var normalizedLaunchTargetBinding: Binding<String> {
        Binding(
            get: { CodexLaunchTarget.normalizedRawValue(launchTargetBinding.wrappedValue) },
            set: { launchTargetBinding.wrappedValue = CodexLaunchTarget.normalizedRawValue($0) }
        )
    }

    private var normalizedAppearanceBinding: Binding<String> {
        Binding(
            get: { AppAppearancePreference.normalizedRawValue(appearanceOverrideBinding.wrappedValue) },
            set: { appearanceOverrideBinding.wrappedValue = AppAppearancePreference.normalizedRawValue($0) }
        )
    }

    var body: some View {
        GroupBox(L10n.text("strategy.general_settings")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.strategyPanelSpacing) {
                Toggle(L10n.text("strategy.switch_without_launch"), isOn: switchAndLaunchBinding)
                    .toggleStyle(.switch)
                    .tint(PoolDashboardTheme.glowA)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)
                    .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text(L10n.text("strategy.launch_target"))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Picker(L10n.text("strategy.launch_target"), selection: normalizedLaunchTargetBinding) {
                        ForEach(CodexLaunchTarget.pickerTargets) { target in
                            Text(target.title).tag(target.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Toggle(L10n.text("strategy.auto_sync_enabled"), isOn: autoSyncEnabledBinding)
                        .toggleStyle(.switch)
                        .tint(PoolDashboardTheme.glowA)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Text(
                        L10n.text(
                            "strategy.auto_sync_interval_seconds_format",
                            Int(autoSyncIntervalSecondsBinding.wrappedValue)
                        )
                    )
                    .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Slider(value: autoSyncIntervalSecondsBinding, in: 5...300, step: 1)
                        .tint(PoolDashboardTheme.glowA)
                        .disabled(!autoSyncEnabledBinding.wrappedValue)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text(L10n.text("strategy.language"))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Picker(L10n.text("strategy.language"), selection: normalizedLanguageBinding) {
                        ForEach(languageOptions) { option in
                            Text(option.title).tag(option.code)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Text(L10n.text("strategy.appearance"))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    Picker(L10n.text("strategy.appearance"), selection: normalizedAppearanceBinding) {
                        Text(L10n.text("strategy.appearance.system")).tag(AppAppearancePreference.system.rawValue)
                        Text(L10n.text("strategy.appearance.dark")).tag(AppAppearancePreference.dark.rawValue)
                        Text(L10n.text("strategy.appearance.light")).tag(AppAppearancePreference.light.rawValue)
                    }
                    .pickerStyle(.menu)
                    .tint(PoolDashboardTheme.glowA)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Stepper(
                        value: usageAnalyticsMaxStoredRecordsBinding,
                        in: UsageAnalyticsEngine.minStoredRecords...UsageAnalyticsEngine.maxStoredRecordsLimit,
                        step: UsageAnalyticsEngine.maxStoredRecordsStep
                    ) {
                        Text(
                            L10n.text(
                                "settings.usage_analytics_history_limit_format",
                                usageAnalyticsMaxStoredRecordsBinding.wrappedValue
                            )
                        )
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    }

                    Text(L10n.text("settings.usage_analytics_history_limit_hint"))
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
                .dashboardInfoCard()

                VStack(alignment: .leading, spacing: PoolDashboardTheme.compactFieldSpacing) {
                    Toggle(L10n.text("update.auto_check"), isOn: appUpdateAutoCheckEnabledBinding)
                        .toggleStyle(.switch)
                        .tint(PoolDashboardTheme.glowA)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)

                    HStack(spacing: 8) {
                        Button(L10n.text("update.check_now")) {
                            onCheckForUpdates()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PoolDashboardTheme.glowA)
                        .disabled(isCheckingForUpdates)

                        if isCheckingForUpdates {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let appUpdateStatusMessage, !appUpdateStatusMessage.isEmpty {
                        Text(appUpdateStatusMessage)
                            .font(.caption)
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                    }
                }
                .dashboardInfoCard()
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}

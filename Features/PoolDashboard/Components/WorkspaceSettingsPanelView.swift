import SwiftUI

struct WorkspaceSettingsPanelView: View {
    let switchWithoutLaunchingBinding: Binding<Bool>
    let autoSyncEnabledBinding: Binding<Bool>
    let autoSyncIntervalSecondsBinding: Binding<Double>
    let languageOverrideBinding: Binding<String>
    let appearanceOverrideBinding: Binding<String>
    let languageOptions: [L10n.LanguageOption]

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
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }
}

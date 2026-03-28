import SwiftUI

struct PoolDashboardStrategyBindingAdapter {
    let state: Binding<AccountPoolState>

    var mode: Binding<SwitchMode> {
        Binding(
            get: {
                let currentMode = state.wrappedValue.mode
                return currentMode == .manual ? .intelligent : currentMode
            },
            set: { newMode in
                state.wrappedValue.setMode(newMode == .manual ? .intelligent : newMode)
            }
        )
    }

    var manualSelection: Binding<UUID> {
        Binding(
            get: {
                if let manualID = state.wrappedValue.manualAccountID {
                    return manualID
                }
                return state.wrappedValue.accounts.first?.id ?? UUID()
            },
            set: { newID in
                state.wrappedValue.selectManualAccount(newID)
            }
        )
    }

    var minSwitchInterval: Binding<Double> {
        Binding(
            get: { state.wrappedValue.minSwitchInterval },
            set: { newValue in
                updateSwitchSettings(minSwitchInterval: newValue)
            }
        )
    }

    var lowThreshold: Binding<Double> {
        Binding(
            get: { state.wrappedValue.lowUsageThresholdRatio },
            set: { newValue in
                updateSwitchSettings(lowUsageThresholdRatio: newValue)
            }
        )
    }

    var minUsageDelta: Binding<Double> {
        Binding(
            get: { state.wrappedValue.minUsageRatioDeltaToSwitch },
            set: { newValue in
                updateSwitchSettings(minUsageRatioDeltaToSwitch: newValue)
            }
        )
    }

    var switchWithoutLaunching: Binding<Bool> {
        Binding(
            get: { state.wrappedValue.switchWithoutLaunching },
            set: { newValue in
                state.wrappedValue.setSwitchWithoutLaunching(newValue)
            }
        )
    }

    var autoSyncEnabled: Binding<Bool> {
        Binding(
            get: { state.wrappedValue.autoSyncEnabled },
            set: { newValue in
                state.wrappedValue.setAutoSyncEnabled(newValue)
            }
        )
    }

    var autoSyncIntervalSeconds: Binding<Double> {
        Binding(
            get: { state.wrappedValue.autoSyncIntervalSeconds },
            set: { newValue in
                state.wrappedValue.setAutoSyncIntervalSeconds(newValue)
            }
        )
    }

    private func updateSwitchSettings(
        minSwitchInterval: Double? = nil,
        lowUsageThresholdRatio: Double? = nil,
        minUsageRatioDeltaToSwitch: Double? = nil
    ) {
        state.wrappedValue.updateSwitchSettings(
            minSwitchInterval: minSwitchInterval,
            lowUsageThresholdRatio: lowUsageThresholdRatio,
            minUsageRatioDeltaToSwitch: minUsageRatioDeltaToSwitch
        )
    }
}

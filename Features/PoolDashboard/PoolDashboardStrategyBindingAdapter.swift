import SwiftUI

struct PoolDashboardStrategyBindingAdapter {
    let state: Binding<AccountPoolState>

    var mode: Binding<SwitchMode> {
        Binding(
            get: { state.wrappedValue.mode },
            set: { newMode in
                state.wrappedValue.setMode(newMode)
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
                state.wrappedValue.updateSwitchSettings(minSwitchInterval: newValue)
            }
        )
    }

    var lowThreshold: Binding<Double> {
        Binding(
            get: { state.wrappedValue.lowUsageThresholdRatio },
            set: { newValue in
                state.wrappedValue.updateSwitchSettings(lowUsageThresholdRatio: newValue)
            }
        )
    }

    var minUsageDelta: Binding<Double> {
        Binding(
            get: { state.wrappedValue.minUsageRatioDeltaToSwitch },
            set: { newValue in
                state.wrappedValue.updateSwitchSettings(minUsageRatioDeltaToSwitch: newValue)
            }
        )
    }
}

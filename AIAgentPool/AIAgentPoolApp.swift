//
//  AIAgentPoolApp.swift
//  AIAgentPool
//
//  Created by Phil on 2026/3/24.
//

import SwiftUI

@main
struct AIAgentPoolApp: App {
    @AppStorage(L10n.languageOverrideKey) private var appLanguageOverride = L10n.systemLanguageCode

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(appLanguageOverride)
                .environment(\.locale, L10n.locale(for: appLanguageOverride))
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}

//
//  AIAgentPoolApp.swift
//  AIAgentPool
//
//  Created by Phil on 2026/3/24.
//

import SwiftUI

@main
struct AIAgentPoolApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            SidebarCommands()
        }
    }
}

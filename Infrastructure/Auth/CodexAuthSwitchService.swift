import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum CodexAuthSwitchError: LocalizedError {
    case appStillRunning(bundleIdentifier: String)
    case appNotFound
    case unsupportedPlatform
    case launchFailedAfterSwitch(reason: String)

    var errorDescription: String? {
        switch self {
        case let .appStillRunning(bundleIdentifier):
            return String(
                format: L10n.text("switch.service.error.app_still_running_format"),
                bundleIdentifier
            )
        case .appNotFound:
            return L10n.text("switch.service.error.app_not_found")
        case .unsupportedPlatform:
            return L10n.text("switch.service.error.unsupported_platform")
        case let .launchFailedAfterSwitch(reason):
            return "Launch failed after auth switch: \(reason)"
        }
    }
}

enum CodexLaunchTarget: String, CaseIterable, Identifiable, Codable {
    case auto
    case chatgpt
    case codex
    case vscode
    case vscodeInsiders
    case cursor
    case windsurf
    case antigravity
    case terminal
    case iterm2
    case xcode
    case androidStudio
    case intellijIDEA
    case pycharm
    case webstorm
    case zed
    case finder

    var id: String { rawValue }

    static let defaultPickerTarget: CodexLaunchTarget = .codex

    static var supportedTargets: [CodexLaunchTarget] {
        [.codex, .chatgpt, .terminal, .iterm2]
    }

    static var advancedTargets: [CodexLaunchTarget] {
        [.vscode, .vscodeInsiders, .cursor, .windsurf, .antigravity, .zed]
    }

    static var pickerTargets: [CodexLaunchTarget] {
        supportedTargets + advancedTargets
    }

    static func normalizedRawValue(_ rawValue: String) -> String {
        guard let value = CodexLaunchTarget(rawValue: rawValue),
              pickerTargets.contains(value)
        else {
            return defaultPickerTarget.rawValue
        }
        if value == .auto {
            return defaultPickerTarget.rawValue
        }
        return value.rawValue
    }

    var title: String {
        switch self {
        case .auto: return L10n.text("strategy.launch_target.auto")
        case .chatgpt: return "ChatGPT"
        case .codex: return "Codex"
        case .vscode: return "VS Code"
        case .vscodeInsiders: return "VS Code Insiders"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .antigravity: return "Antigravity"
        case .terminal: return "Terminal"
        case .iterm2: return "iTerm2"
        case .xcode: return "Xcode"
        case .androidStudio: return "Android Studio"
        case .intellijIDEA: return "IntelliJ IDEA"
        case .pycharm: return "PyCharm"
        case .webstorm: return "WebStorm"
        case .zed: return "Zed"
        case .finder: return "Finder"
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .auto:
            return []
        case .chatgpt:
            return ["com.openai.chatgpt"]
        case .codex:
            return ["com.openai.codex"]
        case .vscode:
            return ["com.microsoft.VSCode"]
        case .vscodeInsiders:
            return ["com.microsoft.VSCodeInsiders"]
        case .cursor:
            return ["com.todesktop.230313mzl4w4u92"]
        case .windsurf:
            return ["com.exafunction.windsurf"]
        case .antigravity:
            return []
        case .terminal:
            return ["com.apple.Terminal"]
        case .iterm2:
            return ["com.googlecode.iterm2"]
        case .xcode:
            return ["com.apple.dt.Xcode"]
        case .androidStudio:
            return ["com.google.android.studio"]
        case .intellijIDEA:
            return ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .pycharm:
            return ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        case .webstorm:
            return ["com.jetbrains.WebStorm"]
        case .zed:
            return ["dev.zed.Zed"]
        case .finder:
            return ["com.apple.finder"]
        }
    }

    var appURLs: [URL] {
        switch self {
        case .auto:
            return []
        case .chatgpt:
            return [URL(fileURLWithPath: "/Applications/ChatGPT.app")]
        case .codex:
            return [URL(fileURLWithPath: "/Applications/Codex.app")]
        case .vscode:
            return [URL(fileURLWithPath: "/Applications/Visual Studio Code.app")]
        case .vscodeInsiders:
            return [URL(fileURLWithPath: "/Applications/Visual Studio Code - Insiders.app")]
        case .cursor:
            return [URL(fileURLWithPath: "/Applications/Cursor.app")]
        case .windsurf:
            return [URL(fileURLWithPath: "/Applications/Windsurf.app")]
        case .antigravity:
            return [URL(fileURLWithPath: "/Applications/Antigravity.app")]
        case .terminal:
            return [
                URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                URL(fileURLWithPath: "/Applications/Utilities/Terminal.app"),
                URL(fileURLWithPath: "/Applications/Terminal.app")
            ]
        case .iterm2:
            return [URL(fileURLWithPath: "/Applications/iTerm.app")]
        case .xcode:
            return [URL(fileURLWithPath: "/Applications/Xcode.app")]
        case .androidStudio:
            return [URL(fileURLWithPath: "/Applications/Android Studio.app")]
        case .intellijIDEA:
            return [URL(fileURLWithPath: "/Applications/IntelliJ IDEA.app")]
        case .pycharm:
            return [URL(fileURLWithPath: "/Applications/PyCharm.app")]
        case .webstorm:
            return [URL(fileURLWithPath: "/Applications/WebStorm.app")]
        case .zed:
            return [URL(fileURLWithPath: "/Applications/Zed.app")]
        case .finder:
            return [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        }
    }
}

struct CodexAuthSwitchService {
    var logger: @Sendable (String) -> Void = { _ in }

    private let autoLaunchOrder: [CodexLaunchTarget] = [
        .chatgpt,
        .codex,
        .terminal,
        .iterm2,
        .vscode,
        .vscodeInsiders,
        .cursor,
        .windsurf,
        .antigravity,
        .zed
    ]
    private let appCloseTimeoutNanoseconds: UInt64 = 8_000_000_000
    private let appExitPollIntervalNanoseconds: UInt64 = 200_000_000
    private let launchRetryIntervalNanoseconds: UInt64 = 500_000_000
    private let deferredLaunchMonitorTimeoutNanoseconds: UInt64 = 3_600_000_000_000

    private var isSandboxedEnvironment: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    @MainActor
    func performSwitchOnly(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String
    ) throws {
        logger(String(format: L10n.text("switch.service.log.using_auth_file_format"), authFileURL.path))
        let hasSecurityScope = authFileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                authFileURL.stopAccessingSecurityScopedResource()
            }
        }

        try rewriteAuthFile(
            authFileURL: authFileURL,
            account: account,
            chatGPTAccountID: chatGPTAccountID
        )
        logger(L10n.text("switch.service.log.launch_skipped_by_setting"))
    }

    @MainActor
    func performSwitchAndLaunch(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String,
        launchTarget: CodexLaunchTarget = .auto
    ) async throws {
        logger(String(format: L10n.text("switch.service.log.using_auth_file_format"), authFileURL.path))
        let hasSecurityScope = authFileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityScope {
                authFileURL.stopAccessingSecurityScopedResource()
            }
        }

        try rewriteAuthFile(
            authFileURL: authFileURL,
            account: account,
            chatGPTAccountID: chatGPTAccountID
        )

        do {
            let launchedImmediately = try await relaunchCodexApp(launchTarget: launchTarget)
            if launchedImmediately {
                logger(L10n.text("switch.service.log.launch_completed"))
            } else {
                logger("Launch is deferred. Waiting for app to close, then will relaunch automatically.")
            }
        } catch {
            throw CodexAuthSwitchError.launchFailedAfterSwitch(reason: error.localizedDescription)
        }
    }

    private func rewriteAuthFile(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String
    ) throws {
        let originalData = try Data(contentsOf: authFileURL)
        let rewrittenData = try CodexAuthFileSwitcher.rewriteAuthJSON(
            originalData,
            accessToken: account.apiToken,
            accountID: chatGPTAccountID,
            email: account.name.contains("@") ? account.name : nil
        )
        try rewrittenData.write(to: authFileURL, options: .atomic)
        logger(L10n.text("switch.service.log.auth_file_rewritten"))
    }

    private func relaunchCodexApp(launchTarget: CodexLaunchTarget) async throws -> Bool {
#if canImport(AppKit)
        for bundleIdentifier in closeBundleIdentifiers(for: launchTarget) {
            let closed = await closeAppIfRunning(bundleIdentifier: bundleIdentifier)
            if !closed {
                scheduleDeferredLaunchMonitor(for: bundleIdentifier, launchTarget: launchTarget)
                return false
            }
        }

        if try await launchCodexAppWithRetry(launchTarget: launchTarget) {
            return true
        }
        throw CodexAuthSwitchError.appNotFound
#else
        throw CodexAuthSwitchError.unsupportedPlatform
#endif
    }

    private func closeAppIfRunning(bundleIdentifier: String) async -> Bool {
#if canImport(AppKit)
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !runningApps.isEmpty else {
            logger(String(format: L10n.text("switch.service.log.app_not_running_format"), bundleIdentifier))
            return true
        }

        logger(
            String(
                format: L10n.text("switch.service.log.app_running_count_format"),
                bundleIdentifier,
                runningApps.count
            )
        )

        if isSandboxedEnvironment {
            logger(L10n.text("switch.service.log.sandbox_cannot_close_apps"))
            return false
        }

        for runningApp in runningApps {
            let pid = runningApp.processIdentifier
            let didTerminate = runningApp.terminate()
            logger(
                String(
                    format: L10n.text("switch.service.log.terminate_attempt_format"),
                    pid,
                    didTerminate ? L10n.text("switch.service.log.terminate_status_success")
                        : L10n.text("switch.service.log.terminate_status_failed")
                )
            )
            if !didTerminate {
                let didForceTerminate = runningApp.forceTerminate()
                logger(
                    String(
                        format: L10n.text("switch.service.log.force_terminate_attempt_format"),
                        pid,
                        didForceTerminate ? L10n.text("switch.service.log.force_terminate_status_success")
                            : L10n.text("switch.service.log.force_terminate_status_failed")
                    )
                )
            }
        }

        let didExit = await waitUntilAppExits(
            bundleIdentifier: bundleIdentifier,
            timeoutNanoseconds: appCloseTimeoutNanoseconds
        )
        if didExit {
            logger(String(format: L10n.text("switch.service.log.app_closed_format"), bundleIdentifier))
            return true
        }

        logger(String(format: L10n.text("switch.service.log.app_still_running_format"), bundleIdentifier))
        return false
#else
        return true
#endif
    }

    private func launchCodexAppWithRetry(
        launchTarget: CodexLaunchTarget,
        maxAttempts: Int = 6
    ) async throws -> Bool {
        let launchBundleIDs = launchBundleIdentifiers(for: launchTarget)
        let launchAppPaths = launchAppURLs(for: launchTarget)

        for attempt in 1...maxAttempts {
            logger(String(format: L10n.text("switch.service.log.launch_attempt_format"), attempt))

            for bundleIdentifier in launchBundleIDs {
                if try await launchApp(bundleIdentifier: bundleIdentifier) {
                    logger(String(format: L10n.text("switch.service.log.launch_success_bundle_format"), bundleIdentifier))
                    return true
                }
            }

            for appURL in launchAppPaths {
                if try await launchApp(at: appURL) {
                    logger(String(format: L10n.text("switch.service.log.launch_success_path_format"), appURL.path))
                    return true
                }
            }

            try? await Task.sleep(nanoseconds: launchRetryIntervalNanoseconds)
        }
        logger(L10n.text("switch.service.log.launch_failed_after_retries"))
        return false
    }

    private func closeBundleIdentifiers(for launchTarget: CodexLaunchTarget) -> [String] {
        if launchTarget == .auto {
            return orderedUniqueValues(of: [CodexLaunchTarget.chatgpt, CodexLaunchTarget.codex].flatMap(\.bundleIdentifiers))
        }
        let explicitBundleIDs = launchTarget.bundleIdentifiers
        let inferredBundleIDs = launchTarget.appURLs.compactMap { url in
            Bundle(url: url)?.bundleIdentifier
        }
        return orderedUniqueValues(of: explicitBundleIDs + inferredBundleIDs)
    }

    private func launchBundleIdentifiers(for launchTarget: CodexLaunchTarget) -> [String] {
        if launchTarget == .auto {
            return orderedUniqueValues(of: autoLaunchOrder.flatMap(\.bundleIdentifiers))
        }
        return orderedUniqueValues(of: launchTarget.bundleIdentifiers)
    }

    private func launchAppURLs(for launchTarget: CodexLaunchTarget) -> [URL] {
        if launchTarget == .auto {
            return orderedUniqueValues(of: autoLaunchOrder.flatMap(\.appURLs))
        }
        return orderedUniqueValues(of: launchTarget.appURLs)
    }

    private func orderedUniqueValues<T: Hashable>(of values: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        result.reserveCapacity(values.count)
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func waitUntilAppExits(bundleIdentifier: String, timeoutNanoseconds: UInt64) async -> Bool {
#if canImport(AppKit)
        var waited: UInt64 = 0
        while waited < timeoutNanoseconds {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                return true
            }
            try? await Task.sleep(nanoseconds: appExitPollIntervalNanoseconds)
            waited += appExitPollIntervalNanoseconds
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
#else
        return true
#endif
    }

    private func scheduleDeferredLaunchMonitor(
        for bundleIdentifier: String,
        launchTarget: CodexLaunchTarget
    ) {
#if canImport(AppKit)
        let pollInterval = appExitPollIntervalNanoseconds
        let timeout = deferredLaunchMonitorTimeoutNanoseconds
        let logger = logger
        Task.detached(priority: .background) {
            logger("Deferred launch monitor started for \(bundleIdentifier).")
            var waited: UInt64 = 0
            while waited < timeout {
                let isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
                if !isRunning {
                    logger("Detected \(bundleIdentifier) closed. Relaunching now.")
                    let service = CodexAuthSwitchService(logger: logger)
                    do {
                        if try await service.launchCodexAppWithRetry(launchTarget: launchTarget) {
                            logger("Deferred relaunch completed.")
                        } else {
                            logger("Deferred relaunch failed after retries.")
                        }
                    } catch {
                        logger("Deferred relaunch error: \(error.localizedDescription)")
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: pollInterval)
                waited += pollInterval
            }
            logger("Deferred launch monitor timed out for \(bundleIdentifier).")
        }
#endif
    }

    private func launchApp(bundleIdentifier: String) async throws -> Bool {
#if canImport(AppKit)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            logger(String(format: L10n.text("switch.service.log.bundle_not_found_format"), bundleIdentifier))
            return false
        }
        logger(String(format: L10n.text("switch.service.log.bundle_found_format"), bundleIdentifier, url.path))
        return try await launchApp(at: url)
#else
        return false
#endif
    }

    private func launchApp(at url: URL) async throws -> Bool {
#if canImport(AppKit)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
#else
        return false
#endif
    }
}

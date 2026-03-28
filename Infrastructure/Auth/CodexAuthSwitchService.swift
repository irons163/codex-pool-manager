import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum CodexAuthSwitchError: LocalizedError {
    case appStillRunning(bundleIdentifier: String)
    case appNotFound
    case unsupportedPlatform

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
        }
    }
}

struct CodexAuthSwitchService {
    var logger: (String) -> Void = { _ in }

    private let knownBundleIdentifiers = ["com.openai.chatgpt", "com.openai.codex"]
    private let knownAppURLs = [
        URL(fileURLWithPath: "/Applications/ChatGPT.app"),
        URL(fileURLWithPath: "/Applications/Codex.app")
    ]
    private let appCloseTimeoutNanoseconds: UInt64 = 8_000_000_000
    private let appExitPollIntervalNanoseconds: UInt64 = 200_000_000
    private let launchRetryIntervalNanoseconds: UInt64 = 500_000_000

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
        chatGPTAccountID: String
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

        try await relaunchCodexApp()
        logger(L10n.text("switch.service.log.launch_completed"))
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

    private func relaunchCodexApp() async throws {
#if canImport(AppKit)
        for bundleIdentifier in knownBundleIdentifiers {
            let closed = await closeAppIfRunning(bundleIdentifier: bundleIdentifier)
            if !closed {
                throw CodexAuthSwitchError.appStillRunning(bundleIdentifier: bundleIdentifier)
            }
        }

        if try await launchCodexAppWithRetry() {
            return
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

    private func launchCodexAppWithRetry(maxAttempts: Int = 6) async throws -> Bool {
        for attempt in 1...maxAttempts {
            logger(String(format: L10n.text("switch.service.log.launch_attempt_format"), attempt))

            for bundleIdentifier in knownBundleIdentifiers {
                if try await launchApp(bundleIdentifier: bundleIdentifier) {
                    logger(String(format: L10n.text("switch.service.log.launch_success_bundle_format"), bundleIdentifier))
                    return true
                }
            }

            for appURL in knownAppURLs {
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

import Foundation

struct PoolDashboardSwitchLaunchCoordinator {
    private struct SwitchAttemptContext {
        let authFileURL: URL
        let failureLogPrefix: String
        let failureSessionAuthorizedAuthFileURL: URL?
    }

    private enum Message {
        static let missingTokenLog = L10n.text("switch.log.missing_token")
        static let missingAccountIDLog = L10n.text("switch.log.missing_account_id")
        static let missingToken = L10n.text("switch.error.missing_token")
        static let missingAccountID = L10n.text("switch.error.missing_account_id")
        static let requiresAuthFilePermission = L10n.text("switch.error.requires_auth_file_permission")
        static let switchFailurePrefix = L10n.text("switch.error.prefix")
        static let startSwitchFormat = "switch.log.start_format"
        static let errorPrefix = "switch.log.error_prefix"
        static let retryFailurePrefix = "switch.log.retry_failure_prefix"
        static let authPermissionStart = "switch.log.auth_permission_start"
        static let authPermissionNotCompleted = "switch.log.auth_permission_not_completed"
        static let authPermissionAcquired = "switch.log.auth_permission_acquired"
    }

    struct Output {
        let switchLaunchLog: String
        let errorMessage: String?
        let sessionAuthorizedAuthFileURL: URL?
        let didSwitchAuth: Bool
    }

    @MainActor
    func switchAndLaunch(
        account: AgentAccount,
        switchWithoutLaunching: Bool = false,
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService,
        authorizeAuthFile: () -> URL?
    ) async -> Output {
        var logLines: [String] = [L10n.text(Message.startSwitchFormat, account.name)]
        func append(_ line: String) {
            logLines.append(line)
        }
        func output(
            errorMessage: String?,
            sessionAuthorizedAuthFileURL: URL?,
            didSwitchAuth: Bool
        ) -> Output {
            Output(
                switchLaunchLog: logLines.joined(separator: "\n"),
                errorMessage: errorMessage,
                sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
                didSwitchAuth: didSwitchAuth
            )
        }
        func switchFailureMessage(_ error: Error) -> String {
            L10n.text("switch.error.with_description_format", Message.switchFailurePrefix, error.localizedDescription)
        }
        func outputForError(
            _ error: Error,
            logPrefix: String,
            sessionAuthorizedAuthFileURL: URL?,
            didSwitchAuth: Bool = false
        ) -> Output {
            append(L10n.text("switch.log.with_description_format", logPrefix, error.localizedDescription))
            return output(
                errorMessage: switchFailureMessage(error),
                sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL,
                didSwitchAuth: didSwitchAuth
            )
        }

        guard !account.apiToken.isEmpty else {
            append(Message.missingTokenLog)
            return output(
                errorMessage: Message.missingToken,
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
                didSwitchAuth: false
            )
        }
        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            append(Message.missingAccountIDLog)
            return output(
                errorMessage: Message.missingAccountID,
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
                didSwitchAuth: false
            )
        }

        func attemptSwitch(_ context: SwitchAttemptContext) async -> Output {
            do {
                try await performSwitchAndLaunch(
                    authFileURL: context.authFileURL,
                    account: account,
                    chatGPTAccountID: chatGPTAccountID,
                    switchWithoutLaunching: switchWithoutLaunching,
                    logger: append
                )
                return output(
                    errorMessage: nil,
                    sessionAuthorizedAuthFileURL: context.authFileURL,
                    didSwitchAuth: true
                )
            } catch let error as CodexAuthSwitchError {
                if case .launchFailedAfterSwitch = error {
                    return outputForError(
                        error,
                        logPrefix: context.failureLogPrefix,
                        sessionAuthorizedAuthFileURL: context.authFileURL,
                        didSwitchAuth: true
                    )
                }
                return outputForError(
                    error,
                    logPrefix: context.failureLogPrefix,
                    sessionAuthorizedAuthFileURL: context.failureSessionAuthorizedAuthFileURL
                )
            } catch {
                return outputForError(
                    error,
                    logPrefix: context.failureLogPrefix,
                    sessionAuthorizedAuthFileURL: context.failureSessionAuthorizedAuthFileURL
                )
            }
        }

        do {
            let authFileURL = try authFileAccessService.resolveAuthFileURLForSwitch(
                sessionAuthorizedURL: currentAuthorizedAuthFileURL
            )
            return await attemptSwitch(.init(
                authFileURL: authFileURL,
                failureLogPrefix: L10n.text(Message.errorPrefix),
                failureSessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            ))
        } catch CodexAuthFileAccessService.AccessError.missingAuthFile {
            append(L10n.text(Message.authPermissionStart))
            guard let authorizedURL = authorizeAuthFile() else {
                append(L10n.text(Message.authPermissionNotCompleted))
                return output(
                    errorMessage: Message.requiresAuthFilePermission,
                    sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
                    didSwitchAuth: false
                )
            }

            append(L10n.text(Message.authPermissionAcquired))
            return await attemptSwitch(.init(
                authFileURL: authorizedURL,
                failureLogPrefix: L10n.text(Message.retryFailurePrefix),
                failureSessionAuthorizedAuthFileURL: authorizedURL
            ))
        } catch {
            return outputForError(
                error,
                logPrefix: L10n.text(Message.errorPrefix),
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }
    }

    @MainActor
    private func performSwitchAndLaunch(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String,
        switchWithoutLaunching: Bool,
        logger: @Sendable @escaping (String) -> Void
    ) async throws {
        let service = CodexAuthSwitchService(logger: logger)
        if switchWithoutLaunching {
            try service.performSwitchOnly(
                authFileURL: authFileURL,
                account: account,
                chatGPTAccountID: chatGPTAccountID
            )
            return
        }

        try await service.performSwitchAndLaunch(
            authFileURL: authFileURL,
            account: account,
            chatGPTAccountID: chatGPTAccountID
        )
    }
}

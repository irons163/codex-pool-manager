import Foundation

struct PoolDashboardSwitchLaunchCoordinator {
    private enum SwitchResolutionError: Error {
        case missingAuthFile
    }

    private enum ValidationError: Error {
        case missingToken
        case missingAccountID

        var logLine: String {
            switch self {
            case .missingToken:
                return "失敗：沒有 token"
            case .missingAccountID:
                return "失敗：沒有 account_id"
            }
        }

        var errorMessage: String {
            switch self {
            case .missingToken:
                return Message.missingToken
            case .missingAccountID:
                return Message.missingAccountID
            }
        }
    }

    private enum Message {
        static let missingToken = "此帳號沒有可用 token，無法切換"
        static let missingAccountID = "此帳號缺少 Account ID，無法切換"
        static let requiresAuthFilePermission = "請先完成 auth.json 授權，才能切換並啟動"
        static let switchFailurePrefix = "切換失敗："
    }

    struct Output {
        let switchLaunchLog: String
        let errorMessage: String?
        let sessionAuthorizedAuthFileURL: URL?
    }

    @MainActor
    func switchAndLaunch(
        account: AgentAccount,
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService,
        authorizeAuthFile: () -> URL?
    ) async -> Output {
        var logLines: [String] = ["開始切換：\(account.name)"]
        func append(_ line: String) {
            logLines.append(line)
        }
        func output(errorMessage: String?, sessionAuthorizedAuthFileURL: URL?) -> Output {
            Output(
                switchLaunchLog: logLines.joined(separator: "\n"),
                errorMessage: errorMessage,
                sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
            )
        }
        func switchFailureMessage(_ error: Error) -> String {
            Message.switchFailurePrefix + error.localizedDescription
        }
        func outputForError(
            _ error: Error,
            logPrefix: String,
            sessionAuthorizedAuthFileURL: URL?
        ) -> Output {
            append("\(logPrefix)：\(error.localizedDescription)")
            return output(
                errorMessage: switchFailureMessage(error),
                sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
            )
        }

        let chatGPTAccountID: String
        do {
            chatGPTAccountID = try validatedChatGPTAccountID(for: account)
        } catch let validationError as ValidationError {
            append(validationError.logLine)
            return output(
                errorMessage: validationError.errorMessage,
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        } catch {
            return outputForError(
                error,
                logPrefix: "錯誤",
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }

        func attemptSwitch(
            authFileURL: URL,
            failureLogPrefix: String,
            failureSessionAuthorizedAuthFileURL: URL?
        ) async -> Output {
            do {
                try await performSwitchAndLaunch(
                    authFileURL: authFileURL,
                    account: account,
                    chatGPTAccountID: chatGPTAccountID,
                    logger: append
                )
                return output(
                    errorMessage: nil,
                    sessionAuthorizedAuthFileURL: authFileURL
                )
            } catch {
                return outputForError(
                    error,
                    logPrefix: failureLogPrefix,
                    sessionAuthorizedAuthFileURL: failureSessionAuthorizedAuthFileURL
                )
            }
        }

        do {
            let authFileURL = try resolveAuthFileURLForSwitch(
                currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
                authFileAccessService: authFileAccessService
            )
            return await attemptSwitch(
                authFileURL: authFileURL,
                failureLogPrefix: "錯誤",
                failureSessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        } catch SwitchResolutionError.missingAuthFile {
            append("尚未授權 auth.json，啟動選檔流程")
            guard let authorizedURL = authorizeAuthFile() else {
                append("使用者未完成 auth.json 授權")
                return output(
                    errorMessage: Message.requiresAuthFilePermission,
                    sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
                )
            }

            append("已取得授權，重試切換")
            return await attemptSwitch(
                authFileURL: authorizedURL,
                failureLogPrefix: "重試失敗",
                failureSessionAuthorizedAuthFileURL: authorizedURL
            )
        } catch {
            return outputForError(
                error,
                logPrefix: "錯誤",
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }
    }

    private func validatedChatGPTAccountID(for account: AgentAccount) throws -> String {
        guard !account.apiToken.isEmpty else {
            throw ValidationError.missingToken
        }
        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            throw ValidationError.missingAccountID
        }
        return chatGPTAccountID
    }

    private func resolveAuthFileURLForSwitch(
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService
    ) throws -> URL {
        do {
            return try authFileAccessService.resolveAuthFileURLForSwitch(
                sessionAuthorizedURL: currentAuthorizedAuthFileURL
            )
        } catch CodexAuthFileAccessService.AccessError.missingAuthFile {
            throw SwitchResolutionError.missingAuthFile
        }
    }

    @MainActor
    private func performSwitchAndLaunch(
        authFileURL: URL,
        account: AgentAccount,
        chatGPTAccountID: String,
        logger: @escaping (String) -> Void
    ) async throws {
        let service = CodexAuthSwitchService(logger: logger)
        try await service.performSwitchAndLaunch(
            authFileURL: authFileURL,
            account: account,
            chatGPTAccountID: chatGPTAccountID
        )
    }
}

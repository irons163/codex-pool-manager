import Foundation

struct PoolDashboardSwitchLaunchCoordinator {
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

        guard !account.apiToken.isEmpty else {
            append("失敗：沒有 token")
            return makeOutput(
                logLines: logLines,
                errorMessage: "此帳號沒有可用 token，無法切換",
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }

        guard let chatGPTAccountID = account.chatGPTAccountID, !chatGPTAccountID.isEmpty else {
            append("失敗：沒有 account_id")
            return makeOutput(
                logLines: logLines,
                errorMessage: "此帳號缺少 Account ID，無法切換",
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }

        do {
            let authFileURL = try resolveAuthFileURLForSwitch(
                currentAuthorizedAuthFileURL: currentAuthorizedAuthFileURL,
                authFileAccessService: authFileAccessService
            )
            try await performSwitchAndLaunch(
                authFileURL: authFileURL,
                account: account,
                chatGPTAccountID: chatGPTAccountID,
                logger: append
            )
            return makeOutput(
                logLines: logLines,
                errorMessage: nil,
                sessionAuthorizedAuthFileURL: authFileURL
            )
        } catch let error as NSError where error.domain == "CodexSwitch" && error.code == 1 {
            append("尚未授權 auth.json，啟動選檔流程")
            guard let authorizedURL = authorizeAuthFile() else {
                append("使用者未完成 auth.json 授權")
                return makeOutput(
                    logLines: logLines,
                    errorMessage: "請先完成 auth.json 授權，才能切換並啟動",
                    sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
                )
            }

            append("已取得授權，重試切換")
            do {
                try await performSwitchAndLaunch(
                    authFileURL: authorizedURL,
                    account: account,
                    chatGPTAccountID: chatGPTAccountID,
                    logger: append
                )
                return makeOutput(
                    logLines: logLines,
                    errorMessage: nil,
                    sessionAuthorizedAuthFileURL: authorizedURL
                )
            } catch {
                append("重試失敗：\(error.localizedDescription)")
                return makeOutput(
                    logLines: logLines,
                    errorMessage: "切換失敗：\(error.localizedDescription)",
                    sessionAuthorizedAuthFileURL: authorizedURL
                )
            }
        } catch {
            append("錯誤：\(error.localizedDescription)")
            return makeOutput(
                logLines: logLines,
                errorMessage: "切換失敗：\(error.localizedDescription)",
                sessionAuthorizedAuthFileURL: currentAuthorizedAuthFileURL
            )
        }
    }

    private func resolveAuthFileURLForSwitch(
        currentAuthorizedAuthFileURL: URL?,
        authFileAccessService: CodexAuthFileAccessService
    ) throws -> URL {
        do {
            return try authFileAccessService.resolveAuthFileURLForSwitch(
                sessionAuthorizedURL: currentAuthorizedAuthFileURL
            )
        } catch {
            throw NSError(
                domain: "CodexSwitch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "找不到 auth.json，請先按「選擇 auth.json」授權"]
            )
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

    private func makeOutput(
        logLines: [String],
        errorMessage: String?,
        sessionAuthorizedAuthFileURL: URL?
    ) -> Output {
        Output(
            switchLaunchLog: logLines.joined(separator: "\n"),
            errorMessage: errorMessage,
            sessionAuthorizedAuthFileURL: sessionAuthorizedAuthFileURL
        )
    }
}

import Foundation

enum CodexAPIKeyLoginError: Error, LocalizedError, Equatable {
    case missingCodexCLI
    case loginFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingCodexCLI:
            return L10n.text("relay.error.codex_cli_missing")
        case let .loginFailed(message):
            return L10n.text("relay.error.login_failed_format", message)
        }
    }
}

private final class CodexAPIKeyLoginContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var didComplete = false
    private let continuation: CheckedContinuation<(terminationStatus: Int32, output: String), Error>

    init(_ continuation: CheckedContinuation<(terminationStatus: Int32, output: String), Error>) {
        self.continuation = continuation
    }

    nonisolated func finish(_ result: Result<(terminationStatus: Int32, output: String), Error>) {
        lock.lock()
        if didComplete {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()

        continuation.resume(with: result)
    }
}

struct CodexAPIKeyLoginService {
    private static let commandSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    var executableURLProvider: () -> URL? = {
        ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var processRunner: (URL, [String], Data, [String: String]) async throws -> (terminationStatus: Int32, output: String) = { executableURL, arguments, input, environment in
        try await withCheckedThrowingContinuation { continuation in
            let continuationBox = CodexAPIKeyLoginContinuationBox(continuation)
            let process = Process()
            let stdout = Pipe()
            let stdin = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = environment
            process.standardOutput = stdout
            process.standardError = stdout
            process.standardInput = stdin
            process.terminationHandler = { process in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuationBox.finish(.success((process.terminationStatus, output)))
            }

            do {
                try process.run()
                stdin.fileHandleForWriting.write(input)
                try stdin.fileHandleForWriting.close()
            } catch {
                if process.isRunning {
                    process.terminate()
                }
                continuationBox.finish(.failure(error))
            }
        }
    }

    func login(apiKey: String) async throws {
        let trimmed = Self.trimmedStableCopy(apiKey)
        try await login(trimmedAPIKeyData: Data(trimmed.utf8))
    }

    func login(trimmedAPIKeyData apiKeyData: Data) async throws {
        guard let executableURL = executableURLProvider() else {
            throw CodexAPIKeyLoginError.missingCodexCLI
        }

        let result = try await processRunner(
            executableURL,
            ["login", "--with-api-key"],
            apiKeyData,
            Self.loginProcessEnvironment()
        )
        guard result.terminationStatus == 0 else {
            throw CodexAPIKeyLoginError.loginFailed(result.output)
        }
    }

    private static func trimmedStableCopy(_ value: String) -> String {
        String(decoding: Array(value.utf8), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func loginProcessEnvironment(
        base environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var mergedEnvironment = environment
        let existingPaths = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        var seen = Set<String>()
        let mergedPaths = (commandSearchPaths + existingPaths).filter { path in
            seen.insert(path).inserted
        }
        mergedEnvironment["PATH"] = mergedPaths.joined(separator: ":")
        return mergedEnvironment
    }
}

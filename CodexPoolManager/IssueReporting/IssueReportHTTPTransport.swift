import Foundation

// Keep Foundation's session and delegate alive across the complete request.
// Completion-handler tasks avoid the async URLSession overlay that crashes in
// the shipped Swift 6.2 build on macOS 26.4.
nonisolated final class IssueReportHTTPTransport: Sendable {
    private let session: URLSession
    private let redirectDelegate: IssueReportRedirectDelegate

    init(configuration suppliedConfiguration: URLSessionConfiguration? = nil) {
        let configuration: URLSessionConfiguration
        if let supplied = suppliedConfiguration?.copy() as? URLSessionConfiguration {
            configuration = supplied
        } else {
            configuration = .ephemeral
        }
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        let delegate = IssueReportRedirectDelegate()
        redirectDelegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let cancellation = IssueReportRequestCancellation()
        let result: (Data, URLResponse) = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    cancellation.complete()
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, let response {
                        continuation.resume(returning: (data, response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                cancellation.start(task)
            }
        } onCancel: {
            cancellation.cancel()
        }
        try Task.checkCancellation()
        withExtendedLifetime(self) {}
        return result
    }
}

// Cancellation can arrive before the URLSession task has been installed, or
// concurrently with its completion. The lock protects both cases.
nonisolated private final class IssueReportRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false

    func start(_ task: URLSessionDataTask) {
        let shouldCancel = lock.withLock {
            self.task = task
            return isCancelled
        }
        if shouldCancel { task.cancel() }
        task.resume()
    }

    func cancel() {
        let task = lock.withLock {
            isCancelled = true
            return self.task
        }
        task?.cancel()
    }

    func complete() {
        lock.withLock { task = nil }
    }
}

nonisolated private final class IssueReportRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

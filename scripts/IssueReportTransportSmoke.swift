import Foundation

nonisolated private enum StubRoute: Sendable {
    case response(Int, Data)
    case failure(URLError.Code)
    case pending(AsyncStream<Void>.Continuation, AsyncStream<Void>.Continuation)
}

nonisolated private final class StubRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [URL: StubRoute] = [:]
    private var requests: [URL: [URLRequest]] = [:]

    func set(_ route: StubRoute, for url: URL) {
        lock.withLock { routes[url] = route }
    }

    func start(_ request: URLRequest) -> StubRoute? {
        lock.withLock {
            guard let url = request.url else { return nil }
            requests[url, default: []].append(request)
            return routes[url]
        }
    }

    func received(_ url: URL) -> [URLRequest] {
        lock.withLock { requests[url] ?? [] }
    }

    func stop(_ url: URL?) {
        let route = lock.withLock { url.flatMap { routes[$0] } }
        if case .pending(_, let stopped) = route {
            stopped.yield(())
            stopped.finish()
        }
    }
}

nonisolated private final class ReportStubProtocol: URLProtocol, @unchecked Sendable {
    static let registry = StubRegistry()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let route = Self.registry.start(request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch route {
        case .response(let status, let data):
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .pending(let started, _):
            started.yield(())
            started.finish()
        }
    }

    override func stopLoading() {
        Self.registry.stop(request.url)
    }
}

@main
private struct IssueReportTransportSmoke {
    static func endpoint() -> URL {
        URL(string: "https://\(UUID().uuidString.lowercased()).invalid/reports")!
    }

    static func service(_ url: URL) -> IssueReportService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReportStubProtocol.self]
        return IssueReportService(endpoint: url, sessionConfiguration: configuration)
    }

    static func payload() -> IssueReportPayload {
        IssueReportPayload(id: UUID().uuidString.lowercased(), title: "Transport test",
                           message: "Synthetic local test only", replyEmail: nil, systemInfo: nil)
    }

    static func failure(_ operation: () async throws -> Void) async -> Error {
        do {
            try await operation()
            fatalError("Expected the request to fail")
        } catch {
            return error
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    static func main() async throws {
        setbuf(stdout, nil)
        print("Starting actual URLSession transport checks")
        let deadline = Task.detached {
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            fatalError("The real URLSession transport did not complete within 25 seconds")
        }
        defer { deadline.cancel() }

        let probeURL = endpoint()
        var probeRequest = URLRequest(url: probeURL)
        probeRequest.httpMethod = "POST"
        probeRequest.httpBody = Data("request lifetime probe".utf8)
        let bridgedProbe = probeRequest as NSURLRequest
        precondition(bridgedProbe.url == probeURL)
        print("PASS: request remains valid after Foundation bridging")
        let probeConfiguration = URLSessionConfiguration.ephemeral
        probeConfiguration.protocolClasses = [ReportStubProtocol.self]
        ReportStubProtocol.registry.set(.response(200, Data("probe".utf8)), for: probeURL)
        let (probeData, _) = try await IssueReportHTTPTransport(configuration: probeConfiguration).send(probeRequest)
        precondition(probeData == Data("probe".utf8))
        print("PASS: transport receives a freshly built request intact")

        let successURL = endpoint()
        let sender = service(successURL)
        for status in [202, 200, 202, 200, 202] {
            let report = payload()
            let receipt = try JSONSerialization.data(withJSONObject: ["accepted": true, "reportID": report.id])
            ReportStubProtocol.registry.set(.response(status, receipt), for: successURL)
            try await sender.send(report)
        }
        let requests = ReportStubProtocol.registry.received(successURL)
        precondition(requests.count == 5)
        for request in requests {
            precondition(request.httpMethod == "POST")
            precondition(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            precondition(request.value(forHTTPHeaderField: "Cookie") == nil)
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            precondition(request.httpBody != nil || request.httpBodyStream != nil)
        }
        print("PASS: real URLSession posts reports repeatedly without cookies or credentials")

        let failureURL = endpoint()
        ReportStubProtocol.registry.set(.response(503, Data()), for: failureURL)
        let unavailable = await failure { try await service(failureURL).send(payload()) }
        precondition(unavailable as? IssueReportError == .unavailable)
        print("PASS: HTTP failure is returned without false success")

        let offlineURL = endpoint()
        ReportStubProtocol.registry.set(.failure(.notConnectedToInternet), for: offlineURL)
        let offline = await failure { try await service(offlineURL).send(payload()) }
        precondition((offline as? URLError)?.code == .notConnectedToInternet)
        print("PASS: network errors return through the actual transport")

        guard let rawRedirectURL = ProcessInfo.processInfo.environment["ISSUE_REPORT_REDIRECT_URL"],
              let redirectURL = URL(string: rawRedirectURL) else {
            fatalError("Run this executable with scripts/test_issue_report_transport.sh")
        }
        var redirectRequest = URLRequest(url: redirectURL, timeoutInterval: 5)
        redirectRequest.httpMethod = "POST"
        redirectRequest.httpBody = Data("local redirect test".utf8)
        let (_, redirectResponse) = try await IssueReportHTTPTransport().send(redirectRequest)
        precondition((redirectResponse as? HTTPURLResponse)?.statusCode == 307)
        print("PASS: redirects never forward report contents to another endpoint")

        let pendingURL = endpoint()
        let started = AsyncStream<Void>.makeStream()
        let stopped = AsyncStream<Void>.makeStream()
        ReportStubProtocol.registry.set(.pending(started.continuation, stopped.continuation), for: pendingURL)
        let pendingService = service(pendingURL)
        let pendingPayload = payload()
        let pending = Task { try await pendingService.send(pendingPayload) }
        for await _ in started.stream { break }
        pending.cancel()
        let cancelled = await failure { try await pending.value }
        precondition(isCancellation(cancelled))
        for await _ in stopped.stream { break }
        print("PASS: cancellation stops the in-flight URLSession task")

        let cancelledURL = endpoint()
        ReportStubProtocol.registry.set(.response(202, Data()), for: cancelledURL)
        let cancelledService = service(cancelledURL)
        let cancelledPayload = payload()
        let beforeStart = Task { try await cancelledService.send(cancelledPayload) }
        beforeStart.cancel()
        let beforeStartError = await failure { try await beforeStart.value }
        precondition(isCancellation(beforeStartError))
        precondition(ReportStubProtocol.registry.received(cancelledURL).isEmpty)
        print("PASS: cancellation before start performs no network request")
    }
}

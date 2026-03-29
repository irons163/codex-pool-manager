import Foundation
@testable import CodexPoolManager

struct MockCodexUsageClient: CodexUsageClient {
    let responseByToken: [String: CodexUsage]
    var shouldThrow: Bool = false
    var shouldThrowError: Error?

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        if let shouldThrowError {
            throw shouldThrowError
        }
        if shouldThrow {
            throw URLError(.badServerResponse)
        }
        return responseByToken[accessToken] ?? CodexUsage(usedUnits: 0, quota: 1000)
    }
}

func makeMockedURLSession(
    endpoint: URL,
    statusCode: Int,
    data: Data,
    requestObserver: ((URLRequest) -> Void)? = nil
) -> URLSession {
    MockUsageURLProtocol.setMock(
        for: endpoint.absoluteString,
        statusCode: statusCode,
        data: data,
        requestObserver: requestObserver
    )
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockUsageURLProtocol.self]
    return URLSession(configuration: configuration)
}

final class MockUsageURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseByURL: [String: (statusCode: Int, data: Data)] = [:]
    private static var observerByURL: [String: (URLRequest) -> Void] = [:]

    static func setMock(
        for url: String,
        statusCode: Int,
        data: Data,
        requestObserver: ((URLRequest) -> Void)?
    ) {
        lock.lock()
        defer { lock.unlock() }
        responseByURL[url] = (statusCode: statusCode, data: data)
        observerByURL[url] = requestObserver
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let responseTuple: (statusCode: Int, data: Data)?
        let observer: ((URLRequest) -> Void)?
        Self.lock.lock()
        responseTuple = Self.responseByURL[url]
        observer = Self.observerByURL[url]
        Self.lock.unlock()

        observer?(request)
        guard let responseTuple else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: responseTuple.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseTuple.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LockedValue<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&_value)
    }
}

actor FlakyCodexUsageClient: CodexUsageClient {
    var failuresBeforeSuccess: Int
    let successUsage: CodexUsage

    init(failuresBeforeSuccess: Int, successUsage: CodexUsage) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.successUsage = successUsage
    }

    func fetchUsage(accessToken: String, accountID: String) async throws -> CodexUsage {
        if failuresBeforeSuccess > 0 {
            failuresBeforeSuccess -= 1
            throw URLError(.timedOut)
        }
        return successUsage
    }
}

import Foundation

enum IssueReportConfiguration {
    static let githubURL = URL(string: "https://github.com/irons163/codex-pool-manager/issues/new")!
    static let emailAddress = "feedback@codexpool.zero2codex.dev"

    static var endpoint: URL? {
        validatedEndpoint(Bundle.main.object(forInfoDictionaryKey: "CodexPoolFeedbackEndpoint") as? String)
    }

    static func validatedEndpoint(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }

    static var systemInfo: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "CodexPoolManager \(version) (\(build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}

struct IssueReportDraft: Equatable {
    var title = ""
    var message = ""
    var replyEmail = ""
    var includesSystemInfo = false

    func payload(id: UUID, systemInfo: String) throws -> IssueReportPayload {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = replyEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 300,
              title.range(of: #"[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]"#, options: .regularExpression) == nil,
              !message.isEmpty, message.utf8.count <= 20_000, !message.contains("\0")
        else { throw IssueReportError.invalidContent }
        guard email.isEmpty || Self.isValidEmail(email) else { throw IssueReportError.invalidEmail }
        return IssueReportPayload(
            id: id.uuidString.lowercased(), title: title, message: message,
            replyEmail: email.isEmpty ? nil : email,
            systemInfo: includesSystemInfo ? systemInfo : nil
        )
    }

    static func isValidEmail(_ value: String) -> Bool {
        value.utf8.count <= 254
            && value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#, options: .regularExpression) != nil
    }
}

struct IssueReportPayload: Codable, Equatable {
    let id: String
    let title: String
    let message: String
    let replyEmail: String?
    let systemInfo: String?
}

enum IssueReportError: Error, LocalizedError, Equatable {
    case unavailable, invalidContent, invalidEmail, rateLimited, pending, failed, invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: return L10n.text("report.error.unavailable")
        case .invalidContent: return L10n.text("report.error.invalid_content")
        case .invalidEmail: return L10n.text("report.error.invalid_email")
        case .rateLimited: return L10n.text("report.error.rate_limited")
        case .pending: return L10n.text("report.error.pending")
        case .failed, .invalidResponse: return L10n.text("report.error.failed")
        }
    }
}

struct IssueReportService {
    typealias Transport = (URLRequest) async throws -> (Data, URLResponse)
    let endpoint: URL?
    private let transport: Transport?
    private let sender: IssueReportHTTPTransport?

    init() {
        self.init(endpoint: IssueReportConfiguration.endpoint)
    }

    init(endpoint: URL?, sessionConfiguration: URLSessionConfiguration? = nil, transport: Transport? = nil) {
        self.endpoint = IssueReportConfiguration.validatedEndpoint(endpoint?.absoluteString)
        self.transport = transport
        if transport == nil {
            self.sender = IssueReportHTTPTransport(configuration: sessionConfiguration)
        } else {
            self.sender = nil
        }
    }

    func send(_ report: IssueReportPayload) async throws {
        guard let endpoint else { throw IssueReportError.unavailable }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(report)
        let data: Data
        let response: URLResponse
        if let transport {
            (data, response) = try await transport(request)
        } else if let sender {
            (data, response) = try await sender.send(request)
        } else {
            throw IssueReportError.unavailable
        }
        guard let response = response as? HTTPURLResponse else { throw IssueReportError.invalidResponse }
        switch response.statusCode {
        case 200, 202:
            struct Receipt: Decodable { let accepted: Bool; let reportID: String }
            guard let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
                  receipt.accepted, receipt.reportID == report.id
            else { throw IssueReportError.invalidResponse }
        case 400, 413: throw IssueReportError.invalidContent
        case 409: throw IssueReportError.pending
        case 429: throw IssueReportError.rateLimited
        case 503: throw IssueReportError.unavailable
        default: throw IssueReportError.failed
        }
    }
}

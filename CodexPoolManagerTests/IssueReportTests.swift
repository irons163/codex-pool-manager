import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CodexPoolManager

@MainActor
struct IssueReportTests {
    private let endpoint = URL(string: "https://feedback.example.com/reports")!

    private func draft() -> IssueReportDraft {
        IssueReportDraft(title: " 同步錯誤 ", message: " 按同步後發生錯誤。 ", replyEmail: "")
    }

    private func response(_ status: Int = 202, data: Data = Data()) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    private func receipt(for request: URLRequest, accepted: Bool = true, id: String? = nil) throws -> Data {
        let payload = try JSONDecoder().decode(IssueReportPayload.self, from: #require(request.httpBody))
        return try JSONSerialization.data(withJSONObject: ["accepted": accepted, "reportID": id ?? payload.id])
    }

    @Test
    func endpointsRequireHTTPSAndRejectEmbeddedCredentialsOrQuery() {
        #expect(IssueReportConfiguration.validatedEndpoint(endpoint.absoluteString) == endpoint)
        for raw in [nil, "", "http://feedback.example.com/reports", "https://user:pass@example.com/reports",
                    "https://example.com/reports?token=secret", "https://example.com/reports#fragment", "$(FEEDBACK_ENDPOINT)"] {
            #expect(IssueReportConfiguration.validatedEndpoint(raw) == nil)
        }
    }

    @Test
    func draftOnlyIncludesUserApprovedFields() throws {
        var draft = draft()
        let payload = try draft.payload(id: UUID(), systemInfo: "private system info")
        #expect(payload.title == "同步錯誤")
        #expect(payload.message == "按同步後發生錯誤。")
        #expect(payload.replyEmail == nil)
        #expect(payload.systemInfo == nil)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any])
        #expect(Set(json.keys) == ["id", "title", "message"])
        draft.includesSystemInfo = true
        draft.replyEmail = " user+feedback@example.com "
        let optedIn = try draft.payload(id: UUID(), systemInfo: "App 1.0 (151)")
        #expect(optedIn.systemInfo == "App 1.0 (151)")
        #expect(optedIn.replyEmail == "user+feedback@example.com")
    }

    @Test
    func draftRejectsHeaderInjectionAndOversizedMultibyteContent() {
        var draft = draft()
        draft.title = "Hi\r\nBcc: attacker@example.com"
        #expect(throws: IssueReportError.invalidContent) { try draft.payload(id: UUID(), systemInfo: "") }
        draft.title = String(repeating: "中", count: 101)
        #expect(throws: IssueReportError.invalidContent) { try draft.payload(id: UUID(), systemInfo: "") }
        draft.title = "Valid"
        draft.message = String(repeating: "x", count: 20_001)
        #expect(throws: IssueReportError.invalidContent) { try draft.payload(id: UUID(), systemInfo: "") }
        draft.message = "Valid"
        draft.replyEmail = "valid@example.com\nBcc: attacker@example.com"
        #expect(throws: IssueReportError.invalidEmail) { try draft.payload(id: UUID(), systemInfo: "") }
    }

    @Test
    func missingEndpointNeverTransmitsReport() async {
        var count = 0
        let service = IssueReportService(endpoint: nil) { _ in count += 1; return response() }
        await #expect(throws: IssueReportError.unavailable) {
            try await service.send(draft().payload(id: UUID(), systemInfo: ""))
        }
        #expect(count == 0)
    }

    @Test
    func clientSendsJSONWithoutAuthenticationOrCookies() async throws {
        let payload = try draft().payload(id: UUID(), systemInfo: "")
        let service = IssueReportService(endpoint: endpoint) { request in
            #expect(request.url == endpoint)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(try JSONDecoder().decode(IssueReportPayload.self, from: #require(request.httpBody)) == payload)
            return try response(data: receipt(for: request))
        }
        try await service.send(payload)
    }

    @Test
    func clientDoesNotAcceptFalseOrMismatchedReceipts() async throws {
        let payload = try draft().payload(id: UUID(), systemInfo: "")
        for (accepted, id) in [(false, payload.id), (true, UUID().uuidString)] {
            let service = IssueReportService(endpoint: endpoint) { request in
                try response(data: receipt(for: request, accepted: accepted, id: id))
            }
            await #expect(throws: IssueReportError.invalidResponse) { try await service.send(payload) }
        }
        let service = IssueReportService(endpoint: endpoint) { _ in response(data: Data("not JSON".utf8)) }
        await #expect(throws: IssueReportError.invalidResponse) { try await service.send(payload) }
    }

    @Test
    func clientMapsFailuresWithoutDisplayingProviderDetails() async throws {
        let payload = try draft().payload(id: UUID(), systemInfo: "")
        for (status, error) in [(400, IssueReportError.invalidContent), (413, .invalidContent), (409, .pending),
                                (429, .rateLimited), (503, .unavailable), (502, .failed), (302, .failed)] {
            let service = IssueReportService(endpoint: endpoint) { _ in response(status, data: Data("private diagnostic".utf8)) }
            await #expect(throws: error) { try await service.send(payload) }
        }
    }

    @Test
    func failedSubmissionKeepsDraftAndReusesIDUntilUserChangesContent() async {
        var ids: [String] = []
        let service = IssueReportService(endpoint: endpoint) { request in
            let payload = try JSONDecoder().decode(IssueReportPayload.self, from: #require(request.httpBody))
            ids.append(payload.id)
            throw URLError(.timedOut)
        }
        let model = IssueReportFormModel(service: service, systemInfo: "App")
        model.draft = draft()
        let original = model.draft
        await model.submit()
        #expect(!model.isSubmitted && !model.isSubmitting)
        #expect(model.errorMessage != nil)
        #expect(model.draft == original)
        await model.submit()
        #expect(ids.count == 2 && ids[0] == ids[1])
        model.draft.message += "Updated"
        await model.submit()
        #expect(ids[2] != ids[1])
    }

    @Test
    func successfulSubmissionCannotBeSentAgain() async {
        var count = 0
        let service = IssueReportService(endpoint: endpoint) { request in
            count += 1
            return try response(data: receipt(for: request))
        }
        let model = IssueReportFormModel(service: service)
        model.draft = draft()
        #expect(model.canSubmit)
        await model.submit()
        #expect(model.isSubmitted && !model.canSubmit)
        await model.submit()
        #expect(count == 1)
    }

    @Test
    func cancelledSubmissionKeepsDraftWithoutReportingSuccess() async {
        let model = IssueReportFormModel(service: IssueReportService(endpoint: endpoint) { _ in throw CancellationError() })
        model.draft = draft()
        await model.submit()
        #expect(!model.isSubmitted && !model.isSubmitting)
        #expect(model.errorMessage == nil)
        #expect(model.draft == draft())
    }

    @Test
    func unavailableServiceAndInvalidFieldsDisableSend() {
        let unavailable = IssueReportFormModel(service: IssueReportService(endpoint: nil))
        unavailable.draft = draft()
        #expect(!unavailable.canSubmit)
        let configured = IssueReportFormModel(service: IssueReportService(endpoint: endpoint))
        #expect(!configured.canSubmit)
        configured.draft = draft()
        configured.draft.replyEmail = "invalid"
        #expect(!configured.canSubmit && configured.validationMessage != nil)
    }

    @Test
    func formAndSidebarMenuRenderWithoutSending() throws {
        var calls = 0
        let model = IssueReportFormModel(service: IssueReportService(endpoint: endpoint) { _ in calls += 1; return response() })
        model.draft = draft()
        model.draft.includesSystemInfo = true
        let content = VStack {
            HStack {
                ReportIssueMenuView(onEmailReport: {}).frame(width: 240)
                ReportIssueMenuView(isCompact: true, onEmailReport: {}).frame(width: 28)
            }
            IssueReportFormView(model: model)
        }
        let host = NSHostingView(rootView: content)
        host.frame = CGRect(x: 0, y: 0, width: 560, height: 650)
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("codex-pool-report-form.png"))
        #expect(calls == 0)
    }
}

import Combine
import SwiftUI

@MainActor
final class IssueReportFormModel: ObservableObject {
    @Published var draft = IssueReportDraft()
    @Published private(set) var isSubmitting = false
    @Published private(set) var isSubmitted = false
    @Published private(set) var errorMessage: String?
    let service: IssueReportService
    let systemInfo: String
    private var lastPayload: IssueReportPayload?

    init(service: IssueReportService? = nil, systemInfo: String? = nil) {
        self.service = service ?? IssueReportService()
        self.systemInfo = systemInfo ?? IssueReportConfiguration.systemInfo
    }

    var canSubmit: Bool {
        service.endpoint != nil && !isSubmitting && !isSubmitted
            && (try? draft.payload(id: UUID(), systemInfo: systemInfo)) != nil
    }

    var validationMessage: String? {
        guard !draft.title.isEmpty || !draft.message.isEmpty || !draft.replyEmail.isEmpty else { return nil }
        do {
            _ = try draft.payload(id: UUID(), systemInfo: systemInfo)
            return nil
        } catch IssueReportError.invalidEmail {
            return L10n.text("report.error.invalid_email")
        } catch {
            return L10n.text("report.error.invalid_content")
        }
    }

    func submit() async {
        guard !isSubmitting, !isSubmitted else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            // Retain the request ID when retrying an unchanged report.
            var payload = try draft.payload(id: UUID(), systemInfo: systemInfo)
            if let previous = lastPayload,
               payload.title == previous.title, payload.message == previous.message,
               payload.replyEmail == previous.replyEmail, payload.systemInfo == previous.systemInfo {
                payload = previous
            }
            lastPayload = payload
            try await service.send(payload)
            isSubmitted = true
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as IssueReportError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = L10n.text("report.error.failed")
        }
    }
}

struct ReportIssueMenuView: View {
    var isCompact = false
    let onEmailReport: () -> Void

    var body: some View {
        Menu {
            Link(destination: IssueReportConfiguration.githubURL) {
                Label(L10n.text("settings.report_issue_github"), systemImage: "arrow.up.right.square")
            }
            Button(action: onEmailReport) {
                Label(L10n.text("settings.report_issue_email"), systemImage: "envelope")
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "ladybug")
                    .frame(width: 16)
                    .accessibilityHidden(true)
                if !isCompact {
                    Text(L10n.text("settings.report_issue"))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(PoolDashboardTheme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: isCompact ? .center : .leading)
            .padding(.horizontal, isCompact ? 0 : 10)
            .padding(.vertical, isCompact ? 0 : 4)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .accessibilityLabel(L10n.text("settings.report_issue"))
        .help(L10n.text("settings.report_issue_hint"))
    }
}

struct IssueReportFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: IssueReportFormModel
    @State private var submitTask: Task<Void, Never>?

    init(model: IssueReportFormModel? = nil) {
        _model = StateObject(wrappedValue: model ?? IssueReportFormModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("settings.report_issue_email"), systemImage: "envelope")
                .font(.title2.weight(.semibold))

            Text(L10n.text("report.recipient_format", IssueReportConfiguration.emailAddress))
                .font(.callout)
                .foregroundStyle(PoolDashboardTheme.textSecondary)
                .textSelection(.enabled)

            if model.isSubmitted {
                Label(L10n.text("report.success"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(PoolDashboardTheme.success)
                    .padding(.vertical, 24)
            } else {
                Text(L10n.text("report.form_hint"))
                    .font(.callout)
                    .foregroundStyle(PoolDashboardTheme.textSecondary)

                if model.service.endpoint == nil {
                    Text(L10n.text("report.error.unavailable"))
                        .font(.callout)
                        .foregroundStyle(PoolDashboardTheme.warning)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        field(L10n.text("report.title"), text: $model.draft.title)
                        field(L10n.text("report.reply_email"), text: $model.draft.replyEmail)

                        Text(L10n.text("report.message"))
                            .font(.callout.weight(.medium))
                        TextEditor(text: $model.draft.message)
                            .font(.body)
                            .frame(minHeight: 160)
                            .padding(6)
                            .background(PoolDashboardTheme.panelMutedFill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(PoolDashboardTheme.panelInnerStroke))
                            .accessibilityLabel(L10n.text("report.message"))

                        Toggle(L10n.text("report.include_system_info"), isOn: $model.draft.includesSystemInfo)
                        if model.draft.includesSystemInfo {
                            Text(model.systemInfo)
                                .font(.caption.monospaced())
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                                .textSelection(.enabled)
                        }
                        Text(L10n.text("report.privacy_hint"))
                            .font(.caption)
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                    }
                    .disabled(model.isSubmitting)
                }

                if let errorMessage = model.errorMessage ?? model.validationMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(PoolDashboardTheme.warning)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }

            HStack {
                Link(L10n.text("settings.report_issue_github"), destination: IssueReportConfiguration.githubURL)
                Spacer()
                if model.isSubmitting {
                    ProgressView().controlSize(.small)
                }
                Button(L10n.text(model.isSubmitted ? "report.close" : "report.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isSubmitting)
                if !model.isSubmitted {
                    Button(L10n.text("report.send")) {
                        submitTask = Task { await model.submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canSubmit)
                }
            }
        }
        .padding(24)
        .frame(width: 540)
        .frame(minHeight: model.isSubmitted ? 220 : 540, maxHeight: 650)
        .background(PoolDashboardTheme.modalSolidFill)
        .foregroundStyle(PoolDashboardTheme.textPrimary)
        .tint(PoolDashboardTheme.glowA)
        .interactiveDismissDisabled(model.isSubmitting)
        .onDisappear { submitTask?.cancel() }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
        }
    }
}

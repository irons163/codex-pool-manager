import SwiftUI

struct LocalOAuthAccountsPanelView: View {
    let accounts: [LocalCodexOAuthAccount]
    let errorMessage: String?
    let successMessage: String?
    let importingAccountID: String?
    let onScan: () -> Void
    let onChooseAuthFile: () -> Void
    let onImport: (LocalCodexOAuthAccount) async -> Void

    var body: some View {
        GroupBox(L10n.text("local_oauth.title")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.localOAuthPanelSpacing) {
                Text(L10n.text("local_oauth.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: PoolDashboardTheme.actionRowSpacing) {
                        headerPrimaryButtons
                        Spacer(minLength: 0)
                        headerStatusView
                    }

                    VStack(alignment: .leading, spacing: PoolDashboardTheme.actionRowSpacing) {
                        headerPrimaryButtons
                        headerStatusView
                    }
                }

                if accounts.isEmpty {
                    PanelStatusCalloutView(
                        message: L10n.text("local_oauth.no_session.message"),
                        title: L10n.text("local_oauth.no_session.title"),
                        tone: .info
                    )
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var headerPrimaryButtons: some View {
        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
            Button(L10n.text("local_oauth.scan_button")) {
                onScan()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: true, vertical: false)

            Button(L10n.text("local_oauth.choose_button")) {
                onChooseAuthFile()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private var headerStatusView: some View {
        if let errorMessage {
            PanelStatusCalloutView(
                message: errorMessage,
                title: L10n.text("local_oauth.scan_failed"),
                tone: .danger
            )
            .frame(maxWidth: 460, alignment: .leading)
            .layoutPriority(1)
        } else if let successMessage {
            PanelStatusCalloutView(
                message: successMessage,
                title: L10n.text("local_oauth.import_result"),
                tone: .success
            )
            .frame(maxWidth: 460, alignment: .leading)
            .layoutPriority(1)
        } else {
            Text(L10n.text("local_oauth.session_count_format", accounts.count))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 100, alignment: .center)
                .statusBadge(tone: PoolDashboardTheme.panelMutedFill)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func accountRow(_ account: LocalCodexOAuthAccount) -> some View {
        let isImportingAccount = isImporting(account)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(PoolDashboardTheme.textPrimary)

                if let email = account.email {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                }

                Text(account.maskedToken)
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .lineLimit(1)

                let accountName = resolvedAccountName(for: account)
                Text(L10n.text("local_oauth.account_id_format", accountName))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                if account.chatGPTAccountID == nil {
                    PanelStatusCalloutView(
                        message: L10n.text("local_oauth.missing_id.message"),
                        title: L10n.text("local_oauth.missing_id.title"),
                        tone: .warning
                    )
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Button(isImportingAccount ? L10n.text("local_oauth.importing_button") : L10n.text("local_oauth.import_button")) {
                    Task { await onImport(account) }
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .disabled(account.chatGPTAccountID == nil || importingAccountID != nil)

                if account.chatGPTAccountID == nil {
                    Text(L10n.text("local_oauth.sync_unavailable"))
                        .font(.caption)
                        .foregroundStyle(PoolDashboardTheme.textMuted)
                }
            }
        }
        .padding(.vertical, PoolDashboardTheme.listRowVerticalInset * 3)
        .padding(.horizontal, 10)
        .dashboardInfoCard()
    }

    private func isImporting(_ account: LocalCodexOAuthAccount) -> Bool {
        importingAccountID == account.id
    }

    private func resolvedAccountName(for account: LocalCodexOAuthAccount) -> String {
        if let email = normalizedNonEmpty(account.email) {
            return email
        }
        if let tokenEmail = emailFromJWTPayload(account.accessToken) {
            return tokenEmail
        }
        return account.displayName
    }

    private func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func emailFromJWTPayload(_ token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        let normalizedPayload = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddedPayload = normalizedPayload.padding(
            toLength: ((normalizedPayload.count + 3) / 4) * 4,
            withPad: "=",
            startingAt: 0
        )

        guard let payloadData = Data(base64Encoded: paddedPayload),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else {
            return nil
        }

        if let email = normalizedNonEmpty(payload["email"] as? String) {
            return email
        }

        if let profile = payload["https://api.openai.com/profile"] as? [String: Any] {
            return normalizedNonEmpty(profile["email"] as? String)
        }

        return nil
    }
}

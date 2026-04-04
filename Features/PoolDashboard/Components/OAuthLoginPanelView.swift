import SwiftUI

struct OAuthLoginPanelView: View {
    @Binding var oauthIssuer: String
    @Binding var oauthClientID: String
    @Binding var oauthScopes: String
    @Binding var oauthRedirectURI: String
    @Binding var oauthOriginator: String
    @Binding var oauthWorkspaceID: String
    @Binding var oauthAccountName: String
    @Binding var oauthAccountQuota: Int

    let isSigningInOAuth: Bool
    let oauthSuccessMessage: String?
    let oauthError: String?
    let onSignIn: () async -> Void

    private let advancedColumns = [
        GridItem(.flexible(minimum: 220), spacing: 12),
        GridItem(.flexible(minimum: 220), spacing: 12)
    ]

    var body: some View {
        GroupBox(L10n.text("oauth.sign_in.title")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.oauthPanelSpacing) {
                Text(L10n.text("oauth.sign_in.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .frame(maxWidth: PoolDashboardTheme.subtitleReadableWidth, alignment: .leading)

                DisclosureGroup(L10n.text("oauth.advanced.title")) {
                    VStack(alignment: .leading, spacing: 10) {
                        LazyVGrid(columns: advancedColumns, alignment: .leading, spacing: 10) {
                            advancedField(L10n.text("oauth.client_id.label"), placeholder: L10n.text("oauth.client_id.placeholder"), text: $oauthClientID)
                            advancedField(L10n.text("oauth.issuer.label"), placeholder: "https://auth.openai.com", text: $oauthIssuer)
                            advancedField(L10n.text("oauth.scopes.label"), placeholder: "openid profile ...", text: $oauthScopes)
                            advancedField(L10n.text("oauth.redirect_uri.label"), placeholder: "http://localhost:1455/auth/callback", text: $oauthRedirectURI)
                            advancedField(L10n.text("oauth.originator.label"), placeholder: "codex_cli_rs", text: $oauthOriginator)
                            advancedField(L10n.text("oauth.workspace_id.label"), placeholder: L10n.text("oauth.workspace_id.optional"), text: $oauthWorkspaceID)
                        }

                        PanelStatusCalloutView(
                            message: L10n.text("oauth.workspace_id.hint"),
                            title: L10n.text("oauth.workspace_id.label"),
                            tone: .info
                        )

                        PanelStatusCalloutView(
                            message: L10n.text("oauth.client_id.public_hint"),
                            title: L10n.text("oauth.client_id.label"),
                            tone: .info
                        )
                    }
                    .padding(.top, 8)
                    .dashboardInfoCard()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

                PanelAdaptiveActionRowView {
                    actionRow
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var actionRow: some View {
        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
            Button(isSigningInOAuth ? L10n.text("oauth.signing_in") : L10n.text("oauth.sign_in_import")) {
                Task { await onSignIn() }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSigningInOAuth || oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("auth.oauth.signInButton")

            if let oauthSuccessMessage {
                PanelStatusCalloutView(
                    message: oauthSuccessMessage,
                    title: L10n.text("oauth.import_completed"),
                    tone: .success
                )
                .frame(maxWidth: 340, alignment: .leading)
            }

            if let oauthError {
                PanelStatusCalloutView(
                    message: oauthError,
                    title: L10n.text("oauth.sign_in_failed"),
                    tone: .danger
                )
                .frame(maxWidth: 340, alignment: .leading)
            }
        }
    }

    private func advancedField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            TextField(placeholder, text: text)
                .dashboardInputFieldStyle()
        }
    }
}

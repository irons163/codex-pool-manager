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
    @Binding var manualCallbackURL: String

    let isSigningInOAuth: Bool
    let oauthSuccessMessage: String?
    let oauthError: String?
    let manualAuthorizationURLOverride: String?
    let showManualImportSection: Bool
    let onSignIn: () -> Void
    let onCopyURLAndManualSignIn: () -> Void
    let onManualImport: () -> Void
    let onCancelSignIn: () -> Void

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

                advancedReadOnlyField(
                    L10n.text("oauth.authorization_url.label"),
                    value: authorizationURLText
                )
                .frame(maxWidth: 600, alignment: .leading)
                .dashboardInfoCard()

                PanelAdaptiveActionRowView {
                    actionRow
                }

                if showManualImportSection {
                    VStack(alignment: .leading, spacing: 10) {
                        advancedField(
                            L10n.text("oauth.manual.callback_url.label"),
                            placeholder: L10n.text("oauth.manual.callback_url.placeholder"),
                            text: $manualCallbackURL
                        )

                        Button(L10n.text("oauth.manual.import")) {
                            onManualImport()
                        }
                        .buttonStyle(DashboardPrimaryButtonStyle())
                        .disabled(isSigningInOAuth || manualCallbackURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .dashboardInfoCard()
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var actionRow: some View {
        HStack(spacing: PoolDashboardTheme.actionRowSpacing) {
            Button(isSigningInOAuth ? L10n.text("oauth.signing_in") : L10n.text("oauth.sign_in_import")) {
                onSignIn()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSigningInOAuth || oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("auth.oauth.signInButton")

            if isSigningInOAuth {
                Button(L10n.text("account.edit.cancel")) {
                    onCancelSignIn()
                }
                .buttonStyle(DashboardPrimaryButtonStyle())
                .accessibilityIdentifier("auth.oauth.cancelSignInButton")
            }

            Button(L10n.text("oauth.manual.copy_sign_in")) {
                onCopyURLAndManualSignIn()
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSigningInOAuth || oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("auth.oauth.copyManualSignInButton")

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

    private func advancedReadOnlyField(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                        .fill(PoolDashboardTheme.panelMutedFill.opacity(0.82))
                        .overlay(
                            RoundedRectangle(cornerRadius: PoolDashboardTheme.controlCornerRadius, style: .continuous)
                                .stroke(PoolDashboardTheme.panelInnerStroke.opacity(0.75), lineWidth: 0.8)
                        )
                )
                .textSelection(.enabled)
        }
    }

    private var authorizationURLText: String {
        if let manualAuthorizationURLOverride {
            let trimmed = manualAuthorizationURLOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let trimmedIssuer = oauthIssuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClientID = oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedScopes = oauthScopes.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirectURI = oauthRedirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginator = oauthOriginator.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkspaceID = oauthWorkspaceID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let issuerURL = URL(string: trimmedIssuer), !trimmedIssuer.isEmpty else {
            return "--"
        }

        guard let endpoint = URL(string: "/oauth/authorize", relativeTo: issuerURL)?.absoluteURL else {
            return "--"
        }

        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: trimmedRedirectURI),
            URLQueryItem(name: "scope", value: trimmedScopes),
            URLQueryItem(name: "code_challenge", value: "<CODE_CHALLENGE>"),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "state", value: "<STATE>"),
            URLQueryItem(name: "originator", value: trimmedOriginator)
        ]

        if !trimmedWorkspaceID.isEmpty {
            queryItems.append(URLQueryItem(name: "allowed_workspace_id", value: trimmedWorkspaceID))
        }

        components?.queryItems = queryItems
        return components?.url?.absoluteString ?? "--"
    }
}

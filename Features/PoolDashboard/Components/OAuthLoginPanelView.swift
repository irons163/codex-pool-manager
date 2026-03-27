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
        GroupBox("OAuth Sign-In") {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.oauthPanelSpacing) {
                Text("Use your own OAuth client to sign in, then import the resulting account into the pool.")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .frame(maxWidth: PoolDashboardTheme.subtitleReadableWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Client ID")
                        .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.textSecondary)
                    TextField("Paste OAuth client ID", text: $oauthClientID)
                        .dashboardInputFieldStyle()
                }
                .dashboardInfoCard()

                GroupBox("Import Target") {
                    HStack(alignment: .center, spacing: PoolDashboardTheme.accountAddRowSpacing) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Account Name")
                                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                                .foregroundStyle(PoolDashboardTheme.textSecondary)
                            TextField("Name after sign-in", text: $oauthAccountName)
                                .dashboardInputFieldStyle()
                        }
                        Stepper("Quota \(oauthAccountQuota)", value: $oauthAccountQuota, in: 100...20_000, step: 100)
                            .monospacedDigit()
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                }
                .sectionCardStyle()

                PanelStatusCalloutView(
                    message: "Workspace ID is optional for most personal flows; keep it empty unless your org requires it.",
                    title: "Configuration Hint",
                    tone: .info
                )

                DisclosureGroup("Advanced OAuth Parameters") {
                    LazyVGrid(columns: advancedColumns, alignment: .leading, spacing: 10) {
                        advancedField("Issuer", placeholder: "https://auth.openai.com", text: $oauthIssuer)
                        advancedField("Scopes", placeholder: "openid profile ...", text: $oauthScopes)
                        advancedField("Redirect URI", placeholder: "http://localhost:1455/auth/callback", text: $oauthRedirectURI)
                        advancedField("Originator", placeholder: "codex_cli_rs", text: $oauthOriginator)
                        advancedField("Workspace ID", placeholder: "Optional", text: $oauthWorkspaceID)
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
            Button(isSigningInOAuth ? "Signing In..." : "Sign In and Import") {
                Task { await onSignIn() }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSigningInOAuth || oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let oauthSuccessMessage {
                PanelStatusCalloutView(
                    message: oauthSuccessMessage,
                    title: "Import Completed",
                    tone: .success
                )
                .frame(maxWidth: 340, alignment: .leading)
            }

            if let oauthError {
                PanelStatusCalloutView(
                    message: oauthError,
                    title: "Sign-In Failed",
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

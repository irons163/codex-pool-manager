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

    var body: some View {
        GroupBox("OAuth 登入（你自行填 client_id）") {
            VStack(alignment: .leading, spacing: 14) {
                Text("輸入 Client ID 後可直接登入，進階參數通常維持預設即可。")
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                TextField("Client ID", text: $oauthClientID)
                    .dashboardInputFieldStyle()

                DisclosureGroup("進階設定（一般情況不用改）") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Issuer (例如 https://auth.openai.com)", text: $oauthIssuer)
                            .dashboardInputFieldStyle()
                        TextField("Scopes", text: $oauthScopes)
                            .dashboardInputFieldStyle()
                        TextField("Redirect URI", text: $oauthRedirectURI)
                            .dashboardInputFieldStyle()
                        TextField("Originator", text: $oauthOriginator)
                            .dashboardInputFieldStyle()
                        TextField("Allowed Workspace ID（可留空）", text: $oauthWorkspaceID)
                            .dashboardInputFieldStyle()
                    }
                    .padding(.top, 6)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PoolDashboardTheme.panelMutedFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(PoolDashboardTheme.panelInnerStroke, lineWidth: 1)
                            )
                    )
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

                HStack(alignment: .center, spacing: 12) {
                    TextField("登入後帳號名稱", text: $oauthAccountName)
                        .dashboardInputFieldStyle()
                    Stepper("配額 \(oauthAccountQuota)", value: $oauthAccountQuota, in: 100...20_000, step: 100)
                        .monospacedDigit()
                }

                ViewThatFits(in: .horizontal) {
                    oauthActionRow
                    VStack(alignment: .leading, spacing: 8) {
                        oauthActionRow
                    }
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    private var oauthActionRow: some View {
        HStack {
            Button(isSigningInOAuth ? "OAuth 登入中..." : "OAuth 登入並新增帳號") {
                Task {
                    await onSignIn()
                }
            }
            .buttonStyle(DashboardPrimaryButtonStyle())
            .disabled(isSigningInOAuth)

            if let oauthSuccessMessage {
                Text(oauthSuccessMessage)
                    .statusBadge(tone: PoolDashboardTheme.success.opacity(0.26))
            }
            if let oauthError {
                Text(oauthError)
                    .statusBadge(tone: PoolDashboardTheme.danger.opacity(0.26))
            }
        }
    }
}

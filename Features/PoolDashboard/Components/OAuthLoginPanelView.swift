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
            VStack(alignment: .leading, spacing: 12) {
                TextField("Client ID", text: $oauthClientID)
                    .textFieldStyle(.roundedBorder)

                DisclosureGroup("進階設定（一般情況不用改）") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Issuer (例如 https://auth.openai.com)", text: $oauthIssuer)
                            .textFieldStyle(.roundedBorder)
                        TextField("Scopes", text: $oauthScopes)
                            .textFieldStyle(.roundedBorder)
                        TextField("Redirect URI", text: $oauthRedirectURI)
                            .textFieldStyle(.roundedBorder)
                        TextField("Originator", text: $oauthOriginator)
                            .textFieldStyle(.roundedBorder)
                        TextField("Allowed Workspace ID（可留空）", text: $oauthWorkspaceID)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(.top, 4)
                }

                HStack {
                    TextField("登入後帳號名稱", text: $oauthAccountName)
                        .textFieldStyle(.roundedBorder)
                    Stepper("配額 \(oauthAccountQuota)", value: $oauthAccountQuota, in: 100...20_000, step: 100)
                }

                HStack {
                    Button(isSigningInOAuth ? "OAuth 登入中..." : "OAuth 登入並新增帳號") {
                        Task {
                            await onSignIn()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSigningInOAuth)
                    .tint(PoolDashboardTheme.glowA)

                    if let oauthSuccessMessage {
                        Text(oauthSuccessMessage)
                            .font(.footnote)
                            .foregroundStyle(PoolDashboardTheme.glowB)
                    }
                    if let oauthError {
                        Text(oauthError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .tint(PoolDashboardTheme.glowA)
    }
}

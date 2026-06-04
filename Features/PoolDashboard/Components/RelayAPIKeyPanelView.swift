import SwiftUI

struct RelayAPIKeyPanelView: View {
    @Binding var accountName: String
    @Binding var providerID: String
    @Binding var providerName: String
    @Binding var baseURL: String
    @Binding var wireAPI: String
    @Binding var apiKey: String

    let successMessage: String?
    let errorMessage: String?
    let onAddRelayAccount: () -> Void

    private let providerColumns = [
        GridItem(.adaptive(minimum: 220), spacing: 12)
    ]

    var body: some View {
        GroupBox(L10n.text("relay.title")) {
            VStack(alignment: .leading, spacing: PoolDashboardTheme.oauthPanelSpacing) {
                Text(L10n.text("relay.subtitle"))
                    .font(.footnote)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
                    .frame(maxWidth: PoolDashboardTheme.subtitleReadableWidth, alignment: .leading)

                LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 10) {
                    advancedField(
                        L10n.text("relay.account_name.label"),
                        placeholder: "Mirror",
                        text: $accountName
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("relay.api_key.label"))
                            .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                        SecureField(L10n.text("relay.api_key.placeholder"), text: $apiKey)
                            .dashboardInputFieldStyle()
                            .accessibilityIdentifier("auth.relay.apiKey")
                    }
                }

                DisclosureGroup(L10n.text("relay.advanced.title")) {
                    LazyVGrid(columns: providerColumns, alignment: .leading, spacing: 10) {
                        advancedField(
                            L10n.text("relay.provider_id.label"),
                            placeholder: PoolDashboardFormState.defaultRelayProviderID,
                            text: $providerID
                        )
                        advancedField(
                            L10n.text("relay.provider_name.label"),
                            placeholder: PoolDashboardFormState.defaultRelayProviderID,
                            text: $providerName
                        )
                        advancedField(
                            L10n.text("relay.base_url.label"),
                            placeholder: PoolDashboardFormState.defaultRelayBaseURL,
                            text: $baseURL
                        )
                        advancedField(
                            L10n.text("relay.wire_api.label"),
                            placeholder: AgentAccount.defaultRelayWireAPI,
                            text: $wireAPI
                        )
                    }
                    .padding(.top, 8)
                    .dashboardInfoCard()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

                PanelStatusCalloutView(
                    message: L10n.text("relay.usage_sync_unavailable.hint"),
                    title: L10n.text("relay.usage_sync_unavailable.title"),
                    tone: .info
                )

                PanelAdaptiveActionRowView {
                    Button(L10n.text("relay.add_button")) {
                        onAddRelayAccount()
                    }
                    .buttonStyle(DashboardPrimaryButtonStyle())
                    .disabled(!canAddRelayAccount)
                    .accessibilityIdentifier("auth.relay.addButton")

                    statusView
                }
            }
        }
        .sectionCardStyle()
        .tint(PoolDashboardTheme.glowA)
    }

    @ViewBuilder
    private var statusView: some View {
        if let successMessage {
            PanelStatusCalloutView(
                message: successMessage,
                title: L10n.text("relay.status.title"),
                tone: .success
            )
            .frame(maxWidth: 340, alignment: .leading)
        }

        if let errorMessage {
            PanelStatusCalloutView(
                message: errorMessage,
                title: L10n.text("relay.error.title"),
                tone: .danger
            )
            .frame(maxWidth: 340, alignment: .leading)
        }
    }

    private var canAddRelayAccount: Bool {
        !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

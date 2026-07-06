import SwiftUI

enum RelayAPIKeyFormReadiness {
    @inline(never)
    static func canAdd(providerID: String, baseURL: String, apiKey: String) -> Bool {
        !providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct RelayAPIKeyPanelView: View {
    enum FieldID: Equatable {
        case accountName
        case baseURL
        case apiKey
        case providerID
        case providerName
        case wireAPI
    }

    @Binding var accountName: String
    @Binding var providerID: String
    @Binding var providerName: String
    @Binding var baseURL: String
    @Binding var wireAPI: String
    @Binding var apiKey: String
    @Binding var preserveOfficialAuth: Bool
    @State private var isWireAPIHelpPresented = false

    let canAddRelayAccount: Bool
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
                    advancedField(
                        L10n.text("relay.base_url.label"),
                        placeholder: PoolDashboardFormState.defaultRelayBaseURL,
                        text: $baseURL
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
                        wireAPIField
                    }
                    .padding(.top, 8)
                    .dashboardInfoCard()
                }
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(PoolDashboardTheme.textSecondary)

                Toggle(isOn: $preserveOfficialAuth) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("relay.preserve_official_auth.toggle"))
                            .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                            .foregroundStyle(PoolDashboardTheme.textPrimary)
                        Text(L10n.text("relay.preserve_official_auth.hint"))
                            .font(.footnote)
                            .foregroundStyle(PoolDashboardTheme.textMuted)
                    }
                }
                .toggleStyle(.switch)
                .dashboardInfoCard()
                .accessibilityIdentifier("auth.relay.preserveOfficialAuth")

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

    private func advancedField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            TextField(placeholder, text: text)
                .dashboardInputFieldStyle()
        }
    }

    private var wireAPIField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(L10n.text("relay.wire_api.label"))
                    .font(PoolDashboardTheme.metadataFont.weight(.semibold))
                    .foregroundStyle(PoolDashboardTheme.textMuted)

                Button {
                    isWireAPIHelpPresented.toggle()
                } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PoolDashboardTheme.warning)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("relay.wire_api.help_button"))
                .popover(isPresented: $isWireAPIHelpPresented, arrowEdge: .bottom) {
                    wireAPIHelpPopover
                }
            }

            TextField(AgentAccount.defaultRelayWireAPI, text: $wireAPI)
                .dashboardInputFieldStyle()
        }
    }

    private var wireAPIHelpPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("relay.wire_api.help_title"))
                .font(.headline)
                .foregroundStyle(PoolDashboardTheme.textPrimary)

            Text(L10n.text("relay.wire_api.help_message"))
                .font(.footnote)
                .foregroundStyle(PoolDashboardTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
    }
}

#if DEBUG
extension RelayAPIKeyPanelView {
    static let debugPrimaryFieldIDs: [FieldID] = [.accountName, .baseURL, .apiKey]
    static let debugAdvancedFieldIDs: [FieldID] = [.providerID, .providerName, .wireAPI]

    @MainActor
    static func debugWireAPIHelpPopoverView() -> some View {
        RelayAPIKeyPanelView(
            accountName: .constant("debug"),
            providerID: .constant("debug-provider"),
            providerName: .constant("Debug Provider"),
            baseURL: .constant("https://example.com"),
            wireAPI: .constant(AgentAccount.defaultRelayWireAPI),
            apiKey: .constant("sk-debug"),
            preserveOfficialAuth: .constant(false),
            canAddRelayAccount: true,
            successMessage: nil,
            errorMessage: nil,
            onAddRelayAccount: {}
        )
        .wireAPIHelpPopover
    }
}
#endif

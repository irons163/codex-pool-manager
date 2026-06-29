import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var runtimeModel: AppPoolRuntimeModel

    let openDashboard: () -> Void
    let switchAccount: (UUID) -> Void

    private var snapshot: MenuBarDashboardSnapshot {
        runtimeModel.menuBarSnapshot
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if snapshot.accountRows.isEmpty {
                    emptyState
                } else {
                    activeAccountSection
                    warningsSection
                    accountsSection
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
        .frame(width: 390)
        .frame(minHeight: 420, maxHeight: 620)
        .background(background)
        .task {
            runtimeModel.bootstrapIfNeeded()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.95),
                                    Color.cyan.opacity(0.78)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("menu_bar.header.title"))
                        .font(.title3.weight(.semibold))
                    Text(snapshot.headerSummaryText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    Task { @MainActor in
                        await runtimeModel.syncNowWithTimeout()
                    }
                } label: {
                    Label(
                        L10n.text("menu_bar.action.sync_now"),
                        systemImage: snapshot.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
                    )
                }
                .disabled(snapshot.isSyncing)

                Button {
                    openDashboard()
                } label: {
                    Label(L10n.text("menu_bar.action.open_dashboard"), systemImage: "rectangle.3.group")
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 6) {
                if snapshot.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(snapshot.updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var activeAccountSection: some View {
        if let activeAccount = snapshot.activeAccount {
            SectionCard(title: L10n.text("menu_bar.section.active")) {
                AccountRowView(row: activeAccount, switchAccount: switchAccount)
            }
        }
    }

    @ViewBuilder
    private var warningsSection: some View {
        if !snapshot.warningRows.isEmpty {
            SectionCard(title: L10n.text("menu_bar.section.warnings")) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.warningRows) { warning in
                        WarningRowView(row: warning)
                    }
                }
            }
        }
    }

    private var accountsSection: some View {
        SectionCard(title: L10n.text("menu_bar.section.accounts")) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.accountRows) { row in
                    AccountRowView(row: row, switchAccount: switchAccount)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 4) {
                Text(L10n.text("menu_bar.empty.title"))
                    .font(.headline)
                Text(L10n.text("menu_bar.empty.message"))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                openDashboard()
            } label: {
                Label(L10n.text("menu_bar.action.open_dashboard"), systemImage: "rectangle.3.group")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.10),
                    Color.cyan.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 44)
                .offset(x: -150, y: -230)

            Circle()
                .fill(Color.cyan.opacity(0.10))
                .frame(width: 160, height: 160)
                .blur(radius: 40)
                .offset(x: 160, y: 260)
        }
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 0.8)
        }
    }
}

private struct AccountRowView: View {
    let row: MenuBarAccountRow
    let switchAccount: (UUID) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            activeIndicator

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    if row.isPaid {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }

                    if let credentialLabel = row.credentialLabel {
                        Text(credentialLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                    }
                }

                HStack(spacing: 8) {
                    MetricPill(text: row.weeklyRemainingText, systemImage: "calendar")

                    if let fiveHourRemainingText = row.fiveHourRemainingText {
                        MetricPill(text: "5h \(fiveHourRemainingText)", systemImage: "timer")
                    }

                    MetricPill(text: row.resetText, systemImage: "arrow.counterclockwise")
                }

                if let warningText = row.warningText,
                   !warningText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(warningText)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if row.isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel(L10n.text("menu_bar.section.active"))
            } else {
                Button(L10n.text("menu_bar.action.switch")) {
                    switchAccount(row.id)
                }
                .accessibilityLabel("\(L10n.text("menu_bar.action.switch")) \(row.name)")
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var activeIndicator: some View {
        Circle()
            .fill(row.isActive ? Color.accentColor : Color.secondary.opacity(0.35))
            .frame(width: 8, height: 8)
    }

    private var rowBackground: some ShapeStyle {
        row.isActive ? Color.accentColor.opacity(0.13) : Color.secondary.opacity(0.07)
    }
}

private struct WarningRowView: View {
    let row: MenuBarWarningRow

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: systemImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(row.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tint: Color {
        switch row.kind {
        case .oauthExpired, .syncFailed:
            return .orange
        case .relayUsageUnavailable:
            return .blue
        case .excluded:
            return .secondary
        }
    }

    private var systemImage: String {
        switch row.kind {
        case .oauthExpired:
            return "person.crop.circle.badge.exclamationmark"
        case .relayUsageUnavailable:
            return "key.horizontal"
        case .syncFailed:
            return "exclamationmark.triangle"
        case .excluded:
            return "minus.circle"
        }
    }
}

private struct MetricPill: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

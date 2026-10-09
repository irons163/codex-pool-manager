import SwiftUI
import Charts
import UniformTypeIdentifiers

struct SessionUsageAnalyticsPanelView: View {
    @State private var model: SessionUsageAnalyticsModel
    @State private var isSourcePickerPresented = false
    @State private var selectedRequest: CodexSessionUsageRecord?
    @State private var panelWidth: CGFloat = 0
    private let scansAutomatically: Bool

    @MainActor
    init(model: SessionUsageAnalyticsModel? = nil, scansAutomatically: Bool = true) {
        _model = State(initialValue: model ?? .live())
        self.scansAutomatically = scansAutomatically
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            filters
            status
            summaryCards
            Text(L10n.text("session_usage.cost_note"))
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
            if !model.records.isEmpty {
                trendChart
                heatmap
            }
            detailSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { panelWidth = $0 }
        .task { if scansAutomatically { await model.task() } }
        .fileImporter(isPresented: $isSourcePickerPresented, allowedContentTypes: [.folder], allowsMultipleSelection: false) {
            sourcePickerCompleted($0)
        }
        .sheet(item: $model.priceEditor) { editor in
            priceEditor(editor)
        }
        .sheet(item: $selectedRequest) { record in
            requestDetail(record)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                heading
                Spacer()
                sourceControls.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 10) {
                heading
                sourceControls
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.text("session_usage.title"))
                .font(.title2.weight(.bold))
                .foregroundStyle(PoolDashboardTheme.textPrimary)
            Text(L10n.text("session_usage.source"))
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
    }

    private var sourceControls: some View {
        HStack(spacing: 10) {
            if model.isLoading { ProgressView().controlSize(.small) }
            if let lastSyncedAt = model.lastSyncedAt {
                Text(lastSyncedAt.formatted(.dateTime.locale(L10n.locale()).hour().minute()))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }
            Button { isSourcePickerPresented = true } label: {
                Label(L10n.text("session_usage.data_source"), systemImage: "folder")
            }
            .help(model.root.path)
            Button { Task { await model.refreshButtonTapped() } } label: {
                Label(L10n.text("session_usage.sync"), systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading)
            .buttonStyle(.borderedProminent)
        }
    }

    private var filters: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    rangePicker
                    modelPicker
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 10) {
                    rangePicker
                    modelPicker
                }
            }
            if model.range == .custom {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        DatePicker(L10n.text("session_usage.from"), selection: $model.customStart, displayedComponents: [.date])
                        DatePicker(L10n.text("session_usage.to"), selection: $model.customEnd, displayedComponents: [.date])
                    }
                    VStack(alignment: .leading) {
                        DatePicker(L10n.text("session_usage.from"), selection: $model.customStart, displayedComponents: [.date])
                        DatePicker(L10n.text("session_usage.to"), selection: $model.customEnd, displayedComponents: [.date])
                    }
                }
            }
        }
        .dashboardInfoCard()
    }

    private var rangePicker: some View {
        @Bindable var model = model
        return Picker(L10n.text("session_usage.range"), selection: $model.range) {
            ForEach(CodexSessionUsageRange.allCases) { range in
                Text(L10n.text("session_usage.range.\(range.rawValue)")).tag(range)
            }
        }
        .pickerStyle(.menu)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var modelPicker: some View {
        @Bindable var model = model
        return Picker(L10n.text("session_usage.model"), selection: $model.selectedModel) {
            Text(L10n.text("session_usage.all_models")).tag("")
            ForEach(model.availableModels, id: \.self) { name in Text(modelName(name)).tag(name) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 360, alignment: .leading)
    }

    @ViewBuilder
    private var status: some View {
        if model.hasReadError {
            PanelStatusCalloutView(message: L10n.text("session_usage.read_error"), tone: .warning)
        } else if model.report.isPartial {
            PanelStatusCalloutView(message: L10n.text("session_usage.partial"), tone: .warning)
        }
        if !model.isLoading && model.records.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(L10n.text("session_usage.empty"), systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Text(L10n.text("session_usage.empty_hint"))
                    .font(.callout)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dashboardInfoCard()
        }
    }

    private var summaryCards: some View {
        let summary = model.summary
        let columnCount = min(4, max(1, Int((panelWidth + 12) / 192)))
        let columns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top), count: columnCount)
        return LazyVGrid(columns: columns, spacing: 12) {
            metricCard("session_usage.tokens", value: number(summary.tokens.total), symbol: "square.stack.3d.up")
            metricCard("session_usage.requests", value: number(Int64(summary.requestCount)), symbol: "arrow.left.arrow.right")
            metricCard("session_usage.cache_rate", value: summary.cacheHitRate.map { $0.formatted(.percent.precision(.fractionLength(1)).locale(L10n.locale())) } ?? "—", symbol: "memorychip")
            metricCard("session_usage.cost", value: summary.totalCost.map(currency) ?? L10n.text("session_usage.unpriced"), symbol: "dollarsign.circle")
        }
    }

    private func metricCard(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text(title), systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PoolDashboardTheme.textMuted)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            if title == "session_usage.tokens" {
                Text(L10n.text("session_usage.token_breakdown", number(model.summary.tokens.freshInput), number(model.summary.tokens.output), number(model.summary.tokens.cachedInput)))
                    .font(.caption2)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardInfoCard()
    }

    private var trendChart: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("session_usage.trend")).font(.headline)
                Spacer()
                Picker(L10n.text("session_usage.metric"), selection: $model.chartMetric) {
                    ForEach(SessionUsageAnalyticsModel.ChartMetric.allCases) { metric in
                        Text(L10n.text("session_usage.metric.\(metric.rawValue)")).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .labelsHidden()
            }
            Chart(model.buckets) { bucket in
                if let value = chartValue(bucket.summary) {
                    BarMark(x: .value(L10n.text("session_usage.time"), bucket.date), y: .value(L10n.text("session_usage.metric.\(model.chartMetric.rawValue)"), value))
                        .foregroundStyle(PoolDashboardTheme.glowA.gradient)
                        .cornerRadius(3)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXScale(range: .plotDimension(padding: 12))
            .frame(height: 190)
            if model.chartMetric == .cost && model.summary.unpricedRequests > 0 {
                Text(L10n.text("session_usage.unpriced_hint"))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.warning)
            }
        }
        .dashboardInfoCard()
    }

    private var heatmap: some View {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: model.now)
        let start = calendar.date(byAdding: .day, value: -370, to: today) ?? today
        let values = Dictionary(grouping: model.report.records.filter {
            $0.timestamp >= start && $0.timestamp <= model.now && (model.selectedModel.isEmpty || $0.model == model.selectedModel)
        }, by: { calendar.startOfDay(for: $0.timestamp) }).mapValues { $0.reduce(Int64(0)) { $0 + $1.tokens.total } }
        let maximum = max(1, values.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("session_usage.activity")).font(.headline)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<53, id: \.self) { week in
                        VStack(spacing: 3) {
                            ForEach(0..<7, id: \.self) { day in
                                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: start) ?? today
                                let count = values[date] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(count == 0 ? PoolDashboardTheme.textMuted.opacity(0.12) : PoolDashboardTheme.glowA.opacity(0.25 + 0.75 * Double(count) / Double(maximum)))
                                    .frame(width: 10, height: 10)
                                    .help("\(date.formatted(.dateTime.locale(L10n.locale()).year().month().day())) · \(number(count)) tokens")
                            }
                        }
                    }
                }
            }
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .defaultScrollAnchor(.leading, for: .alignment)
            Text(L10n.text("session_usage.activity_hint"))
                .font(.caption2)
                .foregroundStyle(PoolDashboardTheme.textMuted)
        }
        .dashboardInfoCard()
    }

    private var detailSection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.text("session_usage.details"), selection: $model.detailTab) {
                ForEach(SessionUsageAnalyticsModel.DetailTab.allCases) { tab in
                    Text(L10n.text("session_usage.tab.\(tab.rawValue)")).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch model.detailTab {
            case .requests: requestTable
            case .models: modelTable
            case .pricing: pricingTable
            }
        }
        .dashboardInfoCard()
    }

    private var requestTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text("session_usage.requests_hint"))
                .font(.caption)
                .foregroundStyle(PoolDashboardTheme.textMuted)
            ScrollView(.horizontal) {
                Table(Array(model.records.prefix(200))) {
                    TableColumn(L10n.text("session_usage.time")) { record in
                        Button(record.timestamp.formatted(.dateTime.locale(L10n.locale()).month().day().hour().minute())) { selectedRequest = record }
                            .buttonStyle(.plain)
                    }.width(min: 120, ideal: 145)
                    TableColumn(L10n.text("session_usage.model")) { Text(modelName($0.model)) }.width(min: 140, ideal: 180)
                    TableColumn(L10n.text("session_usage.input")) { Text(number($0.tokens.freshInput)).monospacedDigit() }.width(min: 100, ideal: 110)
                    TableColumn(L10n.text("session_usage.output")) { Text(number($0.tokens.output)).monospacedDigit() }.width(min: 90, ideal: 100)
                    TableColumn(L10n.text("session_usage.cache")) { Text(number($0.tokens.cachedInput)).monospacedDigit() }.width(min: 100, ideal: 110)
                    TableColumn(L10n.text("session_usage.cost")) { record in
                        Text(model.prices[record.model].map { currency($0.cost(for: record.tokens)) } ?? L10n.text("session_usage.unpriced"))
                    }.width(min: 110, ideal: 125)
                }
                .frame(minWidth: max(840, panelWidth - 20), minHeight: 240, maxHeight: 340)
            }
            if model.records.count > 200 {
                Text(L10n.text("session_usage.log_limit"))
                    .font(.caption)
                    .foregroundStyle(PoolDashboardTheme.textMuted)
            }
        }
    }

    private var modelTable: some View {
        ScrollView(.horizontal) {
            Table(model.models) {
                TableColumn(L10n.text("session_usage.model")) { Text(modelName($0.model)) }.width(min: 150, ideal: 210)
                TableColumn(L10n.text("session_usage.requests")) { Text(number(Int64($0.summary.requestCount))) }.width(min: 120, ideal: 140)
                TableColumn(L10n.text("session_usage.tokens")) { Text(number($0.summary.tokens.total)) }.width(min: 130, ideal: 160)
                TableColumn(L10n.text("session_usage.cost")) { row in Text(row.summary.totalCost.map(currency) ?? L10n.text("session_usage.unpriced")) }.width(min: 130, ideal: 150)
            }
            .frame(minWidth: max(680, panelWidth - 20), minHeight: 160, maxHeight: 260)
        }
    }

    private var pricingTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text("session_usage.price_unit")).font(.caption)
                Spacer()
                Button(L10n.text("session_usage.add_price")) { model.pricingButtonTapped(model: "") }
            }
            ForEach(Array(Set(model.availableModels).union(model.prices.keys)).sorted(), id: \.self) { name in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(modelName(name)).font(.subheadline.weight(.semibold))
                        if let price = model.prices[name] {
                            Text(L10n.text("session_usage.price_breakdown", currency(price.input), currency(price.cachedInput), currency(price.output)))
                                .font(.caption)
                                .foregroundStyle(PoolDashboardTheme.textMuted)
                        } else { Text(L10n.text("session_usage.unpriced")).font(.caption) }
                    }
                    Spacer()
                    Button(L10n.text("session_usage.edit_price")) { model.pricingButtonTapped(model: name) }
                    if model.prices[name] != nil {
                        Button(role: .destructive) { model.removePricingButtonTapped(model: name) } label: { Image(systemName: "trash") }
                            .accessibilityLabel(L10n.text("session_usage.remove_price"))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func priceEditor(_ editor: CodexModelPriceEditor) -> some View {
        @Bindable var editor = editor
        return VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("session_usage.edit_price")).font(.title2.weight(.bold))
            Text(L10n.text("session_usage.price_unit")).font(.caption)
            Form {
                TextField(L10n.text("session_usage.model"), text: $editor.model)
                TextField(L10n.text("session_usage.input"), text: $editor.input)
                TextField(L10n.text("session_usage.cache"), text: $editor.cachedInput)
                TextField(L10n.text("session_usage.output"), text: $editor.output)
            }
            Text(L10n.text("session_usage.cost_note")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.text("session_usage.cancel")) { model.priceEditor = nil }
                Button(L10n.text("session_usage.save")) { model.savePricingButtonTapped() }
                    .disabled(editor.price == nil)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func requestDetail(_ record: CodexSessionUsageRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(modelName(record.model)).font(.title2.weight(.bold))
            Text(record.timestamp.formatted(.dateTime.locale(L10n.locale()).year().month().day().hour().minute().second()))
            LabeledContent(L10n.text("session_usage.input"), value: number(record.tokens.freshInput))
            LabeledContent(L10n.text("session_usage.output"), value: number(record.tokens.output))
            LabeledContent(L10n.text("session_usage.cache"), value: number(record.tokens.cachedInput))
            LabeledContent(L10n.text("session_usage.tokens"), value: number(record.tokens.total))
            Text(L10n.text("session_usage.source")).font(.caption).foregroundStyle(.secondary)
            Text(L10n.text("session_usage.requests_hint")).font(.caption).foregroundStyle(.secondary)
            Text(record.sessionID).font(.caption.monospaced()).textSelection(.enabled)
            Button(L10n.text("session_usage.close")) { selectedRequest = nil }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 460)
    }

    private func chartValue(_ summary: CodexSessionUsageSummary) -> Double? {
        switch model.chartMetric {
        case .tokens: Double(summary.tokens.total)
        case .requests: Double(summary.requestCount)
        case .cost: summary.totalCost
        }
    }

    private func sourcePickerCompleted(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        Task { await model.dataSourceChosen(url) }
    }

    private func number(_ value: Int64) -> String { value.formatted(.number.locale(L10n.locale())) }
    private func currency(_ value: Double) -> String { value.formatted(.currency(code: "USD").precision(.fractionLength(4)).locale(L10n.locale())) }
    private func modelName(_ value: String) -> String { value == "unknown" ? L10n.text("session_usage.unknown_model") : value }
}

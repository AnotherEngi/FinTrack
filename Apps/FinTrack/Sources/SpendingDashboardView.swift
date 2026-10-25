import SwiftUI
import Charts
import FinTrackCore

@MainActor
struct OverviewView: View {
    @Bindable var ledger: LedgerViewModel
    var openReview: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var scope = DisplayScope()
    @State private var excludedCategories: Set<String> = []
    @State private var showHidden = false
    @State private var selection: SummaryContext?
    @State private var editor: EditorDraft?

    private enum SummaryContext: Equatable { case period(String), category(String), unallocated }
    private var visibility: SummaryVisibility { ledger.workspace.summaryVisibility ?? .init() }
    private var rangeKey: String {
        let bounds = scope.selection
        return scope.period.rawValue + ":" + (bounds.from?.iso8601 ?? "") + ":" + (bounds.through?.iso8601 ?? "")
    }

    private func report(excluding categories: Set<String>) throws -> SummaryReport {
        guard scope.isValid else { throw LedgerError.invalidDate }
        return try SummaryReport(records: ledger.records, catalog: ledger.catalog,
            from: scope.selection.from, through: scope.selection.through,
            visibility: visibility, showHidden: showHidden, excludedCategories: categories)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        DisplayScopeControls(scope: $scope)
                        Spacer(minLength: 0)
                        Toggle("Show hidden", isOn: $showHidden).fixedSize()
                    }
                    switch Result(catching: { try report(excluding: []) }) {
                    case .success(let base):
                        switch Result(catching: { excludedCategories.isEmpty ? base : try report(excluding: excludedCategories) }) {
                        case .success(let data): dashboard(data, legend: base.categories, height: geometry.size.height)
                        case .failure(let error): failure(error)
                        }
                    case .failure(let error): failure(error)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add Synthetic Chart Examples", systemImage: "testtube.2") { ledger.loadSpendingSamples() }
                }
            }
            .onChange(of: rangeKey) { _, _ in resetTemporaryFilters() }
            .onChange(of: showHidden) { _, _ in selection = nil }
            .onChange(of: visibility) { _, _ in selection = nil }
            .onChange(of: scenePhase) { _, phase in if phase == .background { resetTemporaryFilters() } }
            .sheet(item: $editor, onDismiss: { ledger.reload() }) { draft in
                TransactionEditorView(ledger: ledger, draft: draft) { _ in }.id(draft.id)
            }
        }
    }

    private func failure(_ error: Error) -> some View {
        VStack(alignment: .leading) {
            Label("Unable to calculate this summary", systemImage: "exclamationmark.triangle")
            Text(error.localizedDescription).font(.callout)
            Button("Open Transactions", action: openReview)
        }.foregroundStyle(.red)
    }

    private func dashboard(_ data: SummaryReport, legend: [SummaryCategory], height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 20) {
                Text("Spending " + data.total.decimalText).monospacedDigit()
                Text("Pending " + data.pending.decimalText).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                if !data.unallocatedRefundIDs.isEmpty {
                    Button("Link refunds: " + data.unallocatedRefundAmount.decimalText) { selection = .unallocated }
                }
            }.font(.callout)
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Spending by " + data.interval.rawValue).font(.headline)
                        Spacer()
                        Menu("Select period") {
                            ForEach(data.periods) { period in
                                Button(period.label) { selection = .period(period.id) }
                            }
                        }.font(.caption)
                    }
                    barChart(data).frame(height: chartHeight(height))
                }
                .padding(12).frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categories · full selected range").font(.headline)
                    pieChart(data).frame(height: chartHeight(height))
                }
                .padding(12).frame(maxWidth: .infinity)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            HStack(alignment: .top, spacing: 14) {
                categoryLegend(legend)
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                purchasesPanel(data)
                    .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }.frame(maxHeight: .infinity)
            Text("Linked refunds reduce original purchase dates. Unlinked refunds need allocation. Missing history is unknown.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func chartHeight(_ available: CGFloat) -> CGFloat { max(100, min(270, available * 0.38)) }

    private func barChart(_ data: SummaryReport) -> some View {
        Chart(data.bars) { bar in
            BarMark(x: .value("Period", bar.periodID), y: .value("Spending", Int(bar.amount.minorUnits)))
                .foregroundStyle(by: .value("Category", bar.categoryID))
                .opacity(isSelected(period: bar.periodID) ? 1 : 0.55)
                .accessibilityLabel(periodLabel(bar.periodID, interval: data.interval) + ", " + categoryLabel(bar.categoryID))
                .accessibilityValue(bar.amount.decimalText)
        }
        .chartLegend(.hidden)
        .chartXScale(domain: data.periods.map(\.id))
        .chartForegroundStyleScale(domain: data.categories.map(\.id), range: data.categories.map { categoryColor($0.id) })
        .chartYAxis { moneyAxis }
        .chartXAxis {
            AxisMarks(values: data.periods.map(\.id)) { value in
                AxisValueLabel {
                    if let period = value.as(String.self), let entry = data.periods.first(where: { $0.id == period }) {
                        Text(entry.axisLabel).font(.caption2).lineLimit(1)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        guard frame.contains(tap.location),
                              let period = proxy.value(atX: tap.location.x - frame.minX, as: String.self),
                              let amount = proxy.value(atY: tap.location.y - frame.minY, as: Int.self) else { return }
                        let total = data.bars.filter { $0.periodID == period }.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
                        guard total > 0, amount >= 0, Int64(amount) <= total else { return }
                        selection = .period(period)
                    })
            }
        }
        .overlay { if data.bars.isEmpty { Text("No posted purchases in this view").foregroundStyle(.secondary) } }
        .accessibilityHint("Click a bar or use Select period to list that period's purchases.")
    }

    private func pieChart(_ data: SummaryReport) -> some View {
        let slices = data.categories.filter { $0.amount.minorUnits > 0 }
        return Chart(slices) { category in
            SectorMark(angle: .value("Spending", Int(category.amount.minorUnits)), innerRadius: .ratio(0), outerRadius: .ratio(1))
                .foregroundStyle(by: .value("Category", category.id))
                .opacity(isSelected(category: category.id) ? 1 : 0.55)
                .accessibilityLabel(category.label).accessibilityValue(category.amount.decimalText)
        }
        .chartLegend(.hidden)
        .chartForegroundStyleScale(domain: data.categories.map(\.id), range: data.categories.map { categoryColor($0.id) })
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let frame = geometry[anchor]
                        let dx = tap.location.x - frame.midX, dy = tap.location.y - frame.midY
                        let radius = min(frame.width, frame.height) / 2
                        guard dx * dx + dy * dy <= radius * radius, dx != 0 || dy != 0 else { return }
                        // Floating point is used only for pointer geometry. All accounting
                        // values, aggregation, and slice boundaries remain integer cents.
                        var radians = atan2(Double(dx), Double(-dy))
                        if radians < 0 { radians += 2 * .pi }
                        guard let cents = proxy.value(atAngle: .radians(radians), as: Int.self) else { return }
                        var end: Int64 = 0
                        for category in slices {
                            end += category.amount.minorUnits
                            if Int64(cents) < end { selection = .category(category.id); break }
                        }
                    })
            }
        }
        .overlay { if slices.isEmpty { Text("No net spending in this view").foregroundStyle(.secondary) } }
        .accessibilityHint("Click a slice or its category name in the legend to list purchases.")
    }

    private func categoryLegend(_ categories: [SummaryCategory]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if categories.isEmpty { Text("Categories appear when posted purchases are available.").foregroundStyle(.secondary) }
                ForEach(categories) { category in
                    HStack(spacing: 10) {
                        Circle().fill(categoryColor(category.id)).frame(width: 12, height: 12)
                        Button { selection = .category(category.id) } label: {
                            HStack { Text(category.label); Spacer(); Text(category.amount.decimalText).monospacedDigit() }
                        }.buttonStyle(.plain)
                        Toggle("Include " + category.label, isOn: Binding(
                            get: { !excludedCategories.contains(category.id) },
                            set: { included in
                                if included { excludedCategories.remove(category.id) } else { excludedCategories.insert(category.id) }
                                selection = nil
                            }))
                            .labelsHidden().tint(categoryColor(category.id)).fixedSize()
                    }.frame(minHeight: 44)
                }
            }
        }.frame(maxHeight: .infinity)
    }

    private func purchasesPanel(_ data: SummaryReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contextTitle(data)).font(.subheadline.bold())
                Spacer()
                if selection != nil { Button("Clear") { selection = nil }.font(.caption) }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if selection == .unallocated {
                        ForEach(ledger.records.filter { data.unallocatedRefundIDs.contains($0.id) }) { refund in
                            Button { editor = ledger.editor(for: refund) } label: {
                                HStack { Text(refund.draft.payee); Spacer(); Text(refund.draft.amount.decimalText).monospacedDigit() }
                            }
                            Text("Received " + refund.draft.date.iso8601 + " · open to link purchases").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let selection {
                        let rows = selectedPurchases(data, context: selection)
                        if rows.isEmpty { Text("No purchases in this selection.").foregroundStyle(.secondary) }
                        ForEach(rows) { row in purchaseRow(row) }
                    }
                }
            }.frame(maxHeight: .infinity)
        }.frame(maxHeight: .infinity)
    }

    private func purchaseRow(_ row: SummaryPurchase) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let record = ledger.record(id: row.recordID) {
                Button { editor = ledger.editor(for: record) } label: {
                    HStack { Text(record.draft.payee); Spacer(); Text(row.net.decimalText).monospacedDigit() }
                }.buttonStyle(.plain)
                Text(row.date.iso8601 + " · " + categoryLabel(row.categoryID)).font(.caption).foregroundStyle(.secondary)
                if !row.refundIDs.isEmpty {
                    Text("Purchase " + record.draft.amount.decimalText + "; linked refunds deducted")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(row.refundIDs, id: \.self) { id in
                        if let refund = ledger.record(id: id) {
                            Button("Refund received " + refund.draft.date.iso8601) { editor = ledger.editor(for: refund) }.font(.caption2)
                        }
                    }
                }
            }
            Divider()
        }
    }

    private func selectedPurchases(_ data: SummaryReport, context: SummaryContext) -> [SummaryPurchase] {
        data.purchases.filter { row in
            switch context { case .period(let id): row.periodID == id; case .category(let id): row.categoryID == id; case .unallocated: false }
        }
    }
    private func contextTitle(_ data: SummaryReport) -> String {
        switch selection {
        case .period(let id): periodLabel(id, interval: data.interval)
        case .category(let id): categoryLabel(id)
        case .unallocated: "Refunds needing purchase links"
        case nil: "Purchases · select a bar or slice"
        }
    }
    private func categoryLabel(_ id: String) -> String { ledger.catalog.category(id: id)?.label ?? (id.isEmpty ? "No category" : id) }
    private func periodLabel(_ id: String, interval: SummaryInterval) -> String { interval == .week ? "Week of " + id : id }
    private func isSelected(period: String) -> Bool { if case .period(let id)? = selection { return id == period }; return true }
    private func isSelected(category: String) -> Bool { if case .category(let id)? = selection { return id == category }; return true }
    private func resetTemporaryFilters() { excludedCategories = []; selection = nil }
    private func categoryColor(_ id: String) -> Color {
        let palette: [Color] = [.blue, .orange, .teal, .purple, .pink, .indigo, .green, .brown, .cyan, .red, .mint]
        let known = ledger.catalog.categories.map(\.id).sorted()
        if let index = known.firstIndex(of: id), index < palette.count { return palette[index] }
        if id.isEmpty { return .gray }
        // Stable across launches; never use Swift's randomly seeded Hasher.
        let value = id.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return palette[Int(value % UInt64(palette.count))]
    }
    private var moneyAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel { if let cents = value.as(Int.self) { Text(Money(minorUnits: Int64(cents)).decimalText) } }
        }
    }
}

@MainActor
struct VisibilityView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var search = ""
    @State private var picker: RuleKind?
    @State private var ruleSearch = ""
    @State private var editor: EditorDraft?
    private enum RuleKind: String, Identifiable { case category, tag; var id: Self { self } }
    private var settings: SummaryVisibility { ledger.workspace.summaryVisibility ?? .init() }
    private var categoryIDs: [String] {
        Set(ledger.catalog.categories.map(\.id)).union(ledger.records.map { $0.draft.categoryID ?? "" }).union(settings.categoryIDs).sorted()
    }
    private var tags: [String] { Set(ledger.records.flatMap { $0.draft.tags }).union(settings.tags).sorted() }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hide from Overview only. Transactions, discussions, and ChatGPT packets keep all records. A category or tag rule also hides future matching transactions. These settings save immediately and are included in backups.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section("Hidden categories") {
                    ForEach(settings.categoryIDs.sorted(), id: \.self) { id in
                        HStack {
                            Text(categoryLabel(id)); Spacer()
                            Button("Show") { categoryBinding(id).wrappedValue = false }
                                .accessibilityLabel("Show category " + categoryLabel(id))
                        }
                    }
                    Button("Add Category", systemImage: "plus") { ruleSearch = ""; picker = .category }
                }
                Section("Hidden tags") {
                    ForEach(settings.tags.sorted(), id: \.self) { tag in
                        HStack { Text(tag); Spacer(); Button("Show") { tagBinding(tag).wrappedValue = false }.accessibilityLabel("Show tag " + tag) }
                    }
                    Button("Add Tag", systemImage: "plus") { ruleSearch = ""; picker = .tag }
                }
                Section("Hidden transactions") {
                    Text("Hide an individual transaction in its editor. Category and tag rules also hide matching transactions.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ledger.records.filter { settings.hides($0) && (search.isEmpty || $0.draft.payee.localizedCaseInsensitiveContains(search)
                        || $0.draft.date.iso8601.contains(search)) }) { record in
                        HStack {
                        Button { editor = ledger.editor(for: record) } label: {
                            VStack(alignment: .leading) {
                                Text(record.draft.payee)
                                Text(record.draft.date.iso8601 + " · " + record.draft.amount.decimalText).font(.caption).foregroundStyle(.secondary)
                                if settings.hides(record), !settings.recordIDs.contains(record.id) {
                                    Text("Hidden by a category or tag rule").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.buttonStyle(.plain)
                        Spacer()
                        if settings.recordIDs.contains(record.id) {
                            Button("Show") { recordBinding(record.id).wrappedValue = false }
                                .accessibilityLabel("Remove individual hiding for " + record.draft.payee)
                        }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Find hidden transactions")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editor) { draft in TransactionEditorView(ledger: ledger, draft: draft) { _ in }.id(draft.id) }
            .sheet(item: $picker) { kind in
                NavigationStack {
                    List {
                        ForEach((kind == .category ? categoryIDs : tags).filter {
                            ruleSearch.isEmpty || (kind == .category ? categoryLabel($0) : $0).localizedCaseInsensitiveContains(ruleSearch)
                        }, id: \.self) { value in
                            let hidden = kind == .category ? settings.categoryIDs.contains(value) : settings.tags.contains(value)
                            Button {
                                if kind == .category { categoryBinding(value).wrappedValue = true }
                                else { tagBinding(value).wrappedValue = true }
                            } label: {
                                HStack { Text(kind == .category ? categoryLabel(value) : value); Spacer(); if hidden { Image(systemName: "checkmark") } }
                            }.disabled(hidden)
                        }
                    }
                    .navigationTitle(kind == .category ? "Hide Categories" : "Hide Tags")
                    .searchable(text: $ruleSearch)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { picker = nil } } }
                }
            }
        }
    }
    private func categoryLabel(_ id: String) -> String { ledger.catalog.category(id: id)?.label ?? (id.isEmpty ? "No category" : id) }
    private func categoryBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { settings.categoryIDs.contains(id) }, set: { hidden in
            var copy = settings; if hidden { copy.categoryIDs.insert(id) } else { copy.categoryIDs.remove(id) }
            ledger.saveSummaryVisibility(copy)
        })
    }
    private func tagBinding(_ tag: String) -> Binding<Bool> {
        Binding(get: { settings.tags.contains(tag) }, set: { hidden in
            var copy = settings; if hidden { copy.tags.insert(tag) } else { copy.tags.remove(tag) }
            ledger.saveSummaryVisibility(copy)
        })
    }
    private func recordBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { settings.recordIDs.contains(id) }, set: { hidden in
            var copy = settings; if hidden { copy.recordIDs.insert(id) } else { copy.recordIDs.remove(id) }
            ledger.saveSummaryVisibility(copy)
        })
    }
}

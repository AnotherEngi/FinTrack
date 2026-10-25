import SwiftUI
import Charts
import FinTrackCore

@MainActor
struct OverviewView: View {
    @Bindable var ledger: LedgerViewModel
    var openReview: () -> Void
    @State private var scope = DisplayScope()
    @State private var excludedTags: Set<String> = []
    @State private var excludedCategories: Set<String> = []
    @State private var excludeEvents = false
    @State private var selectedCategory: String?
    @State private var selectedMonth: String?
    @State private var seasonalMonth: Int?
    @State private var drilldown: SpendingBucket?

    private var records: [LedgerTransaction] {
        let selection = LedgerSelection(excludedTags: excludedTags, excludeExceptionalEvents: excludeEvents)
        return selection.records(in: scope.selection.records(in: ledger.records)).filter {
            !excludedCategories.contains($0.draft.categoryID ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    scopeControls
                    if let data = try? SpendingCharts(records: records, catalog: ledger.catalog) {
                        totals(data)
                        if data.months.isEmpty {
                            ContentUnavailableView("No spending in this view", systemImage: "chart.bar",
                                description: Text("Add transactions or change the dates and filters."))
                            Button("Open Transactions", action: openReview)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), alignment: .top)], alignment: .leading, spacing: 18) {
                                categoryCard(data)
                                monthCard(data)
                            }
                            seasonalCard(data)
                        }
                    } else { Text("These totals exceed the supported amount range.").foregroundStyle(.red) }
                    filters
                }.padding(18)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add Synthetic Chart Examples", systemImage: "testtube.2") { ledger.loadSpendingSamples() }
                }
            }
            .sheet(item: $drilldown, onDismiss: { selectedCategory = nil; selectedMonth = nil }) { bucket in
                NavigationStack {
                    RecordCollectionView(ledger: ledger, recordIDs: bucket.recordIDs, title: bucket.label)
                }
            }
            .refreshable { ledger.reload() }
        }
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisplayScopeControls(scope: $scope)
            Text("Posted spending, with refunds deducted. Pending charges stay separate. Saved history may be incomplete; missing months are unknown.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func totals(_ data: SpendingCharts) -> some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading) { Text("Spending").font(.caption); Text(data.totals.posted.decimalText).font(.title2.monospacedDigit()) }
            VStack(alignment: .leading) { Text("Pending").font(.caption); Text(data.totals.pending.decimalText).font(.title3.monospacedDigit()) }
            Spacer()
        }
    }

    private func categoryCard(_ data: SpendingCharts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where the money goes").font(.headline)
            Chart(data.categories) { bucket in
                BarMark(x: .value("Posted spending", Int(bucket.totals.posted.minorUnits)), y: .value("Category", bucket.label))
                    .foregroundStyle(.blue.gradient)
                    .accessibilityLabel(bucket.label).accessibilityValue(bucket.totals.posted.decimalText)
            }
            .chartXAxis { moneyAxis }
            .chartYSelection(value: $selectedCategory)
            .frame(height: max(200, CGFloat(data.categories.count) * 42))
            .onChange(of: selectedCategory) { _, label in
                drilldown = data.categories.first { $0.label == label }
            }
            ForEach(data.categories) { bucket in
                Button { drilldown = bucket } label: { LabeledContent(bucket.label, value: bucket.totals.posted.decimalText) }
            }
        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func monthCard(_ data: SpendingCharts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending over time").font(.headline)
            Chart(data.months) { month in
                BarMark(x: .value("Month", month.id), y: .value("Posted spending", Int(month.posted.minorUnits)))
                    .foregroundStyle(.teal.gradient)
                    .accessibilityLabel(month.id).accessibilityValue(month.posted.decimalText)
            }
            .chartYAxis { moneyAxis }
            .chartXSelection(value: $selectedMonth)
            .frame(height: 260)
            .onChange(of: selectedMonth) { _, id in
                if let month = data.months.first(where: { $0.id == id }) { showMonth(month) }
            }
            Text("Tap a bar to see its transactions. Only observed months are shown.").font(.caption).foregroundStyle(.secondary)
        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func seasonalCard(_ data: SpendingCharts) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time of year · compare years").font(.headline)
            if data.years.count < 2 {
                Text("One year is available so far. Additional years appear here when they are imported.").font(.caption).foregroundStyle(.secondary)
            }
            Chart(data.months) { month in
                LineMark(x: .value("Month", month.month), y: .value("Posted spending", Int(month.posted.minorUnits)),
                         series: .value("Observed segment", month.segment))
                    .foregroundStyle(by: .value("Year", String(month.year)))
                PointMark(x: .value("Month", month.month), y: .value("Posted spending", Int(month.posted.minorUnits)))
                    .foregroundStyle(by: .value("Year", String(month.year)))
                    .accessibilityLabel("\(month.year)-\(month.month)").accessibilityValue(month.posted.decimalText)
            }
            .chartXScale(domain: 1...12)
            .chartXAxis {
                AxisMarks(values: Array(1...12)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let month = value.as(Int.self), (1...12).contains(month) { Text(Self.monthNames[month - 1]) }
                    }
                }
            }
            .chartYAxis { moneyAxis }
            .chartXSelection(value: $seasonalMonth)
            .frame(height: 260)
            if let seasonalMonth, (1...12).contains(seasonalMonth) {
                let matching = data.months.filter { $0.month == seasonalMonth }
                ForEach(matching) { month in
                    Button { showMonth(month) } label: {
                        LabeledContent("\(Self.monthNames[seasonalMonth - 1]) \(month.year)", value: month.posted.decimalText)
                    }
                }
            }
            Text("Partial years and missing months are not equivalent coverage. Gaps are left open; no missing month is treated as zero.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var filters: some View {
        DisclosureGroup("Spending filters") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Exclude Exceptional Events", isOn: $excludeEvents)
                ForEach(ledger.catalog.categories, id: \.id) { category in
                    Toggle("Exclude " + category.label, isOn: Binding(get: { excludedCategories.contains(category.id) },
                        set: { if $0 { excludedCategories.insert(category.id) } else { excludedCategories.remove(category.id) } }))
                }
                ForEach(Array(Set(ledger.records.flatMap { $0.draft.tags })).sorted(), id: \.self) { tag in
                    Toggle("Exclude tag: " + tag, isOn: Binding(get: { excludedTags.contains(tag) },
                        set: { if $0 { excludedTags.insert(tag) } else { excludedTags.remove(tag) } }))
                }
                Button("Clear Filters") { excludedTags = []; excludedCategories = []; excludeEvents = false }
            }.padding(.top)
        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var moneyAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            AxisValueLabel {
                if let cents = value.as(Int.self) { Text(Money(minorUnits: Int64(cents)).decimalText) }
            }
        }
    }
    private func showMonth(_ month: SpendingMonth) {
        let ids = Set(month.recordIDs)
        guard let totals = try? SpendingTotals(records: records.filter({ ids.contains($0.id) })) else { return }
        drilldown = SpendingBucket(id: month.id, label: month.id, recordIDs: month.recordIDs,
            totals: totals)
    }
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

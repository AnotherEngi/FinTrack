import SwiftUI
import FinTrackCore

extension WorkspacePeriod {
    var label: String {
        switch self {
        case .oneMonth: "1 month"
        case .threeMonths: "3 months"
        case .sixMonths: "6 months"
        case .yearToDate: "YTD"
        case .pastYear: "Past year"
        case .custom: "Custom"
        }
    }
}

extension TransactionSortColumn {
    var label: String {
        switch self {
        case .activity: "Activity"
        case .date: "Date"
        case .amount: "Amount"
        case .merchant: "Merchant"
        case .source: "Source"
        case .category: "Category"
        case .tags: "Tags"
        case .review: "Review"
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .activity: 44
        case .date: 80
        case .amount: 108
        case .merchant: 144
        case .source: 112
        case .category: 144
        case .tags: 128
        case .review: 164
        }
    }

    static var minimumTableWidth: CGFloat {
        var total: CGFloat = 0
        for column in allCases { total += column.minimumWidth }
        return total
    }

    func width(in tableWidth: CGFloat) -> CGFloat {
        let extra = max(0, tableWidth - Self.minimumTableWidth)
        switch self {
        case .merchant: return minimumWidth + extra * 0.45
        case .category: return minimumWidth + extra * 0.35
        case .tags: return minimumWidth + extra * 0.20
        default: return minimumWidth
        }
    }

    var alignment: Alignment {
        self == .activity ? .center : self == .amount ? .trailing : .leading
    }
}

/// Shared cell geometry keeps header and row edges aligned. Insets are inside
/// each column's width, including a clear gutter after right-aligned amounts.
@MainActor
private struct TransactionTableCell<Content: View>: View {
    let column: TransactionSortColumn
    let tableWidth: CGFloat
    let content: Content

    init(_ column: TransactionSortColumn, tableWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.column = column
        self.tableWidth = tableWidth
        self.content = content()
    }

    var body: some View {
        content
            .padding(.leading, column == .activity ? 0 : 8)
            .padding(.trailing, column == .activity ? 0 : column == .amount ? 12 : 8)
            .frame(width: column.width(in: tableWidth), alignment: column.alignment)
    }
}

@MainActor
struct TransactionListView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var editor: EditorDraft?
    @State private var startDiscussion = false
    @State private var search = ""
    @State private var period = WorkspacePeriod.oneMonth
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: .now)!
    @State private var through = Date.now
    @State private var amalgamate = false
    @State private var sort = TransactionTableSort()
    @State private var showExport = false
    @State private var pendingRequest: ReviewRequest?

    private var range: TransactionDateRange? {
        guard let today = try? TransactionDate(EditorDraft.dateText(.now)) else { return nil }
        return try? period.range(through: today,
            customFrom: TransactionDate(EditorDraft.dateText(from)),
            customThrough: TransactionDate(EditorDraft.dateText(through)))
    }

    private var visibleRecords: [LedgerTransaction] {
        guard let range else { return [] }
        let labels = Dictionary(uniqueKeysWithValues: ledger.catalog.categories.map { ($0.id, $0.label) })
        let records = LedgerSelection(from: range.from, through: range.through,
            search: search, categoryLabels: labels).records(in: ledger.records)
        return sort.records(records, catalog: ledger.catalog, changedIDs: ledger.sessionChanges.recordIDs)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
                if period == .custom {
                    HStack {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("Through", selection: $through, displayedComponents: .date)
                    }.padding(.horizontal, 16).padding(.bottom, 10)
                }
                if range == nil {
                    Text("Choose a start date on or before the end date.").foregroundStyle(.red)
                }
                if ledger.records.isEmpty {
                    ContentUnavailableView {
                        Label("No saved transactions", systemImage: "tablecells")
                    } description: {
                        Text("Add a transaction or load invented table examples.")
                    } actions: { Button("Load Synthetic Table Examples") { ledger.loadTableSamples() } }
                } else if visibleRecords.isEmpty {
                    ContentUnavailableView {
                        Label("No matching transactions", systemImage: "magnifyingglass")
                    } description: {
                        Text("Try another search or date range. Existing records are preserved.")
                    } actions: { Button("Add Current Synthetic Table Examples") { ledger.loadTableSamples() } }
                } else {
                    GeometryReader { geometry in
                        let width = max(TransactionSortColumn.minimumTableWidth, geometry.size.width - 24)
                        ScrollView([.horizontal, .vertical]) {
                            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                                if amalgamate {
                                    tableSection(nil, records: visibleRecords, width: width)
                                } else {
                                    tableSection("Not approved", records: visibleRecords.filter { $0.approval != .confirmed }, width: width)
                                    tableSection("Approved", records: visibleRecords.filter { $0.approval == .confirmed }, width: width)
                                }
                            }.frame(width: width).padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showExport = true } label: {
                        Label("Review with ChatGPT", systemImage: "square.and.arrow.up").labelStyle(.titleAndIcon)
                    }.accessibilityLabel("Export shown transactions for ChatGPT").help("Export shown transactions for ChatGPT")
                        .disabled(visibleRecords.isEmpty)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { startDiscussion = false; editor = .new() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add transaction").help("Add transaction")
                }
                if !ledger.drafts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ForEach(ledger.drafts) { draft in
                                Button(draft.input.payee.isEmpty ? "New transaction draft" : draft.input.payee) {
                                    startDiscussion = false; editor = draft
                                }
                            }
                        } label: { Image(systemName: "doc.badge.ellipsis") }
                            .accessibilityLabel("Resume unsaved drafts").help("Resume unsaved drafts")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Add Synthetic Table Examples", systemImage: "testtube.2") { ledger.loadTableSamples() }
                }
            }
            .sheet(item: $editor, onDismiss: { ledger.reload() }) { draft in
                // Table details stay on the selected record after a review action.
                TransactionEditorView(ledger: ledger, draft: draft, startDiscussion: startDiscussion) { _ in }
                    .id(draft.id)
            }
            .sheet(isPresented: $showExport) {
                ReviewExportView(ledger: ledger, showsDone: true)
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                searchField.frame(width: 220)
                dateButtons
                Spacer(minLength: 0)
                amalgamateSwitch
            }
            VStack(spacing: 10) {
                searchField
                HStack(spacing: 12) {
                    ScrollView(.horizontal, showsIndicators: false) { dateButtons }.frame(height: 44)
                    amalgamateSwitch
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search transactions", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("Clear search").foregroundStyle(.secondary)
            }
        }.padding(10).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var dateButtons: some View {
        HStack(spacing: 4) {
            ForEach(WorkspacePeriod.allCases, id: \.self) { value in
                Button {
                    if value == .custom, let range {
                        from = Self.calendarDate(range.from)
                        through = Self.calendarDate(range.through)
                    }
                    period = value
                } label: {
                    Text(value.label).font(.caption).fixedSize().padding(.horizontal, 10).frame(minHeight: 44)
                        .background(period == value ? Color.accentColor.opacity(0.14) : Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).foregroundStyle(period == value ? Color.accentColor : Color.primary)
                    .accessibilityAddTraits(period == value ? [.isSelected] : [])
            }
        }
    }

    private var amalgamateSwitch: some View {
        Toggle("Amalgamate", isOn: $amalgamate).toggleStyle(.switch).fixedSize()
            .help("Combine approved and non-approved transactions")
    }

    private static func calendarDate(_ value: TransactionDate) -> Date {
        let parts = value.iso8601.split(separator: "-").map { Int($0)! }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    private func tableSection(_ title: String?, records: [LedgerTransaction], width: CGFloat) -> some View {
        Section {
            if records.isEmpty { Text("No matching transactions.").foregroundStyle(.secondary).padding() }
            ForEach(records) { record in
                TransactionTableRow(record: record, catalog: ledger.catalog, width: width,
                    changed: ledger.sessionChanges.recordIDs.contains(record.id),
                    hasDraft: ledger.drafts.contains { $0.id == record.id },
                    onEdit: { discuss in startDiscussion = discuss; editor = ledger.editor(for: record) },
                    onReview: { action in perform(action, record: record) })
                Divider()
            }
        } header: {
            VStack(alignment: .leading, spacing: 0) {
                if let title { Text(title).font(.subheadline.weight(.medium)).padding(.vertical, 10) }
                HStack(spacing: 0) {
                    ForEach(TransactionSortColumn.allCases, id: \.self) { column in
                        Button {
                            sort = TransactionTableSort(column: column,
                                ascending: sort.column == column ? !sort.ascending : column != .date && column != .amount)
                        } label: {
                            TransactionTableCell(column, tableWidth: width) {
                                HStack(spacing: 3) {
                                    if column == .activity { Image(systemName: "circle.dotted") }
                                    else {
                                        Text(column.label)
                                        Image(systemName: sort.column == column
                                            ? sort.ascending ? "arrow.up" : "arrow.down" : "arrow.up.arrow.down")
                                            .imageScale(.small)
                                    }
                                }.font(.caption).foregroundStyle(sort.column == column ? Color.accentColor : Color.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: column.alignment)
                            }
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Sort by \(column.label)")
                            .accessibilityValue(sort.column == column ? sort.ascending ? "Ascending" : "Descending" : "Not selected")
                            .help("Sort by \(column.label)")
                    }
                }
            }.frame(width: width, alignment: .leading).background(Color(.systemGroupedBackground))
        }
    }

    private func perform(_ action: ReviewAction, record: LedgerTransaction) {
        let request: ReviewRequest
        if let pendingRequest, pendingRequest.transactionID == record.id,
           pendingRequest.action == action, pendingRequest.expectedRevision == record.revision {
            request = pendingRequest
        } else {
            request = ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: action)
            pendingRequest = request
        }
        do { _ = try ledger.perform(request); pendingRequest = nil }
        catch { ledger.message = error.localizedDescription }
    }
}

@MainActor
private struct TransactionTableRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let record: LedgerTransaction
    let catalog: ReviewCatalog
    let width: CGFloat
    let changed: Bool
    let hasDraft: Bool
    let onEdit: (Bool) -> Void
    let onReview: (ReviewAction) -> Void

    private var approvalAction: ReviewAction { record.approval == .confirmed ? .reopen : .approve }
    private var approvalReason: String? {
        hasDraft ? "Finish or discard this transaction's unsaved draft first."
            : record.reviewBlockReason(for: approvalAction, catalog: catalog)
    }
    private var activityLabel: String {
        var labels: [String] = []
        if changed { labels.append("Changed this session") }
        if hasDraft { labels.append("Unsaved draft") }
        if record.discussionRequested {
            labels.append(record.discussionProgress == .reviewingInChatGPT
                ? "Reviewing in ChatGPT, marked by you" : "Discussion waiting for export")
        }
        return labels.joined(separator: "; ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            TransactionTableCell(.activity, tableWidth: width) { activity }
            TransactionTableCell(.date, tableWidth: width) { date }
            TransactionTableCell(.amount, tableWidth: width) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.draft.amount.decimalText).monospacedDigit().font(.subheadline)
                    if record.draft.postingStatus == .pending { Text("Pending").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            TransactionTableCell(.merchant, tableWidth: width) {
                Text(record.draft.payee).font(.subheadline).foregroundStyle(.primary).lineLimit(3)
                    .help(record.draft.payee)
            }
            TransactionTableCell(.source, tableWidth: width) {
                Text(record.draft.source?.label ?? "—").font(.subheadline).lineLimit(3)
                    .help(record.draft.source?.label ?? "Source unavailable on this record")
                    .accessibilityLabel(record.draft.source?.label ?? "Source unavailable")
            }
            TransactionTableCell(.category, tableWidth: width) {
                if let categoryID = record.draft.categoryID {
                    pill(catalog.category(id: categoryID)?.label ?? categoryID,
                        origin: record.classificationProvenance.category)
                } else { Text("—").foregroundStyle(.secondary).accessibilityLabel("Category unavailable") }
            }
            TransactionTableCell(.tags, tableWidth: width) {
                VStack(alignment: .leading, spacing: 4) {
                    if record.draft.tags.isEmpty { Text("—").foregroundStyle(.secondary) }
                    ForEach(record.draft.tags, id: \.self) { tag in
                        pill(tag, origin: record.classificationProvenance.tags[tag] ?? .unknown)
                    }
                }
            }
            TransactionTableCell(.review, tableWidth: width) { actions }
        }
        .padding(.vertical, 12).frame(width: width, alignment: .leading).frame(minHeight: 68)
        .background(Color(.secondarySystemGroupedBackground))
        .accessibilityElement(children: .contain)
    }

    private var date: some View {
        let parts = record.draft.date.iso8601.split(separator: "-").map { Int($0)! }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return VStack(alignment: .leading, spacing: 2) {
            Text(formatter.string(from: date)).font(.caption)
            if record.draft.date.iso8601.prefix(4) != EditorDraft.dateText(.now).prefix(4) {
                Text(String(parts[0])).font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityLabel(record.draft.date.iso8601)
    }

    private var activity: some View {
        Group {
            if activityLabel.isEmpty { Text("—").foregroundStyle(.secondary) }
            else {
                Button { onEdit(false) } label: {
                    HStack(spacing: 2) {
                        if changed { Image(systemName: "pencil").foregroundStyle(statusColor(.user)) }
                        if hasDraft { Image(systemName: "doc.badge.ellipsis").foregroundStyle(.secondary) }
                        if record.discussionRequested {
                            Image(systemName: record.discussionProgress == .reviewingInChatGPT ? "ellipsis.bubble" : "bubble.left")
                                .foregroundStyle(statusColor(record.discussionProgress == .reviewingInChatGPT ? .user : .assistant))
                        }
                    }.font(.system(size: 11)).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(activityLabel).help(activityLabel)
            }
        }
    }

    private func pill(_ text: String, origin: ValueOrigin) -> some View {
        let approved = record.approval == .confirmed
        let color = statusColor(origin, approved: approved)
        let known = approved || origin != .unknown
        let status = approved ? "Approved" : origin == .assistant ? "AI suggestion, not approved"
            : origin == .user ? "Your edit, not approved" : "Origin unknown"
        return Text(text).font(.caption).lineLimit(3).padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(known ? color : .primary)
            .background(known ? color.opacity(0.14) : Color.clear, in: Capsule())
            .padding(.horizontal, 4)
            .accessibilityLabel(text + ", " + status).help(text + " — " + status)
    }

    private func statusColor(_ origin: ValueOrigin, approved: Bool = false) -> Color {
        let dark = colorScheme == .dark
        if approved { return dark ? Color(red: 0.62, green: 0.88, blue: 0.75) : Color(red: 0.14, green: 0.42, blue: 0.31) }
        switch origin {
        case .assistant: return dark ? Color(red: 1, green: 0.81, blue: 0.58) : Color(red: 0.60, green: 0.33, blue: 0.08)
        case .user: return dark ? Color(red: 0.63, green: 0.78, blue: 1) : Color(red: 0.08, green: 0.35, blue: 0.68)
        case .unknown: return .secondary
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            actionButton(record.approval == .notApplicable ? "minus.circle"
                : record.approval == .confirmed ? "arrow.uturn.backward" : "checkmark",
                label: approvalAction.label, help: approvalReason ?? approvalAction.label,
                disabled: approvalReason != nil, color: statusColor(.unknown, approved: true)) { onReview(approvalAction) }
            actionButton("bubble.left.and.bubble.right", label: "Discuss", help: "Discuss",
                disabled: record.draft.treatment.excludedFromReview) { onEdit(true) }
            actionButton("square.and.pencil", label: "Edit", help: "Edit") { onEdit(false) }
        }
    }

    private func actionButton(_ icon: String, label: String, help: String,
                              disabled: Bool = false, color: Color = .primary,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(color).frame(width: 44, height: 44)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
            .accessibilityLabel(label + " " + record.draft.payee).help(help)
    }
}

import SwiftUI
import FinTrackCore

@MainActor
struct TransactionListView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var editor: EditorDraft?
    @State private var search = ""
    @State private var period = HistoryPeriod.all
    @State private var reviewFilter = ReviewFilter.all
    @State private var from = Calendar.current.date(byAdding: .day, value: -56, to: .now)!
    @State private var through = Date.now

    private enum HistoryPeriod: String, CaseIterable {
        case all = "All history", eightWeeks = "Last 8 weeks", custom = "Date range"
    }

    private enum ReviewFilter: String, CaseIterable {
        case all = "All transactions", unreviewed = "Unreviewed", discussion = "Needs discussion"
        case approved = "Approved", pending = "Pending", excluded = "Outside spending review"
    }

    private var visibleRecords: [LedgerTransaction] {
        let end = EditorDraft.dateText(through)
        let start = EditorDraft.dateText(from)
        let eightWeeksAgo = EditorDraft.dateText(
            Calendar.current.date(byAdding: .day, value: -56, to: .now)!)
        return ledger.records.filter { record in
            let date = record.draft.date.iso8601
            let inRange = switch period {
            case .all: true
            case .eightWeeks: date >= eightWeeksAgo && date <= EditorDraft.dateText(.now)
            case .custom: date >= start && date <= end
            }
            let matchesReview = switch reviewFilter {
            case .all: true
            case .unreviewed: record.approval == .unreviewed
            case .discussion: record.discussionRequested
            case .approved: record.approval == .confirmed
            case .pending: record.draft.postingStatus == .pending
            case .excluded: record.approval == .notApplicable
            }
            return inRange && matchesReview && (search.isEmpty
                || record.draft.payee.localizedCaseInsensitiveContains(search)
                || record.draft.notes.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let failure = ledger.startupFailure {
                    ContentUnavailableView("Unable to Open FinTrack", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("\(failure)\nYour existing files have been preserved."))
                } else {
                    history
                }
            }
            .navigationTitle("FinTrack")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Transaction", systemImage: "plus") { editor = .new() }
                        .disabled(ledger.startupFailure != nil)
                }
            }
            .sheet(item: $editor, onDismiss: { ledger.reload() }) { draft in
                TransactionEditorView(ledger: ledger, draft: draft) { id in
                    editor = ledger.nextReviewDraft(after: id, visibleIDs: visibleRecords.map(\.id))
                }
                .id(draft.id)
            }
            .alert("FinTrack", isPresented: Binding(
                get: { ledger.message != nil }, set: { if !$0 { ledger.message = nil } })) {
                    Button("OK") { ledger.message = nil }
                } message: { Text(ledger.message ?? "") }
        }
    }

    private var history: some View {
        List {
            Section {
                Label("Synthetic development data only", systemImage: "testtube.2")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("History", selection: $period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Review filter", selection: $reviewFilter) {
                    ForEach(ReviewFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                if period == .custom {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("Through", selection: $through, displayedComponents: .date)
                    if EditorDraft.dateText(from) > EditorDraft.dateText(through) {
                        Text("Choose a start date before the end date.").foregroundStyle(.red)
                    }
                }
            }
            if !ledger.records.isEmpty {
                Section("Shown Spending") {
                    if let totals = try? SpendingTotals(records: visibleRecords) {
                        LabeledContent("Posted spending", value: totals.posted.decimalText + " USD")
                        LabeledContent("Pending spending", value: totals.pending.decimalText + " USD")
                    } else {
                        Text("Totals are unavailable for these amounts.").foregroundStyle(.secondary)
                    }
                    Text("Includes classified posted/pending purchases and refunds in the current view. Other or unresolved treatments and posting states are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !ledger.drafts.isEmpty {
                Section("Unsaved Drafts") {
                    ForEach(ledger.drafts) { draft in
                        Button { editor = draft } label: {
                            Label(draft.input.payee.isEmpty ? "New transaction draft" : draft.input.payee,
                                  systemImage: "square.and.pencil")
                        }
                    }
                }
            }
            if ledger.records.isEmpty {
                Section {
                    Text("Add a transaction or load eight weeks of invented examples.")
                    Button("Load Synthetic Examples") { ledger.loadSamples() }
                }
            } else if visibleRecords.isEmpty {
                Text("No transactions match this range or search.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(Set(visibleRecords.map { $0.draft.date.iso8601 })).sorted(by: >), id: \.self) { date in
                    Section(date) {
                        ForEach(visibleRecords.filter { $0.draft.date.iso8601 == date }) { record in
                            Button { editor = ledger.editor(for: record) } label: {
                                HStack {
                                    Image(systemName: record.discussionRequested ? "bubble.left.and.bubble.right"
                                        : record.approval == .confirmed ? "checkmark.circle.fill"
                                        : record.approval == .notApplicable ? "minus.circle" : "circle")
                                        .accessibilityLabel(record.discussionRequested ? "Needs discussion" : record.approval.label)
                                    VStack(alignment: .leading) {
                                        Text(record.draft.payee).foregroundStyle(.primary)
                                        Text(record.draft.treatment.label + " · " + record.draft.postingStatus.label
                                             + " · " + record.approval.label)
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let category = ledger.catalog.category(id: record.draft.categoryID) {
                                            Text(category.label).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(record.draft.amount.decimalText + " USD")
                                        .monospacedDigit().foregroundStyle(.primary)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search payees and notes")
        .refreshable { ledger.reload() }
    }
}

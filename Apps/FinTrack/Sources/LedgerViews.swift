import SwiftUI
import FinTrackCore

@MainActor
struct FinTrackRootView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var tab = WorkspaceTab.review

    private enum WorkspaceTab: Hashable { case overview, review, questions, history, export }

    var body: some View {
        Group {
            if let failure = ledger.startupFailure {
                ContentUnavailableView("Unable to Open FinTrack", systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("\(failure)\nYour existing files have been preserved."))
            } else {
                TabView(selection: $tab) {
                    OverviewView(ledger: ledger) { tab = .review }
                        .tabItem { Label("Overview", systemImage: "chart.bar") }.tag(WorkspaceTab.overview)
                    TransactionListView(ledger: ledger)
                        .tabItem { Label("Transactions", systemImage: "tablecells") }.tag(WorkspaceTab.review)
                    QuestionsView(ledger: ledger)
                        .tabItem { Label("Questions", systemImage: "bubble.left.and.bubble.right") }
                        .badge(ledger.records.filter { LedgerReviewFilter.questions.matches($0) }.count)
                        .tag(WorkspaceTab.questions)
                    ReviewHistoryView(ledger: ledger)
                        .tabItem { Label("Review history", systemImage: "clock.arrow.circlepath") }.tag(WorkspaceTab.history)
                    ReviewExportView(ledger: ledger)
                        .tabItem { Label("Review & backup", systemImage: "arrow.triangle.2.circlepath") }.tag(WorkspaceTab.export)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if ledger.startupFailure == nil && ledger.backup?.isCurrent != true {
                Button { tab = .export } label: {
                    Label(ledger.backup?.status ?? "Automatic iCloud backup needs attention.", systemImage: "icloud.and.arrow.up")
                        .font(.caption).frame(maxWidth: .infinity).padding(6)
                }.background(.thinMaterial)
            }
        }
        .task {
            while !Task.isCancelled {
                await ledger.backupNow()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .alert("FinTrack", isPresented: Binding(
            get: { ledger.message != nil }, set: { if !$0 { ledger.message = nil } })) {
                Button("OK") { ledger.message = nil }
            } message: { Text(ledger.message ?? "") }
    }
}

enum DisplayPeriod: String, CaseIterable {
    case all = "All history", eightWeeks = "Last 8 weeks", custom = "Date range"
}

struct DisplayScope {
    var period = DisplayPeriod.all
    var from = Calendar.current.date(byAdding: .day, value: -56, to: .now)!
    var through = Date.now

    var isValid: Bool { period != .custom || EditorDraft.dateText(from) <= EditorDraft.dateText(through) }

    var selection: LedgerSelection {
        switch period {
        case .all: LedgerSelection()
        case .eightWeeks: LedgerSelection(
            from: try? TransactionDate(EditorDraft.dateText(Calendar.current.date(byAdding: .day, value: -56, to: .now)!)),
            through: try? TransactionDate(EditorDraft.dateText(.now)))
        case .custom: LedgerSelection(from: try? TransactionDate(EditorDraft.dateText(from)),
            through: try? TransactionDate(EditorDraft.dateText(through)))
        }
    }

    func contains(_ date: String) -> Bool {
        let bounds = selection
        return isValid && (bounds.from.map { date >= $0.iso8601 } ?? true)
            && (bounds.through.map { date <= $0.iso8601 } ?? true)
    }
}

struct DisplayScopeControls: View {
    @Binding var scope: DisplayScope

    var body: some View {
        Picker("Period", selection: $scope.period) {
            ForEach(DisplayPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        if scope.period == .custom {
            DatePicker("From", selection: $scope.from, displayedComponents: .date)
            DatePicker("Through", selection: $scope.through, displayedComponents: .date)
            if !scope.isValid { Text("Choose a start date before the end date.").foregroundStyle(.red) }
        }
    }
}

struct LedgerRecordRow: View {
    let record: LedgerTransaction
    let catalog: ReviewCatalog

    var body: some View {
        HStack {
            Image(systemName: record.discussionRequested ? "bubble.left.and.bubble.right"
                : record.approval == .confirmed ? "checkmark.circle.fill"
                : record.approval == .notApplicable ? "minus.circle" : "circle")
                .accessibilityLabel(record.discussionRequested ? "Needs discussion" : record.approval.label)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.draft.payee).foregroundStyle(.primary)
                Text(record.draft.date.iso8601 + " · " + record.draft.treatment.label
                    + " · " + record.draft.postingStatus.label + " · " + record.approval.label)
                    .font(.caption).foregroundStyle(.secondary)
                if let category = catalog.category(id: record.draft.categoryID) {
                    Text(category.label).font(.caption).foregroundStyle(.secondary)
                }
                if !record.draft.tags.isEmpty {
                    Text(record.draft.tags.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                }
                if record.draft.exceptionalEvent {
                    Label("Exceptional Event", systemImage: "flag").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(record.draft.amount.decimalText + " USD").monospacedDigit().foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct RecordCollectionView: View {
    @Bindable var ledger: LedgerViewModel
    let recordIDs: [UUID]
    let title: String
    @State private var editor: EditorDraft?

    private var records: [LedgerTransaction] {
        LedgerSelection().records(in: ledger.records.filter { recordIDs.contains($0.id) })
    }

    var body: some View {
        List {
            Text("Saved transactions in this selection.").font(.caption).foregroundStyle(.secondary)
            ForEach(records) { record in
                Button { editor = ledger.editor(for: record) } label: {
                    LedgerRecordRow(record: record, catalog: ledger.catalog)
                }
            }
        }
        .navigationTitle(title)
        .sheet(item: $editor, onDismiss: { ledger.reload() }) { draft in
            TransactionEditorView(ledger: ledger, draft: draft) { id in
                editor = ledger.nextReviewDraft(after: id, visibleIDs: records.map(\.id))
            }.id(draft.id)
        }
    }
}

@MainActor
struct OverviewView: View {
    @Bindable var ledger: LedgerViewModel
    var openReview: () -> Void
    @State private var scope = DisplayScope()
    @State private var excludedTags: Set<String> = []
    @State private var excludeEvents = false

    private var baseRecords: [LedgerTransaction] { scope.selection.records(in: ledger.records) }
    private var records: [LedgerTransaction] {
        LedgerSelection(excludedTags: excludedTags, excludeExceptionalEvents: excludeEvents).records(in: baseRecords)
    }
    private var tags: [String] { Array(Set(ledger.records.flatMap { $0.draft.tags })).sorted() }

    var body: some View {
        NavigationStack {
            List {
                Section("Stored records") {
                    Text("Synthetic development data only").font(.callout).foregroundStyle(.secondary)
                    DisplayScopeControls(scope: $scope)
                    Text("Totals cover saved records in this selection. Missing accounts or dates are unknown; this is not complete household coverage.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let first = records.last, let last = records.first {
                        LabeledContent("Observed dates", value: first.draft.date.iso8601 + " – " + last.draft.date.iso8601)
                    }
                }
                if ledger.records.isEmpty {
                    Section {
                        Text("Add a transaction or load the invented examples in Transactions.")
                        Button("Open Transactions", action: openReview)
                    }
                } else if records.isEmpty {
                    Text("No saved transactions match this selection.").foregroundStyle(.secondary)
                } else {
                    report
                }
                Section("Display exclusions") {
                    Toggle("Exclude Exceptional Events", isOn: $excludeEvents)
                    ForEach(tags, id: \.self) { tag in
                        Toggle("Exclude tag: " + tag, isOn: Binding(
                            get: { excludedTags.contains(tag) },
                            set: { if $0 { excludedTags.insert(tag) } else { excludedTags.remove(tag) } }))
                    }
                    Text("\(baseRecords.count - records.count) records hidden. Overlapping exclusions count once. These controls do not edit the ledger.")
                        .font(.caption).foregroundStyle(.secondary)
                    if excludeEvents || !excludedTags.isEmpty {
                        Button("Clear Display Exclusions") { excludeEvents = false; excludedTags = [] }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { ledger.reload() }
        }
    }

    @ViewBuilder private var report: some View {
        if let summary = try? LedgerOverview(records: records, catalog: ledger.catalog) {
            Section("Selected spending") {
                LabeledContent("Posted purchases and refunds", value: summary.totals.posted.decimalText + " USD")
                LabeledContent("Pending, separate", value: summary.totals.pending.decimalText + " USD")
                Text("\(summary.recordCount) saved records; \(summary.omittedFromSpendingCount) income, payment, transfer, credit, or unresolved records omitted from spending.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Review progress") {
                countLink("Unreviewed", count: summary.unreviewedCount, filter: .unreviewed)
                countLink("Approved", count: summary.approvedCount, filter: .approved)
                countLink("Needs discussion", count: summary.discussionCount, filter: .discussion)
                countLink("Questions or discussion", count: summary.questionsCount, filter: .questions)
            }
            Section("By category") { ForEach(summary.categories) { bucket in bucketLink(bucket) } }
            Section("By month") {
                ForEach(summary.months) { bucket in bucketLink(bucket) }
                Text("Only months with stored purchases or refunds are shown. Missing months are not zero-filled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Totals are unavailable because these amounts exceed the supported total range.").foregroundStyle(.secondary)
        }
    }

    private func countLink(_ title: String, count: Int, filter: LedgerReviewFilter) -> some View {
        NavigationLink {
            RecordCollectionView(ledger: ledger, recordIDs: records.filter { filter.matches($0) }.map(\.id), title: title)
        } label: { LabeledContent(title, value: String(count)) }
    }

    private func bucketLink(_ bucket: SpendingBucket) -> some View {
        NavigationLink {
            RecordCollectionView(ledger: ledger, recordIDs: bucket.recordIDs, title: bucket.label)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(bucket.label, value: bucket.totals.posted.decimalText + " USD")
                Text("\(bucket.recordIDs.count) records · pending \(bucket.totals.pending.decimalText) USD")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct QuestionsView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var scope = DisplayScope()
    @State private var search = ""
    @State private var discussionOnly = false
    @State private var editor: EditorDraft?

    private var records: [LedgerTransaction] {
        var selection = scope.selection
        selection.search = search
        selection.reviewFilter = discussionOnly ? .discussion : .questions
        return selection.records(in: ledger.records)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DisplayScopeControls(scope: $scope)
                    Toggle("Discussion requests only", isOn: $discussionOnly)
                    Text("Unanswered assistant questions and your discussion requests. Answers remain in the ledger; Discuss does not contact ChatGPT.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("\(records.count) transactions") {
                    if records.isEmpty { Text("No outstanding questions match this selection.").foregroundStyle(.secondary) }
                    ForEach(records) { record in
                        Button { editor = ledger.editor(for: record) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                LedgerRecordRow(record: record, catalog: ledger.catalog)
                                if !record.assistantContext.question.isEmpty {
                                    Text("Assistant question: " + record.assistantContext.question).foregroundStyle(.primary)
                                }
                                if !record.draft.answer.isEmpty {
                                    Text("Your answer: " + record.draft.answer).foregroundStyle(.secondary)
                                }
                                if record.discussionRequested {
                                    Label("Discussion requested", systemImage: "bubble.left").font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search payees, notes, answers, and tags")
            .refreshable { ledger.reload() }
            .sheet(item: $editor, onDismiss: { ledger.reload() }) { draft in
                TransactionEditorView(ledger: ledger, draft: draft) { id in
                    editor = ledger.nextReviewDraft(after: id, visibleIDs: records.map(\.id))
                }.id(draft.id)
            }
        }
    }
}

@MainActor
struct ReviewHistoryView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var scope = DisplayScope()
    @State private var search = ""

    private var entries: [LedgerHistoryEntry] {
        LedgerHistoryEntry.entries(in: ledger.records).filter {
            scope.contains(EditorDraft.dateText($0.decision.createdAt))
                && (search.isEmpty || $0.currentPayee.localizedCaseInsensitiveContains(search)
                    || $0.decision.request.action.label.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Decision dates") {
                    DisplayScopeControls(scope: $scope)
                    Text("Explicit local Approve, Discuss, and Reopen actions. Skip creates no decision. Names show the current payee; these are not snapshots of earlier field values or ChatGPT processing receipts.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("\(entries.count) decisions") {
                    if entries.isEmpty { Text("No saved review decisions match this selection.").foregroundStyle(.secondary) }
                    ForEach(entries) { entry in
                        NavigationLink {
                            RecordCollectionView(ledger: ledger, recordIDs: [entry.transactionID], title: "Current transaction")
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.decision.request.action.label + " · " + entry.currentPayee)
                                Text(entry.decision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Revision \(entry.decision.request.expectedRevision) → \(entry.decision.appliedRevision)")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Action ID: " + entry.decision.id.uuidString).font(.caption2).foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search payees and review actions")
            .refreshable { ledger.reload() }
        }
    }
}

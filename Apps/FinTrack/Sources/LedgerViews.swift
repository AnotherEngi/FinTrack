import SwiftUI
import FinTrackCore

@MainActor
struct FinTrackRootView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var tab = WorkspaceTab.review
    @State private var showBackup = false

    private enum WorkspaceTab: Hashable { case overview, review, questions, history, export, visibility }

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
                    VisibilityView(ledger: ledger)
                        .tabItem { Label("Visibility", systemImage: "eye.slash") }.tag(WorkspaceTab.visibility)
                    QuestionsView(ledger: ledger)
                        .tabItem { Label("Discussions", systemImage: "bubble.left.and.bubble.right") }
                        .badge(ledger.discussions.values.filter { !$0.isResolved || $0.status == .draft }.count)
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
                Button { showBackup = true } label: {
                    Label(ledger.backup?.status ?? "Automatic iCloud backup needs attention.", systemImage: "icloud.and.arrow.up")
                        .font(.caption).frame(maxWidth: .infinity).padding(6)
                }.background(.thinMaterial)
            }
        }
        .sheet(isPresented: $showBackup) { BackupSettingsView(ledger: ledger) }
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
    case all = "All history", oneMonth = "1 month", threeMonths = "3 months", sixMonths = "6 months"
    case yearToDate = "YTD", pastYear = "Past year", eightWeeks = "Last 8 weeks", custom = "Date range"
}

struct DisplayScope {
    var period = DisplayPeriod.all
    var from = Calendar.current.date(byAdding: .day, value: -56, to: .now)!
    var through = Date.now

    var isValid: Bool { period != .custom || EditorDraft.dateText(from) <= EditorDraft.dateText(through) }

    var selection: LedgerSelection {
        switch period {
        case .all: LedgerSelection()
        case .oneMonth: preset(.oneMonth)
        case .threeMonths: preset(.threeMonths)
        case .sixMonths: preset(.sixMonths)
        case .yearToDate: preset(.yearToDate)
        case .pastYear: preset(.pastYear)
        case .eightWeeks: LedgerSelection(
            from: try? TransactionDate(EditorDraft.dateText(Calendar.current.date(byAdding: .day, value: -56, to: .now)!)),
            through: try? TransactionDate(EditorDraft.dateText(.now)))
        case .custom: LedgerSelection(from: try? TransactionDate(EditorDraft.dateText(from)),
            through: try? TransactionDate(EditorDraft.dateText(through)))
        }
    }

    private func preset(_ period: WorkspacePeriod) -> LedgerSelection {
        guard let today = try? TransactionDate(EditorDraft.dateText(.now)), let range = try? period.range(through: today) else {
            return LedgerSelection(from: try? TransactionDate("9999-12-31"), through: try? TransactionDate("0001-01-01"))
        }
        return LedgerSelection(from: range.from, through: range.through)
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

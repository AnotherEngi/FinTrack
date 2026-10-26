import SwiftUI
import Observation
import FinTrackCore

@MainActor
struct FinancialSettingsView: View {
    var ledger: LedgerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var context: FinancialContext
    @State private var categories: [ReviewCategory]
    @State private var failure: String?
    @State private var inputState = FinancialInputState()
    init(ledger: LedgerViewModel) {
        self.ledger = ledger
        _context = State(initialValue: FinancialContext(workspace: ledger.workspace))
        _categories = State(initialValue: ledger.catalog.categories)
    }
    var body: some View {
        NavigationStack {
            Form {
                categorySection
                accountSection
                programSection
                reimbursementSection
                reportingSection
                if let failure { Section { Text(failure).foregroundStyle(.red).textSelection(.enabled) } }
            }
            .navigationTitle("Financial Settings").navigationBarTitleDisplayMode(.inline)
            .environment(inputState)
            .onChange(of: financialObjectIDs) { _, ids in inputState.prune(keeping: ids) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try ledger.saveFinancialSettings(context, categories: categories); dismiss() }
                        catch { failure = error.localizedDescription }
                    }.disabled(!inputState.errors.isEmpty)
                }
            }
        }
    }
    private var categorySection: some View {
                Section("Categories and subcategories") {
                    ForEach($categories) { $category in
                        DisclosureGroup(category.label) {
                            Text("Stable ID: " + category.id).font(.caption).textSelection(.enabled)
                            TextField("Display label", text: $category.label)
                            TextField("Stored source label", text: $category.storedLabel)
                            SourceValueField(title: "Definition", value: $category.definition)
                            Toggle("Unresolved", isOn: $category.unresolved)
                            Toggle("Excluded", isOn: $category.excluded)
                            ForEach($category.subcategories) { $sub in
                                DisclosureGroup(sub.label) {
                                    TextField("Display label", text: $sub.label)
                                    TextField("Stored source label", text: $sub.storedLabel)
                                    SourceValueField(title: "Definition", value: $sub.definition)
                                    Toggle("Unresolved", isOn: $sub.unresolved)
                                    Toggle("Excluded", isOn: $sub.excluded)
                                    Button("Remove Subcategory", role: .destructive) { category.subcategories.removeAll { $0.id == sub.id } }
                                }
                            }
                            Button("Add Subcategory") { category.subcategories.append(.init(id: UUID().uuidString, label: "New subcategory", origin: .user)) }
                            Button("Remove Category", role: .destructive) { categories.removeAll { $0.id == category.id } }
                        }
                    }
                    Button("Add Category") { categories.append(.init(id: UUID().uuidString, label: "New category", origin: .user)) }
                    Text("Referenced categories cannot be removed. Unused definitions remain available and are included in backups.").font(.caption)
                }
    }
    private var accountSection: some View {
                Section("Accounts") {
                    ForEach($context.accounts) { $account in
                        DisclosureGroup(account.alias) {
                            TextField("Alias", text: $account.alias)
                            SourceValueField(title: "Provider", value: $account.provider)
                            SourceValueField(title: "Provider account identity", value: $account.providerAccountID)
                            Button("Remove Account", role: .destructive) { context.accounts.removeAll { $0.id == account.id } }
                        }
                    }
                    Button("Add Account") { context.accounts.append(.init(alias: "New account")) }
                }
    }
    private var programSection: some View {
                Section("Benefit programs") {
                    ForEach($context.programs) { $program in
                        DisclosureGroup(program.label) {
                            BenefitProgramFields(program: $program)
                            Button("Remove Program", role: .destructive) { context.programs.removeAll { $0.id == program.id } }
                        }
                    }
                    Button("Add Program") { context.programs.append(.init(label: "New program")) }
                }
    }
    private var reimbursementSection: some View {
                Section("Reimbursements") {
                    Text("Expected amounts do not reduce spending. Only actual receipts assigned to a claim reduce purchase net cost. Unknown amounts and settings remain unknown.").font(.caption)
                    ForEach($context.claims) { $claim in
                        DisclosureGroup(ledger.record(id: claim.expenseID)?.draft.payee ?? "Choose purchase") {
                            ClaimFields(claim: $claim, records: ledger.records, programs: context.programs)
                            if let received = try? FinancialAccounting.received(claimID: claim.id, workspace: reimbursementWorkspace) {
                                LabeledContent("Assigned actual receipts", value: received.decimalText)
                            }
                            if let expected = claim.expected {
                                Text("Expected " + expected.decimalText + "; received and outstanding use assigned receipt records.").font(.caption)
                            }
                            if let outstanding = try? FinancialAccounting.outstanding(claim: claim, workspace: reimbursementWorkspace) {
                                LabeledContent("Outstanding", value: outstanding.decimalText)
                            } else { Text("Outstanding unknown until an expected amount is supplied.").font(.caption) }
                            Button("Remove Claim", role: .destructive) { context.claims.removeAll { $0.id == claim.id } }
                        }
                    }
                    Button("Add Claim") {
                        if let purchase = ledger.records.first(where: { $0.draft.treatment == .spending }) { context.claims.append(.init(expenseID: purchase.id)) }
                    }.disabled(!ledger.records.contains { $0.draft.treatment == .spending })
                    ForEach($context.repayments) { $part in
                        DisclosureGroup("Actual repayment " + part.amount.decimalText) {
                            RepaymentFields(part: $part, claims: context.claims, records: ledger.records)
                            Button("Remove Repayment Link", role: .destructive) { context.repayments.removeAll { $0.id == part.id } }
                        }
                    }
                    Button("Link Actual Repayment") {
                        if let claim = context.claims.first, let receipt = ledger.records.first(where: { $0.draft.treatment == .reimbursementReceipt && $0.draft.postingStatus == .posted }) {
                            context.repayments.append(.init(receiptID: receipt.id, claimID: claim.id, amount: Money(minorUnits: 0)))
                        }
                    }.disabled(context.claims.isEmpty || !ledger.records.contains { $0.draft.treatment == .reimbursementReceipt && $0.draft.postingStatus == .posted })
                }
    }
    private var reportingSection: some View {
                Section("Reporting") {
                    Text("America/New_York · Monday weeks · calendar-month presets")
                    Toggle("Include posted unapproved purchases", isOn: $context.reporting.includePostedUnreviewed)
                    Text("Source coverage, source comparison controls and typed payment/duplicate relationships are available in Advanced Financial Settings.").font(.caption)
                    NavigationLink("Advanced Financial Settings") {
                        FinancialJSONEditor(context: $context)
                    }
                }
    }
    private var reimbursementWorkspace: ReviewWorkspace {
        var value = ledger.workspace; value.claims = context.claims; value.repayments = context.repayments; return value
    }
    private var financialObjectIDs: [UUID] { context.programs.map(\.id) + context.claims.map(\.id) + context.repayments.map(\.id) }
}

private struct SourceValueField: View {
    let title: String
    @Binding var value: SourceValue
    var body: some View {
        Picker(title, selection: $value.kind) {
            Text("Unknown").tag(SourceValue.Kind.unknown); Text("Absent").tag(SourceValue.Kind.absent)
            Text("Null").tag(SourceValue.Kind.null); Text("Text").tag(SourceValue.Kind.text)
            Text("Number").tag(SourceValue.Kind.number); Text("Boolean").tag(SourceValue.Kind.boolean)
        }.onChange(of: value.kind) { _, kind in
            value.text = [.text, .number].contains(kind) ? "" : nil
            value.boolean = kind == .boolean ? false : nil
        }
        if [.text, .number].contains(value.kind) {
            TextField(title + " value", text: Binding(get: { value.text ?? "" }, set: { value.text = $0 }))
        } else if value.kind == .boolean {
            Toggle(title + " value", isOn: Binding(get: { value.boolean ?? false }, set: { value.boolean = $0 }))
        }
    }
}

private struct OptionalMoneyField: View {
    let title: String
    let id: String
    var required = false
    @Binding var value: Money?
    @Environment(FinancialInputState.self) private var inputs
    private var text: String { inputs.text[id] ?? value?.decimalText ?? "" }
    var body: some View {
        TextField(title + (required ? "" : " (blank = unknown)"), text: Binding(get: { text }, set: { input in
            inputs.text[id] = input
            if input.isEmpty && !required { value = nil; inputs.errors.remove(id) }
            else if let parsed = try? Money(decimalText: input) { value = parsed; inputs.errors.remove(id) }
            else { inputs.errors.insert(id) }
        })).keyboardType(.decimalPad)
        if inputs.errors.contains(id) { Text("Enter a complete amount before saving.").foregroundStyle(.red) }
    }
}

private struct BenefitProgramFields: View {
    @Binding var program: BenefitProgram
    var body: some View {
        TextField("Program", text: $program.label)
        OptionalMoneyField(title: "Limit", id: program.id.uuidString + ":limit", value: $program.limit)
        Picker("Period", selection: $program.period.basis) { ForEach(BenefitPeriod.Basis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        SourceDateField(title: "Period start", id: program.id.uuidString + ":start", value: $program.period.from)
        SourceDateField(title: "Period end", id: program.id.uuidString + ":end", value: $program.period.through)
        SourceValueField(title: "Eligibility rules", value: $program.eligibilityRules)
        Text("Unspecified limits, eligibility and reset rules are not inferred.").font(.caption)
    }
}
private struct SourceDateField: View {
    let title: String
    let id: String
    @Binding var value: TransactionDate?
    @Environment(FinancialInputState.self) private var inputs
    private var text: String { inputs.text[id] ?? value?.iso8601 ?? "" }
    var body: some View {
        TextField(title + " (YYYY-MM-DD; blank = unknown)", text: Binding(get: { text }, set: { input in
            inputs.text[id] = input
            if input.isEmpty { value = nil; inputs.errors.remove(id) }
            else if let parsed = try? TransactionDate(input) { value = parsed; inputs.errors.remove(id) }
            else { inputs.errors.insert(id) }
        }))
        if inputs.errors.contains(id) { Text("Enter a complete date before saving.").foregroundStyle(.red) }
    }
}
@MainActor @Observable private final class FinancialInputState {
    var text: [String: String] = [:]
    var errors: Set<String> = []
    func prune(keeping ids: [UUID]) {
        let prefixes = Set(ids.map(\.uuidString))
        text = text.filter { prefixes.contains(String($0.key.prefix(36))) }
        errors = errors.filter { prefixes.contains(String($0.prefix(36))) }
    }
}
private struct ClaimFields: View {
    @Binding var claim: ReimbursementClaim
    let records: [LedgerTransaction]
    let programs: [BenefitProgram]
    var body: some View {
        Picker("Purchase", selection: $claim.expenseID) { ForEach(records.filter { $0.draft.treatment == .spending }) { Text($0.draft.payee + " · " + $0.draft.date.iso8601).tag($0.id) } }
        Picker("Program", selection: $claim.programID) {
            Text("Unknown / none").tag(Optional<UUID>.none)
            ForEach(programs) { Text($0.label).tag(Optional($0.id)) }
        }
        Picker("Eligibility", selection: $claim.eligibility) { ForEach(ReimbursementEligibility.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        Picker("Status", selection: $claim.status) { ForEach(ClaimStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
        OptionalMoneyField(title: "Expected", id: claim.id.uuidString + ":expected", value: $claim.expected)
        OptionalMoneyField(title: "Source-reported received (unverified)", id: claim.id.uuidString + ":reported", value: $claim.sourceReportedReceived)
        TextField("Claim notes", text: $claim.notes, axis: .vertical)
    }
}
private struct RepaymentFields: View {
    @Binding var part: RepaymentAllocation
    let claims: [ReimbursementClaim]
    let records: [LedgerTransaction]
    var body: some View {
        Picker("Actual receipt", selection: $part.receiptID) { ForEach(records.filter { $0.draft.treatment == .reimbursementReceipt && $0.draft.postingStatus == .posted }) { Text($0.draft.payee + " · " + $0.draft.amount.decimalText).tag($0.id) } }
        Picker("Claim", selection: $part.claimID) { ForEach(claims) { claim in Text(records.first { $0.id == claim.expenseID }?.draft.payee ?? claim.id.uuidString).tag(claim.id) } }
        Picker("Purchase allocation", selection: $part.expenseAllocationID) {
            Text("Whole purchase / unattributed").tag(Optional<UUID>.none)
            if let claim = claims.first(where: { $0.id == part.claimID }), let expense = records.first(where: { $0.id == claim.expenseID }) {
                ForEach(expense.draft.components) { component in Text(component.categoryID + " · " + component.amount.decimalText).tag(Optional(component.id)) }
            }
        }
        OptionalMoneyField(title: "Assigned receipt amount", id: part.id.uuidString + ":amount", required: true, value: Binding(get: { part.amount }, set: { if let value = $0 { part.amount = value } }))
    }
}
private struct FinancialJSONEditor: View {
    @Binding var context: FinancialContext
    @State private var text = ""
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack {
            Text("Edit the supplied typed financial settings. Unknown fields, broken references and invalid controls are rejected on Save. Source baselines, migration audit and refund receipts are read-only.").font(.caption)
            TextEditor(text: $text).font(.system(.caption, design: .monospaced)).autocorrectionDisabled()
            if let failure { Text(failure).foregroundStyle(.red) }
            Button("Use Settings Draft") {
                do {
                    var value = try StrictJSON.decode(FinancialContext.self, from: Data(text.utf8))
                    value.migrationAudit = context.migrationAudit; value.refundReceipts = context.refundReceipts
                    value.sourceBaselines = context.sourceBaselines
                    context = value; dismiss()
                } catch { failure = error.localizedDescription }
            }
        }.padding().onAppear {
            do { text = String(decoding: try ExchangeJSON.encode(context), as: UTF8.self) } catch { failure = error.localizedDescription }
        }
    }
}

@MainActor
struct FinTrackRootView: View {
    @Bindable var ledger: LedgerViewModel
    @State private var tab = WorkspaceTab.review
    @State private var showBackup = false
    @State private var confirmEmptyLedger = false

    private enum WorkspaceTab: Hashable { case overview, review, questions, history, export, visibility }

    var body: some View {
        Group {
            if let failure = ledger.startupFailure {
                VStack(spacing: 16) {
                    ContentUnavailableView("Unable to Open FinTrack", systemImage: "externaldrive.badge.exclamationmark",
                        description: Text("\(failure)\nYour existing files have been preserved."))
                    Button("Restore a Backup", systemImage: "arrow.counterclockwise") { showBackup = true }
                        .buttonStyle(.borderedProminent)
                    Button("Create a Separate Empty Ledger", role: .destructive) { confirmEmptyLedger = true }
                        .buttonStyle(.bordered).padding(.bottom, 24)
                }
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
            if ledger.startupFailure == nil && (ledger.backup?.isCurrent != true || ledger.capacityNotice != nil) {
                Button { showBackup = true } label: {
                    Label(ledger.capacityNotice ?? ledger.backup?.status ?? "Automatic iCloud backup needs attention.", systemImage: "icloud.and.arrow.up")
                        .font(.caption).frame(maxWidth: .infinity).padding(6)
                }.background(.thinMaterial)
            }
        }
        .sheet(isPresented: $showBackup) { BackupSettingsView(ledger: ledger) }
        .confirmationDialog("Start with an empty ledger?", isPresented: $confirmEmptyLedger, titleVisibility: .visible) {
            Button("Create Separate Empty Ledger", role: .destructive) {
                do { try ledger.restoreBackup(FullBackup(records: [], workspace: ReviewWorkspace())) }
                catch { ledger.message = "Could not create a new ledger: " + error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Existing files are preserved. This activates a new empty database; use Restore instead if you have a backup to recover.") }
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
    var from = ReportingCalendar.calendar.date(byAdding: .day, value: -56, to: .now)!
    var through = Date.now

    var isValid: Bool { period != .custom || ReportingCalendar.dayText(at: from) <= ReportingCalendar.dayText(at: through) }

    var selection: LedgerSelection {
        switch period {
        case .all: LedgerSelection()
        case .oneMonth: preset(.oneMonth)
        case .threeMonths: preset(.threeMonths)
        case .sixMonths: preset(.sixMonths)
        case .yearToDate: preset(.yearToDate)
        case .pastYear: preset(.pastYear)
        case .eightWeeks: LedgerSelection(
            from: try? TransactionDate(ReportingCalendar.dayText(at: ReportingCalendar.calendar.date(byAdding: .day, value: -56, to: .now)!)),
            through: try? TransactionDate(ReportingCalendar.dayText(at: .now)))
        case .custom: LedgerSelection(from: try? TransactionDate(ReportingCalendar.dayText(at: from)),
            through: try? TransactionDate(ReportingCalendar.dayText(at: through)))
        }
    }

    private func preset(_ period: WorkspacePeriod) -> LedgerSelection {
        guard let today = try? TransactionDate(ReportingCalendar.dayText(at: .now)), let range = try? period.range(through: today) else {
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
                .environment(\.calendar, ReportingCalendar.calendar)
                .environment(\.timeZone, ReportingCalendar.calendar.timeZone)
            DatePicker("Through", selection: $scope.through, displayedComponents: .date)
                .environment(\.calendar, ReportingCalendar.calendar)
                .environment(\.timeZone, ReportingCalendar.calendar.timeZone)
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
                if record.draft.exceptionalEvent == true {
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

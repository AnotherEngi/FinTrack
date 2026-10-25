import SwiftUI
import FinTrackCore

@MainActor
struct TransactionEditorView: View {
    var ledger: LedgerViewModel
    var onAdvance: (UUID) -> Void
    let startDiscussion: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EditorDraft
    @State private var status = "Valid edits save on this iPad as you type."
    @State private var discardConfirmation = false
    @State private var needsRetry = false
    @State private var draftWriteFailed = false
    @State private var pendingRequest: ReviewRequest?
    @State private var showDiscussion = false
    @State private var showRefundPurchases = false
    @State private var refundSearch = ""
    @State private var visibilityFailure: String?
    @FocusState private var noteFocused: Bool

    init(ledger: LedgerViewModel, draft: EditorDraft, startDiscussion: Bool = false,
         onAdvance: @escaping (UUID) -> Void) {
        self.ledger = ledger
        self.onAdvance = onAdvance
        self.startDiscussion = startDiscussion
        _draft = State(initialValue: draft)
    }

    private var currentRecord: LedgerTransaction? { ledger.record(id: draft.id) }

    private var refundPurchaseCandidates: [LedgerTransaction] {
        let linkedIDs = Set((draft.input.refundAllocations ?? []).map(\.purchaseID))
        return ledger.records.filter { record in
            guard record.id != draft.id, record.draft.treatment == .spending,
                  record.draft.postingStatus == .posted, record.draft.date.iso8601 <= draft.input.dateText,
                  !linkedIDs.contains(record.id) else { return false }
            return refundSearch.isEmpty || record.draft.payee.localizedCaseInsensitiveContains(refundSearch)
                || record.draft.date.iso8601.contains(refundSearch)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Review / posted date (YYYY-MM-DD)", text: $draft.input.dateText)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    TextField("Activity date (optional)", text: $draft.input.activityDateText)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    TextField("Payee or description", text: $draft.input.payee)
                    TextField("Source label (optional)", text: $draft.input.sourceLabel)
                    Text("Use a label such as Sample Visa, without account numbers or credentials.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Amount", text: $draft.input.amountText)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    Text("Expenses are positive (12.34). Refunds and income are negative (-12.34).")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Posting", selection: $draft.input.postingStatus) {
                        Text("Posted").tag(PostingStatus.posted)
                        Text("Pending").tag(PostingStatus.pending)
                        Text("Needs posting review").tag(PostingStatus.unresolved)
                    }
                    Picker("Treatment", selection: $draft.input.treatment) {
                        ForEach(TransactionTreatment.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Section("Classification") {
                    Picker("Category", selection: $draft.input.categoryID) {
                        Text("Choose a category").tag(Optional<String>.none)
                        ForEach(ledger.catalog.categories) { category in
                            Text(category.label).tag(Optional(category.id))
                        }
                        if let categoryID = draft.input.categoryID,
                           ledger.catalog.category(id: categoryID) == nil {
                            Text("Unavailable category").tag(Optional(categoryID))
                        }
                    }
                    TextField("Tags (separate with semicolons)", text: $draft.input.tagsText)
                    Toggle("Exceptional Event", isOn: $draft.input.exceptionalEvent)
                    Text("Exceptional Events remain included in shown spending.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if draft.input.treatment == .refund || !(draft.input.refundAllocations ?? []).isEmpty { refundSection }
                Section("Overview visibility") {
                    Toggle("Hide this transaction from Overview", isOn: Binding(
                        get: { ledger.workspace.summaryVisibility?.recordIDs.contains(draft.id) == true },
                        set: { hidden in
                            do { try ledger.setSummaryHidden(hidden, recordID: draft.id) }
                            catch { visibilityFailure = error.localizedDescription }
                        })).disabled(currentRecord == nil)
                    if let record = currentRecord, let rules = ledger.workspace.summaryVisibility,
                       rules.categoryIDs.contains(record.draft.categoryID ?? "") || !rules.tags.isDisjoint(with: record.draft.tags) {
                        Text("A hidden category or tag also hides this transaction. Manage that rule in Visibility.").font(.caption).foregroundStyle(.secondary)
                    }
                    if currentRecord == nil { Text("Save a valid transaction before changing visibility.").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Your Note to ChatGPT") {
                    TextField("Your note", text: $draft.input.notes, axis: .vertical).lineLimit(3...8)
                        .focused($noteFocused)
                }
                if let record = currentRecord {
                    if !record.assistantContext.question.isEmpty || !record.assistantContext.reason.isEmpty {
                        Section("From ChatGPT") {
                            if !record.assistantContext.question.isEmpty {
                                Text(record.assistantContext.question).textSelection(.enabled)
                            }
                            if !record.assistantContext.reason.isEmpty {
                                Text(record.assistantContext.reason).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    if !record.assistantContext.question.isEmpty || !draft.input.answer.isEmpty {
                        Section("Your Answer") {
                            TextField("Your answer", text: $draft.input.answer, axis: .vertical).lineLimit(2...6)
                        }
                    }
                    if !record.assistantContext.ledgerNotes.isEmpty {
                        Section("Earlier Ledger Notes") {
                            Text(record.assistantContext.ledgerNotes).textSelection(.enabled)
                        }
                    }
                    reviewActions(record)
                    if let thread = ledger.discussions[record.id] {
                        Section("Discussion") {
                            Text(thread.status.label)
                            Button("Read Replies / Continue Discussion", systemImage: "questionmark.bubble") { showDiscussion = true }
                        }
                    }
                    if !record.reviewHistory.isEmpty {
                        Section("Review History") {
                            ForEach(record.reviewHistory.reversed()) { entry in
                                LabeledContent(entry.request.action.label,
                                    value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            }
                        }
                    }
                }
                if let legacy = draft.input.legacyReviewStatus {
                    Section("Earlier Prototype Review") {
                        Text("Preserved flag: \(legacy == .reviewed ? "Reviewed" : "Needs review"). Select posting status, treatment, and category before approving this classification.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let fields = ledger.workspace.historyDetails?[draft.id.uuidString], !fields.isEmpty {
                    Section("Preserved Sheet Details") {
                        Text("Read-only source details. Preserved split, reimbursement or subcategory fields do not become supported calculations merely by being imported.").font(.caption).foregroundStyle(.secondary)
                        ForEach(fields.keys.sorted(), id: \.self) { key in
                            LabeledContent(key) { Text(fields[key] ?? "").textSelection(.enabled) }
                        }
                    }
                }
                Section {
                    Text(status).font(.callout).accessibilityLabel("Save status: \(status)")
                    if needsRetry { Button("Retry Save") { saveChangedInput() } }
                }
            }
            .navigationTitle(draft.expectedRevision == nil ? "New Transaction" : "Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(draftWriteFailed)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Discard Unsaved Draft", role: .destructive) { discardConfirmation = true }
                }
            }
            .onChange(of: draft.input) { _, _ in pendingRequest = nil; saveChangedInput() }
            .task { if startDiscussion { noteFocused = true } }
            .interactiveDismissDisabled(draftWriteFailed)
            .alert("Visibility Not Saved", isPresented: Binding(get: { visibilityFailure != nil }, set: { if !$0 { visibilityFailure = nil } })) {
                Button("OK") { visibilityFailure = nil }
            } message: { Text(visibilityFailure ?? "") }
            .sheet(isPresented: $showDiscussion) { DiscussionDetailView(ledger: ledger, recordID: draft.id) }
            .sheet(isPresented: $showRefundPurchases) { refundPurchasePicker }
            .confirmationDialog("Discard unsaved input? Previously saved edits will remain.",
                                isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("Discard Unsaved Draft", role: .destructive) {
                    do { try ledger.discardDraft(id: draft.id); dismiss() }
                    catch { status = "Unable to discard draft: \(error.localizedDescription)" }
                }
            }
        }
    }

    private var refundSection: some View {
        Section("Refund applies to") {
            Text("Link the original purchases and enter a positive amount for each. The summary reduces their purchase dates and categories; this refund keeps its bank date. Any unallocated amount stays flagged for linking.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(draft.input.refundAllocations ?? []) { link in
                VStack(alignment: .leading) {
                    if let purchase = ledger.record(id: link.purchaseID) {
                        Text(purchase.draft.payee + " · " + (purchase.draft.activityDate ?? purchase.draft.date).iso8601)
                    } else { Text("Missing purchase").foregroundStyle(.red) }
                    HStack {
                        TextField("Refund amount for this purchase", text: Binding(
                            get: { draft.input.refundAllocations?.first { $0.purchaseID == link.purchaseID }?.amountText ?? "" },
                            set: { text in
                                if let index = draft.input.refundAllocations?.firstIndex(where: { $0.purchaseID == link.purchaseID }) {
                                    draft.input.refundAllocations?[index].amountText = text
                                }
                            }))
                            .keyboardType(.decimalPad)
                        Button("Remove", role: .destructive) {
                            draft.input.refundAllocations?.removeAll { $0.purchaseID == link.purchaseID }
                        }.buttonStyle(.borderless)
                    }
                }
            }
            Button("Link a Purchase", systemImage: "link") { showRefundPurchases = true }
                .disabled((draft.input.refundAllocations?.count ?? 0) >= 100)
        }
    }

    private var refundPurchasePicker: some View {
        NavigationStack {
            List {
                if refundPurchaseCandidates.isEmpty { Text("No matching posted purchases. Add or import the original purchase first.").foregroundStyle(.secondary) }
                ForEach(refundPurchaseCandidates) { purchase in
                    Button {
                        if draft.input.refundAllocations == nil { draft.input.refundAllocations = [] }
                        draft.input.refundAllocations?.append(RefundAllocationInput(purchaseID: purchase.id))
                        showRefundPurchases = false
                    } label: { LedgerRecordRow(record: purchase, catalog: ledger.catalog) }
                }
            }
            .searchable(text: $refundSearch, prompt: "Find the original purchase")
            .navigationTitle("Link a Purchase").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showRefundPurchases = false } } }
        }
    }

    @ViewBuilder
    private func reviewActions(_ record: LedgerTransaction) -> some View {
        Section("Review") {
            LabeledContent("Saved approval", value: record.approval.label)
            if record.discussionRequested {
                Label(record.discussionProgress == .reviewingInChatGPT ? "Reviewing in ChatGPT" : "Discussion waiting for export",
                    systemImage: "bubble.left.and.bubble.right")
                if record.discussionProgress != .reviewingInChatGPT {
                    Button("Mark Reviewing in ChatGPT") { perform(.markDiscussionInProgress) }.disabled(needsRetry)
                }
                Text("Imported replies appear in Discussions. Saving or sharing a review alone does not prove ChatGPT received it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            let approvalReason = record.reviewBlockReason(for: .approve, catalog: ledger.catalog)
            if let approvalReason { Text(approvalReason).font(.caption).foregroundStyle(.secondary) }
            Button("Approve") { perform(.approve) }
                .disabled(needsRetry || approvalReason != nil)
            let discussionReason = record.reviewBlockReason(for: .discuss, catalog: ledger.catalog)
            Button("Discuss") { perform(.discuss) }
                .disabled(needsRetry || discussionReason != nil)
            if discussionReason != nil && !record.draft.treatment.excludedFromReview {
                Text(discussionReason ?? "").font(.caption).foregroundStyle(.secondary)
            }
            if record.approval == .confirmed || record.discussionRequested {
                Button("Reopen") { perform(.reopen) }.disabled(needsRetry)
            }
            Button("Skip") { perform(.skip) }.disabled(needsRetry)
        }
    }

    private func perform(_ action: ReviewAction) {
        guard saveChangedInput(), let revision = draft.expectedRevision else { return }
        let request: ReviewRequest
        if let pendingRequest, pendingRequest.action == action, pendingRequest.expectedRevision == revision {
            request = pendingRequest
        } else {
            request = ReviewRequest(transactionID: draft.id, expectedRevision: revision, action: action)
            pendingRequest = request
        }
        do {
            let saved = try ledger.perform(request)
            draft.expectedRevision = saved.revision
            pendingRequest = nil
            status = "Review action saved on this iPad."
            if [.approve, .discuss, .skip].contains(action) { onAdvance(draft.id) }
        } catch {
            status = "Review action was not applied: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func saveChangedInput() -> Bool {
        do {
            try ledger.storeDraft(draft)
            draftWriteFailed = false
        }
        catch {
            draftWriteFailed = true
            needsRetry = true
            status = "Draft could not be saved. Keep this editor open and retry: \(error.localizedDescription)"
            return false
        }
        do {
            draft = try ledger.commitDraft(draft)
            needsRetry = false
            status = "Saved on this iPad."
            return true
        } catch {
            needsRetry = true
            status = "Draft saved on this iPad. \(error.localizedDescription)"
            return false
        }
    }
}

import SwiftUI
import FinTrackCore

@MainActor
struct TransactionEditorView: View {
    var ledger: LedgerViewModel
    var onAdvance: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EditorDraft
    @State private var status = "Valid edits save on this iPad as you type."
    @State private var discardConfirmation = false
    @State private var needsRetry = false
    @State private var draftWriteFailed = false
    @State private var pendingRequest: ReviewRequest?

    init(ledger: LedgerViewModel, draft: EditorDraft, onAdvance: @escaping (UUID) -> Void) {
        self.ledger = ledger
        self.onAdvance = onAdvance
        _draft = State(initialValue: draft)
    }

    private var currentRecord: LedgerTransaction? { ledger.record(id: draft.id) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Review / posted date (YYYY-MM-DD)", text: $draft.input.dateText)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    TextField("Activity date (optional)", text: $draft.input.activityDateText)
                        .keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    TextField("Payee or description", text: $draft.input.payee)
                    TextField("Amount in USD", text: $draft.input.amountText)
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
                Section("Your Note to ChatGPT") {
                    TextField("Your note", text: $draft.input.notes, axis: .vertical).lineLimit(3...8)
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
            .interactiveDismissDisabled(draftWriteFailed)
            .confirmationDialog("Discard unsaved input? Previously saved edits will remain.",
                                isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("Discard Unsaved Draft", role: .destructive) {
                    do { try ledger.discardDraft(id: draft.id); dismiss() }
                    catch { status = "Unable to discard draft: \(error.localizedDescription)" }
                }
            }
        }
    }

    @ViewBuilder
    private func reviewActions(_ record: LedgerTransaction) -> some View {
        Section("Review") {
            LabeledContent("Saved approval", value: record.approval.label)
            if record.discussionRequested { Label("Needs discussion", systemImage: "bubble.left.and.bubble.right") }
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
            if action != .reopen { onAdvance(draft.id) }
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

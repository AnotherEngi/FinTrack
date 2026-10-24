import Foundation
import Testing
@testable import FinTrackCore

private func purchase(notes: String = "", answer: String = "", status: PostingStatus = .posted,
                      treatment: TransactionTreatment = .spending,
                      category: String? = "sample-groceries", amount: Int64 = 2_500,
                      assistant: AssistantContext = .init()) throws -> LedgerTransaction {
    try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-10-01"),
        payee: "Invented merchant", amount: Money(minorUnits: amount), notes: notes, answer: answer,
        postingStatus: status, treatment: treatment, categoryID: category), assistantContext: assistant)
}

private func action(_ kind: ReviewAction, on record: LedgerTransaction,
                    id: UUID = UUID()) throws -> LedgerTransaction {
    try record.applying(ReviewRequest(id: id, transactionID: record.id,
        expectedRevision: record.revision, action: kind), catalog: .prototype)
}

@Test func onlyExplicitApprovalConfirmsAPurchase() throws {
    let record = try purchase(notes: "Looks correct")
    #expect(record.approval == .unreviewed)
    let discussed = try action(.discuss, on: record)
    #expect(discussed.approval == .unreviewed)
    #expect(discussed.discussionRequested)
    let approved = try action(.approve, on: discussed)
    #expect(approved.approval == .confirmed)
    #expect(!approved.discussionRequested)
    #expect(approved.reviewHistory.map(\.request.action) == [.discuss, .approve])
}

@Test func notesAnswersAndDiscussionPreserveApprovalAndAssistantOwnership() throws {
    let context = AssistantContext(question: "What was this for?", reason: "A suggestion",
                                   ledgerNotes: "Earlier history remains read-only")
    let approved = try action(.approve, on: purchase(assistant: context))
    var draft = approved.draft
    draft.notes = "My own explanation"
    draft.answer = "Household supplies"
    let edited = try approved.revising(with: draft, expectedRevision: approved.revision)
    let discussed = try action(.discuss, on: edited)
    #expect(discussed.approval == .confirmed)
    #expect(discussed.discussionRequested)
    #expect(discussed.assistantContext == context)
    #expect(discussed.draft.notes == "My own explanation")
    #expect(discussed.draft.answer == "Household supplies")
}

@Test func classificationAndFinancialChangesReopenApproval() throws {
    let approved = try action(.approve, on: purchase(notes: "Please check this"))
    let discussed = try action(.discuss, on: approved)
    let mutations: [(inout TransactionDraft) throws -> Void] = [
        { $0.categoryID = "sample-household" }, { $0.tags = ["Sample trip"] },
        { $0.exceptionalEvent = true }, { $0.amount = Money(minorUnits: 2_600) },
        { $0.postingStatus = .pending }, { $0.payee = "Corrected merchant" },
        { $0.date = try TransactionDate("2026-10-02") },
        { $0.activityDate = try TransactionDate("2026-09-30") }
    ]
    for mutate in mutations {
        var draft = discussed.draft
        try mutate(&draft)
        let changed = try discussed.revising(with: draft, expectedRevision: discussed.revision)
        #expect(changed.approval == .unreviewed)
        #expect(changed.discussionRequested)
        #expect(changed.reviewHistory == discussed.reviewHistory)
    }
}

@Test func pendingTransactionsCanBeDiscussedButNotApproved() throws {
    let record = try purchase(notes: "Check once posted", status: .pending)
    #expect(throws: ReviewError.pendingApproval) { try action(.approve, on: record) }
    let discussed = try action(.discuss, on: record)
    #expect(discussed.discussionRequested)
    #expect(discussed.approval == .unreviewed)
    var posted = discussed.draft
    posted.postingStatus = .posted
    let saved = try discussed.revising(with: posted, expectedRevision: discussed.revision)
    #expect(saved.approval == .unreviewed)
    #expect(try action(.approve, on: saved).approval == .confirmed)
}

@Test func unknownUnresolvedAndExcludedCategoriesBlockApproval() throws {
    for category: String? in [nil, "unknown-category", "sample-unresolved", "sample-excluded"] {
        let record = try purchase(category: category)
        #expect(throws: ReviewError.unresolvedCategory) { try action(.approve, on: record) }
    }
    let unresolved = try purchase(treatment: .unresolved)
    #expect(throws: ReviewError.unresolvedTreatment) { try action(.approve, on: unresolved) }
    let unknownPosting = try purchase(status: .unresolved)
    #expect(throws: ReviewError.unresolvedPosting) { try action(.approve, on: unknownPosting) }
}

@Test func excludedTreatmentsStayOutsideSpendingReview() throws {
    for treatment in [TransactionTreatment.income, .payment, .statementCredit, .transfer] {
        let record = try purchase(notes: "Does not authorize approval", treatment: treatment, amount: -500)
        #expect(record.approval == .notApplicable)
        #expect(throws: ReviewError.excludedTreatment) { try action(.approve, on: record) }
        #expect(throws: ReviewError.excludedTreatment) { try action(.discuss, on: record) }
        #expect(try action(.skip, on: record) == record)
    }
    let approved = try action(.approve, on: purchase(notes: "A comment"))
    var draft = approved.draft
    draft.treatment = .transfer
    let changed = try approved.revising(with: draft, expectedRevision: approved.revision)
    #expect(changed.approval == .notApplicable)
    #expect(!changed.discussionRequested)
}

@Test func assistantTextCannotSupplyUserDiscussionConsent() throws {
    let record = try purchase(assistant: .init(question: "Please explain", reason: "AI text",
                                             ledgerNotes: "An earlier assistant note"))
    #expect(record.draft.notes.isEmpty)
    #expect(throws: ReviewError.discussionNeedsContext) { try action(.discuss, on: record) }
    var draft = record.draft
    draft.answer = "My answer"
    let answered = try record.revising(with: draft, expectedRevision: record.revision)
    #expect(try action(.discuss, on: answered).discussionRequested)
}

@Test func reopenClearsDiscussionAndSkipCreatesNoDecision() throws {
    let record = try purchase(notes: "Check category")
    let approved = try action(.approve, on: record)
    let discussed = try action(.discuss, on: approved)
    let reopened = try action(.reopen, on: discussed)
    #expect(reopened.approval == .unreviewed)
    #expect(!reopened.discussionRequested)
    #expect(try action(.skip, on: reopened) == reopened)
}

@Test func staleActionsAndReusedOperationIDsCannotOverwriteNewerEdits() throws {
    let record = try purchase()
    let request = ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: .approve)
    let approved = try record.applying(request, catalog: .prototype)
    #expect(try approved.applying(request, catalog: .prototype) == approved)
    var draft = approved.draft
    draft.tags = ["My correction"]
    let newer = try approved.revising(with: draft, expectedRevision: approved.revision)
    #expect(try newer.applying(request, catalog: .prototype) == newer)
    #expect(newer.approval == .unreviewed)
    #expect(throws: LedgerError.staleRevision) {
        try newer.applying(ReviewRequest(transactionID: newer.id, expectedRevision: 1, action: .approve), catalog: .prototype)
    }
    #expect(throws: ReviewError.operationIDReused) {
        try newer.applying(ReviewRequest(id: request.id, transactionID: newer.id,
            expectedRevision: newer.revision, action: .reopen), catalog: .prototype)
    }
    #expect(throws: ReviewError.wrongTransaction) {
        try newer.applying(ReviewRequest(transactionID: UUID(), expectedRevision: newer.revision,
                                        action: .approve), catalog: .prototype)
    }
}

@Test func unchangedEditsAndTagReorderingDoNotRevokeApproval() throws {
    var initial = try purchase().draft
    initial.tags = ["A", "B"]
    let approved = try action(.approve, on: LedgerTransaction(draft: initial))
    #expect(try approved.revising(with: approved.draft, expectedRevision: approved.revision) == approved)
    var reordered = approved.draft
    reordered.tags.reverse()
    #expect(try approved.revising(with: reordered, expectedRevision: approved.revision).approval == .confirmed)
}

@Test func spendingTotalsSeparatePendingAndExcludeNonspendingTreatments() throws {
    let original = try purchase(amount: 5_000)
    var draft = original.draft
    draft.exceptionalEvent = true
    let flagged = try original.revising(with: draft, expectedRevision: original.revision)
    let records = try [flagged, purchase(treatment: .refund, amount: -1_200),
        purchase(status: .pending, amount: 700), purchase(treatment: .payment, amount: -9_000),
        purchase(treatment: .statementCredit, amount: -800), purchase(treatment: .transfer, amount: 4_000),
        purchase(treatment: .income, amount: -100_000), purchase(treatment: .unresolved, amount: 500),
        purchase(status: .unresolved, amount: 900)]
    let totals = try SpendingTotals(records: records)
    #expect(totals.posted.minorUnits == 3_800)
    #expect(totals.pending.minorUnits == 700)
    #expect(throws: MoneyError.outOfRange) {
        try SpendingTotals(records: [purchase(amount: Int64.max), purchase(amount: 1)])
    }
}

@Test func invalidSignsCatalogsAndTagsAreRejected() throws {
    #expect(throws: ReviewError.invalidAmountSign) { try purchase(amount: -1) }
    #expect(throws: ReviewError.invalidAmountSign) { try purchase(treatment: .refund, amount: 1) }
    #expect(throws: ReviewError.invalidAmountSign) { try purchase(treatment: .income, amount: 1) }
    let category = ReviewCategory(id: "same", label: "Example")
    #expect(throws: ReviewError.invalidCatalog) { try ReviewCatalog(categories: [category, category]) }
    var draft = try purchase().draft
    draft.tags = ["duplicate", "duplicate"]
    #expect(throws: ReviewError.invalidTags) { try LedgerTransaction(draft: draft) }
}

@Test func oldReviewFlagsArePreservedWithoutInferringClassificationOrApproval() throws {
    let record = try purchase()
    let data = try JSONEncoder().encode(record)
    let decoded = try JSONSerialization.jsonObject(with: data)
    var old = try #require(decoded as? [String: Any])
    old.removeValue(forKey: "approval")
    old.removeValue(forKey: "reviewHistory")
    var draft = try #require(old["draft"] as? [String: Any])
    for field in ["treatment", "postingStatus", "categoryID", "legacyReviewStatus"] { draft.removeValue(forKey: field) }
    draft["reviewStatus"] = "reviewed"
    old["draft"] = draft
    let legacyData = try JSONSerialization.data(withJSONObject: old)
    let restored = try JSONDecoder().decode(LedgerTransaction.self, from: legacyData)
    #expect(restored.draft.legacyReviewStatus == .reviewed)
    #expect(restored.draft.treatment == .unresolved)
    #expect(restored.draft.postingStatus == .unresolved)
    #expect(restored.approval == .unreviewed)
    #expect(restored.draft.amount == record.draft.amount)
    #expect(restored.id == record.id)
}

@Test func reviewHistoryAndCommentOwnershipSurviveSerialization() throws {
    let record = try action(.discuss, on: purchase(notes: "User-owned",
        assistant: .init(question: "Assistant-owned", reason: "Reason", ledgerNotes: "History")))
    let encoded = try JSONEncoder().encode(record)
    let restored = try JSONDecoder().decode(LedgerTransaction.self, from: encoded)
    #expect(restored == record)
    #expect(restored.draft.notes != restored.assistantContext.question)
    let decoded = try JSONSerialization.jsonObject(with: encoded)
    var corrupt = try #require(decoded as? [String: Any])
    let history = try #require(corrupt["reviewHistory"] as? [[String: Any]])
    corrupt["reviewHistory"] = history + history
    let corruptData = try JSONSerialization.data(withJSONObject: corrupt)
    #expect(throws: ReviewError.invalidHistory) {
        try JSONDecoder().decode(LedgerTransaction.self, from: corruptData)
    }
}

@Test func oldIncompleteEditorInputRetainsTextAndNeverCreatesApproval() throws {
    let old: [String: Any] = ["dateText": "2026-10-01", "payee": "My draft",
        "amountText": "-12.", "notes": "My own note", "reviewStatus": "reviewed"]
    let data = try JSONSerialization.data(withJSONObject: old)
    let input = try JSONDecoder().decode(TransactionInput.self, from: data)
    #expect(input.amountText == "-12.")
    #expect(input.notes == "My own note")
    #expect(input.legacyReviewStatus == .reviewed)
    #expect(input.treatment == .unresolved)
    #expect(input.postingStatus == .unresolved)
    #expect(throws: MoneyError.invalidAmount) { try input.value() }
    var completed = input
    completed.amountText = "-12.00"
    let record = try LedgerTransaction(draft: completed.value())
    #expect(record.approval == .unreviewed)
    #expect(record.reviewHistory.isEmpty)
    let encoded = try JSONEncoder().encode(input)
    #expect(try JSONDecoder().decode(TransactionInput.self, from: encoded) == input)
}

@Test func editorInputKeepsNotesAnswersAndClassificationSeparate() throws {
    let draft = try purchase(notes: "User note", answer: "User answer").draft
    var input = TransactionInput(draft: draft)
    input.tagsText = "Sample trip; Sample work"
    input.activityDateText = "2026-09-30"
    let saved = try input.value()
    #expect(saved.notes == "User note")
    #expect(saved.answer == "User answer")
    #expect(saved.tags == ["Sample trip", "Sample work"])
    #expect(saved.activityDate?.iso8601 == "2026-09-30")
    #expect(saved.categoryID == draft.categoryID)
}

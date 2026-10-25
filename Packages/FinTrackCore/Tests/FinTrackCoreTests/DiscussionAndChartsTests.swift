import Foundation
import Testing
@testable import FinTrackCore

private func discussionRecord() throws -> LedgerTransaction {
    try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-10-01"), payee: "Fictional Shop",
        amount: Money(minorUnits: 1200), notes: "Which category fits this fictional purchase?", treatment: .spending,
        categoryID: "sample-household"), discussionRequested: true)
}

@Test func everyPopulatedClassificationHasAReviewColorWithoutInventingProvenance() {
    #expect(ClassificationStatus(approval: .unreviewed, origin: .unknown) == .needsReview)
    #expect(ClassificationStatus(approval: .unreviewed, origin: .assistant) == .needsReview)
    #expect(ClassificationStatus(approval: .unreviewed, origin: .user) == .userEdit)
    for origin in [ValueOrigin.unknown, .assistant, .user] {
        #expect(ClassificationStatus(approval: .confirmed, origin: origin) == .approved)
    }
}

@Test func importedDiscussionAnswerNeedsNoAcceptanceAndNeverChangesTheLedger() throws {
    let record = try discussionRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let requestJSON = try #require(JSONSerialization.jsonObject(with: ExchangeJSON.encode(packet)) as? [String: Any])
    let template = try #require(requestJSON["returnTemplate"] as? [String: Any])
    #expect(template["answers"] is [Any])
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: String(record.revision), text: "A fictional explanation, not a record edit.")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    let data = try ExchangeJSON.encode(response)
    try workspace.receive(data); try workspace.receive(data)
    #expect(workspace.staged.count == 1)
    #expect(workspace.pending.isEmpty)
    #expect(workspace.decidedProposals.isEmpty)
    #expect(workspace.discussion(for: record)?.status == .responseReceived)
    #expect(workspace.discussion(for: record)?.answers == [answer])
    #expect(record.revision == 1 && record.draft.categoryID == "sample-household" && record.approval == .unreviewed)
    let next = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    #expect(next.discussionContext?.first?.answers == [answer])
}

@Test func oldResponseExplanationsRemainReadableAndCanonicalReimportsRemainIdempotent() throws {
    let record = try discussionRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let explanation = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        question: "Can you clarify the fictional purchase?", rationale: "Earlier-format discussion response")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [explanation])
    let data = try ExchangeJSON.encode(response)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["answers"] == nil)
    try workspace.stage(data)
    let restored = try ExchangeJSON.decode(ReviewWorkspace.self, from: ExchangeJSON.encode(workspace))
    workspace = restored
    try workspace.receive(data)
    #expect(workspace.staged.count == 1)
    #expect(!explanation.changesClassification(of: record))
    #expect(workspace.discussion(for: record)?.answers.first?.text == explanation.rationale)
}

@Test func forgedDiscussionAnswerCannotAcknowledgeOrAttachToAnotherRecord() throws {
    let record = try discussionRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let answer = DiscussionAnswer(recordID: UUID(), expectedRevision: "1", text: "Wrong record")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    #expect(throws: (any Error).self) { try workspace.receive(ExchangeJSON.encode(response)) }
    #expect(workspace.staged.isEmpty)
    #expect(workspace.pending.count == 1)
}

@Test func resolvingDiscussionPreservesApprovalAndOnlyNewDiscussionContentReopensIt() throws {
    let original = try discussionRecord()
    let approved = try original.applying(ReviewRequest(transactionID: original.id, expectedRevision: original.revision, action: .approve), catalog: .prototype)
    var workspace = ReviewWorkspace()
    workspace.establishBaseline(records: [])
    let resolved = try approved.applying(ReviewRequest(transactionID: approved.id, expectedRevision: approved.revision, action: .resolveDiscussion), catalog: .prototype)
    workspace.resolveDiscussion(for: resolved)
    #expect(resolved.approval == .confirmed)
    #expect(!resolved.discussionRequested)
    #expect(workspace.discussion(for: resolved)?.isResolved == true)
    var value = resolved.draft; value.categoryID = "sample-groceries"
    let classified = try resolved.revising(with: value, expectedRevision: resolved.revision)
    #expect(workspace.discussion(for: classified)?.isResolved == true)
    let reopened = try classified.applying(ReviewRequest(transactionID: classified.id, expectedRevision: classified.revision, action: .discuss), catalog: .prototype)
    #expect(workspace.discussion(for: reopened)?.isResolved == false)
}

@Test func replyingToAnImportedQuestionTracksDirectionEvenAtTheSameSourceRevision() throws {
    let record = try discussionRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: "1", text: "I need more context.", questionForUser: "What was purchased?")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    try workspace.receive(ExchangeJSON.encode(response))
    #expect(workspace.discussion(for: record)?.status == .awaitingYou)
    workspace.discussionReplies = [UserDiscussionReply(recordID: record.id, sentRevision: "1", text: "Fictional household supplies", respondingTo: answer.id)]
    workspace.pending.append(FeedbackEvent(before: record, after: record, kind: "discussion-reply"))
    #expect(workspace.discussion(for: record)?.status == .readyToSend)
}

@Test func discussionDraftAndResolutionSurviveBackupAndOlderWorkspacesDecodeWithoutThem() throws {
    let record = try discussionRecord()
    var workspace = ReviewWorkspace()
    workspace.resolveDiscussion(for: record)
    workspace.discussionDrafts = [record.id.uuidString: DiscussionDraft(recordID: record.id, expectedRevision: "1", text: "Unfinished fictional reply")]
    let backup = FullBackup(records: [record], workspace: workspace)
    let restored = try ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(backup))
    try restored.validate(catalog: .prototype)
    #expect(restored.workspace.discussionDrafts == workspace.discussionDrafts)
    // Restoring unfinished input must make it discoverable even after prior closure.
    #expect(restored.workspace.discussion(for: record)?.isResolved == false)
    #expect(restored.workspace.discussion(for: record)?.status == .draft)
    var finished = restored.workspace
    finished.discussionDrafts = nil
    #expect(finished.discussion(for: record)?.isResolved == true)
    var object = try #require(JSONSerialization.jsonObject(with: ExchangeJSON.encode(workspace)) as? [String: Any])
    for key in ["discussionDrafts", "discussionReplies", "resolvedDiscussions", "discussionClosedRevisions"] { object.removeValue(forKey: key) }
    let older = try ExchangeJSON.decode(ReviewWorkspace.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(older.discussionDrafts == nil && older.resolvedDiscussions == nil)
}

private func chartRecord(_ date: String, _ cents: Int64, treatment: TransactionTreatment = .spending,
                         posting: PostingStatus = .posted) throws -> LedgerTransaction {
    try LedgerTransaction(draft: TransactionDraft(date: TransactionDate(date), payee: "Fictional chart record",
        amount: Money(minorUnits: cents), postingStatus: posting, treatment: treatment, categoryID: "sample-household"))
}

@Test func spendingChartsUseExactTotalsAndLeaveMissingYearMonthsDisconnected() throws {
    let records = try [chartRecord("2025-01-02", 100), chartRecord("2025-01-03", -20, treatment: .refund),
        chartRecord("2025-01-04", 30, posting: .pending), chartRecord("2025-03-02", 200),
        chartRecord("2026-01-02", 400), chartRecord("2026-01-03", -500, treatment: .income),
        chartRecord("2026-01-04", 50, treatment: .payment), chartRecord("2026-05-01", 999, posting: .unresolved)]
    let data = try SpendingCharts(records: records, catalog: .prototype)
    #expect(data.totals.posted.minorUnits == 680 && data.totals.pending.minorUnits == 30)
    #expect(data.categories[0].totals.posted.minorUnits == 680)
    #expect(data.months.map(\.id) == ["2025-01", "2025-03", "2026-01"])
    #expect(data.months[0].segment != data.months[1].segment)
    #expect(data.months[1].segment != data.months[2].segment)
    #expect(data.years == [2025, 2026])
}

@Test func adjacentChartMonthsShareALineAndNegativeRefundsAreNotClampedOrRounded() throws {
    let records = try [chartRecord("2026-01-01", -1200, treatment: .refund), chartRecord("2026-02-01", 300)]
    let data = try SpendingCharts(records: records, catalog: .prototype)
    #expect(data.months[0].segment == data.months[1].segment)
    #expect(data.months[0].posted.minorUnits == -1200)
    #expect(data.totals.posted.minorUnits == -900)
    #expect(throws: (any Error).self) {
        try SpendingCharts(records: [chartRecord("2026-01-01", Int64.max), chartRecord("2026-01-02", 1)], catalog: .prototype)
    }
}

@Test func chartExamplesAreStableFictionalAndNeverDatedAfterTheChosenDay() throws {
    let today = try TransactionDate("2026-10-24")
    let records = try SyntheticSpendingExamples.make(asOf: today)
    let repeated = try SyntheticSpendingExamples.make(asOf: today)
    #expect(records.count == 66)
    #expect(records == repeated)
    #expect(Set(records.map(\.id)).count == records.count)
    #expect(records.allSatisfy { $0.draft.date <= today && $0.classificationProvenance.category == .assistant })
    #expect(try SpendingCharts(records: records, catalog: .prototype).years == [2025, 2026])
}

@Test func classificationProposalAfterResolutionDoesNotReopenAnUnrelatedDiscussion() throws {
    let record = try discussionRecord()
    let resolved = try record.applying(ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: .resolveDiscussion), catalog: .prototype)
    var workspace = ReviewWorkspace()
    workspace.resolveDiscussion(for: resolved)
    let packet = try workspace.prepare(records: [resolved], catalog: .prototype, mode: .fullHistory)
    #expect(packet.manifest.discussionRecordIDs?.isEmpty == true)
    let proposal = ClassificationProposal(recordID: resolved.id, expectedRevision: String(resolved.revision),
        categoryID: "sample-groceries", rationale: "A classification change without a discussion reply")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [proposal])
    try workspace.receive(ExchangeJSON.encode(response))
    #expect(workspace.discussion(for: resolved)?.isResolved == true)
    #expect(workspace.discussion(for: resolved)?.answers.isEmpty == true)
}

@Test func aNewUnfinishedQuestionIsDiscoverableButItsDraftIsNeverSentForReview() throws {
    let record = try chartRecord("2026-10-01", 1234)
    var workspace = ReviewWorkspace()
    workspace.establishBaseline(records: [])
    let text = "PRIVATE_SYNTHETIC_UNSAVED_QUESTION"
    workspace.discussionDrafts = [record.id.uuidString: DiscussionDraft(recordID: record.id, expectedRevision: "1", text: text)]
    #expect(workspace.discussion(for: record)?.status == .draft)
    #expect(throws: (any Error).self) { try workspace.prepare(records: [record], catalog: .prototype, mode: .pending) }
    let full = try workspace.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    let encoded = try ExchangeJSON.encode(full)
    #expect(!String(decoding: encoded, as: UTF8.self).contains(text))
}

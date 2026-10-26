import Foundation
import Testing
@testable import FinTrackCore

@Test func knowledgeFreshnessAllowsSequentialResponseProposalsButRejectsInterveningEdits() throws {
    var state = ReviewWorkspace()
    let response = ReviewResponse(packetID: UUID(), knowledgeVersion: state.knowledgeVersion)
    try state.validateKnowledgeFreshness(response)
    // Accepting the first proposal changes the version, retaining its lineage.
    state.knowledgeVersion = UUID()
    state.knowledgeResponseID = response.id
    try state.validateKnowledgeFreshness(response)
    // A manual edit clears lineage; another response replaces it.
    state.knowledgeResponseID = nil
    #expect(throws: LedgerError.staleRevision) { try state.validateKnowledgeFreshness(response) }
    state.knowledgeResponseID = UUID()
    #expect(throws: LedgerError.staleRevision) { try state.validateKnowledgeFreshness(response) }
}

@Test func pendingFeedbackSurvivesRestartAndOldReceiptPreservesNewEdits() throws {
    let original = try SyntheticTransactions.make()[0]
    var state = ReviewWorkspace()
    let first = try state.prepare(records: [original], catalog: .prototype, mode: .pending)
    #expect(first.feedback.count == 1)
    #expect(first.feedback[0].kind == "initial-baseline")
    var draft = original.draft; draft.notes = "Synthetic new question"
    let updated = try original.revising(with: draft, expectedRevision: original.revision)
    let event = FeedbackEvent(before: original, after: updated)
    state.pending.append(event)
    state = try ExchangeJSON.decode(ReviewWorkspace.self, from: ExchangeJSON.encode(state))
    let response = ReviewResponse(packetID: first.manifest.id, knowledgeVersion: first.manifest.knowledgeVersion,
        acknowledgedOperationIDs: first.manifest.operationIDs)
    try state.acknowledge(response)
    #expect(state.pending.map(\.id) == [event.id])
    try state.acknowledge(response)
    #expect(state.pending.map(\.id) == [event.id])
}

@Test func routineIncludesOnlyPendingContextButFullHistoryIncludesEveryRecord() throws {
    // Remove the fixture's pre-existing assistant questions; open questions have
    // separate coverage below and intentionally remain eligible after receipts.
    let records = try SyntheticTransactions.make().map {
        try LedgerTransaction(id: $0.id, createdAt: $0.createdAt, draft: $0.draft)
    }
    var state = ReviewWorkspace()
    state.establishBaseline(records: [])
    state.pending.append(FeedbackEvent(before: records[0], after: records[0]))
    let pending = try state.prepare(records: records, catalog: .prototype, mode: .pending)
    #expect(pending.snapshot?.transactions.map(\.transactionID) == [records[0].id])
    #expect(pending.snapshot?.options.includeUserContext == true)
    let full = try state.prepare(records: records, catalog: .prototype, mode: .fullHistory)
    #expect(full.snapshot?.transactions.count == records.count)
    #expect(state.pending.count == 1) // preparation cannot acknowledge anything
    #expect(full.returnTemplate.packetID == full.manifest.id)
}

@Test func knowledgeOnlyPacketsWorkWithoutFinancialRecords() throws {
    var state = ReviewWorkspace()
    state.pending.append(FeedbackEvent(kind: "knowledge-edit", detail: "Synthetic rule"))
    state.knowledge = [KnowledgeRule(text: "Ask about mixed-use shops.")]
    let packet = try state.prepare(records: [], catalog: .prototype, mode: .pending)
    #expect(packet.snapshot == nil)
    #expect(packet.knowledge.count == 1)
    #expect(packet.feedback.count == 1)
}

@Test func responseRejectsWrongPacketUnknownOperationsAndOutOfScopeRecords() throws {
    let records = try SyntheticTransactions.make()
    var state = ReviewWorkspace()
    let packet = try state.prepare(records: [records[0]], catalog: .prototype, mode: .pending)
    #expect(throws: (any Error).self) {
        try state.validate(ReviewResponse(packetID: UUID(), knowledgeVersion: packet.manifest.knowledgeVersion))
    }
    #expect(throws: (any Error).self) {
        try state.validate(ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
            acknowledgedOperationIDs: [UUID()]))
    }
    #expect(throws: (any Error).self) {
        try state.validate(ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
            proposals: [.init(recordID: records[1].id, expectedRevision: String(records[1].revision), rationale: "Outside scope")]))
    }
    #expect(state.pending.count == 1)
}

@Test func incomingRetriesAreIdempotentAndReusedIDsOrWritableUnknownFieldsFail() throws {
    let record = try SyntheticTransactions.make()[0]
    var state = ReviewWorkspace()
    let packet = try state.prepare(records: [record], catalog: .prototype, mode: .pending)
    let proposal = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision), categoryID: "sample-household", rationale: "Synthetic")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [proposal])
    let data = try ExchangeJSON.encode(response)
    try state.stage(data); try state.stage(data)
    #expect(state.staged.count == 1)
    let reused = ReviewResponse(id: response.id, packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, summary: "Changed")
    #expect(throws: (any Error).self) { try state.stage(ExchangeJSON.encode(reused)) }
    let copied = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [proposal])
    #expect(throws: (any Error).self) { try state.stage(ExchangeJSON.encode(copied)) }
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var proposals = try #require(object["proposals"] as? [[String: Any]])
    proposals[0]["approval"] = "confirmed"; object["proposals"] = proposals
    #expect(throws: (any Error).self) { try state.stage(JSONSerialization.data(withJSONObject: object)) }
}

@Test func acceptedSuggestionPreservesUserTextReopensChangedClassificationAndRejectsStaleRevision() throws {
    var draft = try SyntheticTransactions.make()[0].draft
    draft.categoryID = "sample-groceries"; draft.notes = "Synthetic user note"
    let record = try LedgerTransaction(draft: draft, approval: .confirmed, classificationProvenance: .manual(draft))
    let proposal = ClassificationProposal(recordID: record.id, expectedRevision: "1",
        categoryID: "sample-household", tags: ["Synthetic"], question: "Synthetic question?", rationale: "Synthetic rationale")
    let updated = try record.applyingSuggestion(proposal, catalog: .prototype)
    #expect(updated.approval == .unreviewed)
    #expect(updated.draft.notes == draft.notes)
    #expect(updated.draft.amount == draft.amount)
    #expect(updated.assistantContext.question == "Synthetic question?")
    #expect(updated.classificationProvenance.category == .assistant)
    #expect(updated.classificationProvenance.tags["Synthetic"] == .assistant)
    #expect(throws: LedgerError.staleRevision) { try updated.applyingSuggestion(proposal, catalog: .prototype) }
}

@Test func weeklyContractRejectsDuplicateSourceIDsAndInexactAmounts() throws {
    let row = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "synthetic-001"),
        date: "2026-10-01", merchant: "Synthetic Shop", amountMinorUnits: "1234", categoryID: "sample-household")
    var state = ReviewWorkspace()
    #expect(throws: (any Error).self) { try state.stage(ExchangeJSON.encode(WeeklyBatch(coverage: "Synthetic", transactions: [row, row]))) }
    for invalid in ["12.34", "1e3", "001", "9223372036854775808"] {
        let bad = WeeklyTransaction(identity: row.identity, date: row.date, merchant: row.merchant, amountMinorUnits: invalid)
        #expect(throws: (any Error).self) { try bad.draft() }
    }
    let precise = WeeklyTransaction(identity: row.identity, date: row.date, merchant: row.merchant,
        amountMinorUnits: "9007199254740993")
    #expect(try precise.draft().amount.minorUnits == 9_007_199_254_740_993)
}

@Test func completeBackupRoundTripIncludesPendingWorkRulesAndSourceEvidence() throws {
    let record = try SyntheticTransactions.make()[0]
    var state = ReviewWorkspace()
    _ = try state.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    state.knowledge = [KnowledgeRule(text: "Synthetic guidance")]
    let backup = FullBackup(records: [record], workspace: state)
    let restored = try ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(backup))
    try restored.validate(catalog: .prototype)
    #expect(restored.records == [record])
    #expect(restored.workspace.pending == state.pending)
    #expect(restored.workspace.knowledge == state.knowledge)
    #expect(restored.workspace.manifests[0].id == state.manifests[0].id)
    #expect(throws: (any Error).self) { try FullBackup(records: [record, record], workspace: state).validate(catalog: .prototype) }
}

@Test func cloudConfirmationKeepsLastGoodBackupAndCannotCoverLaterEdits() throws {
    let firstGeneration = UUID(), secondGeneration = UUID()
    var progress = BackupProgress()
    let first = progress.begin(generation: firstGeneration)
    #expect(!progress.isCurrent(generation: firstGeneration))
    #expect(progress.confirm(id: UUID()) == nil)
    #expect(progress.candidate == first)
    progress = try ExchangeJSON.decode(BackupProgress.self, from: ExchangeJSON.encode(progress))
    #expect(progress.confirm(id: first.id) == nil)
    #expect(progress.isCurrent(generation: firstGeneration))
    let next = progress.begin(generation: secondGeneration)
    #expect(progress.confirmed == first)
    #expect(progress.begin(generation: UUID()) == next) // cannot overwrite an in-flight file
    #expect(progress.confirm(id: next.id) == first) // only now may adapter remove old cloud file
    #expect(progress.isCurrent(generation: secondGeneration))
    #expect(!progress.isCurrent(generation: UUID()))
}

@Test func acknowledgedButUnresolvedDiscussionStaysInTheNextReview() throws {
    var draft = try SyntheticTransactions.make()[0].draft
    draft.notes = "Synthetic question about this purchase"
    let record = try LedgerTransaction(draft: draft, discussionRequested: true)
    var state = ReviewWorkspace()
    let first = try state.prepare(records: [record], catalog: .prototype, mode: .pending)
    let response = ReviewResponse(packetID: first.manifest.id, knowledgeVersion: first.manifest.knowledgeVersion,
        acknowledgedOperationIDs: first.manifest.operationIDs)
    try state.acknowledge(response)
    #expect(state.pending.isEmpty)
    let next = try state.prepare(records: [record], catalog: .prototype, mode: .pending)
    #expect(next.snapshot?.transactions.map(\.transactionID) == [record.id])
    #expect(next.feedback.isEmpty)
}

@Test func feedbackIncludesExactPriorAndSavedClassificationAndMoney() throws {
    let original = try SyntheticTransactions.make()[0]
    var value = original.draft
    value.categoryID = "sample-household"
    value.amount = Money(minorUnits: 9_007_199_254_740_993)
    let updated = try original.revising(with: value, expectedRevision: original.revision)
    let feedback = FeedbackEvent(before: original, after: updated)
    #expect(feedback.priorValues["categoryID"] == (original.draft.categoryID ?? ""))
    #expect(feedback.savedValues["categoryID"] == "sample-household")
    #expect(feedback.savedValues["amountMinorUnits"] == "9007199254740993")
}

@Test func unrelatedEditorChangesPreserveImportedTagsWithDelimitersAndWhitespace() throws {
    var draft = try SyntheticTransactions.make()[0].draft
    draft.tags = ["Synthetic; one tag", " preserved spacing "]
    var input = TransactionInput(draft: draft)
    input.notes = "Synthetic note edit only"
    input = try ExchangeJSON.decode(TransactionInput.self, from: ExchangeJSON.encode(input))
    #expect(try input.value().tags == draft.tags)
    input.tagsText = "Explicit replacement; Second tag"
    #expect(try input.value().tags == ["Explicit replacement", "Second tag"])
}

@Test func autosavesCoalesceWithoutChangingPreparedOperationBoundaries() throws {
    let original = try SyntheticTransactions.make()[0]
    var state = ReviewWorkspace()
    state.baselineEstablished = true
    var draft = original.draft; draft.notes = "First synthetic note"
    let first = try original.revising(with: draft, expectedRevision: original.revision)
    state.recordUserChange(before: original, after: first)
    let firstID = try #require(state.pending.first?.id)
    draft.notes = "Final synthetic note"
    let second = try first.revising(with: draft, expectedRevision: first.revision)
    state.recordUserChange(before: first, after: second)
    #expect(state.pending.count == 1)
    #expect(state.pending[0].id == firstID)
    #expect(state.pending[0].priorValues["userNote"] == original.draft.notes)
    #expect(state.pending[0].savedValues["userNote"] == "Final synthetic note")
    let packet = try state.prepare(records: [second], catalog: .prototype, mode: .pending)
    draft.notes = "Edited during discussion"
    let third = try second.revising(with: draft, expectedRevision: second.revision)
    state.recordUserChange(before: second, after: third)
    #expect(state.pending.count == 2)
    try state.acknowledge(ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs))
    #expect(state.pending.count == 1)
    #expect(state.pending[0].savedValues["userNote"] == "Edited during discussion")
}

@Test func unsentRevertedEditDisappearsButNewManualRecordRemains() throws {
    let original = try SyntheticTransactions.make()[0]
    var state = ReviewWorkspace(); state.baselineEstablished = true
    var draft = original.draft; draft.notes = "Temporary synthetic edit"
    let first = try original.revising(with: draft, expectedRevision: original.revision)
    state.recordUserChange(before: original, after: first)
    let reverted = try first.revising(with: original.draft, expectedRevision: first.revision)
    state.recordUserChange(before: first, after: reverted)
    #expect(state.pending.isEmpty)
    state.recordUserChange(before: nil, after: original)
    state.recordUserChange(before: original, after: first)
    #expect(state.pending.count == 1)
    #expect(state.pending[0].kind == "manual-addition")
    #expect(state.pending[0].savedValues["userNote"] == "Temporary synthetic edit")
}

import Foundation
import SwiftData
import Testing
import FinTrackCore
@testable import FinTrackPersistence

private enum ExchangeWriteFailure: Error { case disk }

@MainActor
@Test func plainDiscussionRepliesCannotAcquireFinancialProposalDecisions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    let explanation = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        rationale: "Fictional legacy explanation without an edit")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [explanation])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    for accept in [true, false] {
        #expect(throws: (any Error).self) { try repository.decideProposal(fileID: response.id, proposalID: explanation.id, accept: accept) }
    }
    #expect(try repository.fetchAll().first == record)
    #expect(try repository.workspace().decidedProposals.isEmpty)
    #expect(try repository.workspace().discussion(for: record)?.answers.first?.text == explanation.rationale)
}

@MainActor
@Test func futureDiscussionDraftIsRejectedButStaleDraftRemainsRecoverable() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    #expect(throws: LedgerError.staleRevision) {
        try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: record.revision + 1, text: "Fictional invalid revision")
    }
    #expect(try repository.workspace().discussionDrafts == nil)
    var value = record.draft; value.notes = "Fictional new note"
    _ = try repository.update(id: record.id, expectedRevision: record.revision, draft: value)
    try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: record.revision, text: "Fictional retained stale draft")
    #expect(throws: LedgerError.staleRevision) {
        try repository.replyToDiscussion(recordID: record.id, expectedRevision: record.revision, text: "Fictional retained stale draft")
    }
    #expect(try repository.workspace().discussionDrafts?[record.id.uuidString]?.expectedRevision == String(record.revision))
}

@MainActor
@Test func discussionReplyDraftReopensAndReplyAndResolutionPreserveApproval() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let original = try SyntheticTransactions.make()[0]
    try repository.insert(original)
    let approved = try repository.perform(ReviewRequest(transactionID: original.id, expectedRevision: original.revision, action: .approve))
    try repository.saveDiscussionDraft(recordID: original.id, expectedRevision: approved.revision, text: "Fictional reply in progress")
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.workspace().discussionDrafts?[original.id.uuidString]?.text == "Fictional reply in progress")
    try reopened.replyToDiscussion(recordID: original.id, expectedRevision: approved.revision, text: "Fictional household supplies")
    let replied = try #require(reopened.fetchAll().first)
    #expect(replied.approval == .confirmed)
    #expect(try reopened.workspace().discussionDrafts?[original.id.uuidString] == nil)
    #expect(try reopened.workspace().discussionReplies?.count == 1)
    try reopened.resolveDiscussion(recordID: replied.id, expectedRevision: replied.revision)
    let resolved = try #require(reopened.fetchAll().first)
    #expect(resolved.approval == .confirmed)
    #expect(try reopened.workspace().discussion(for: resolved)?.isResolved == true)
}

@MainActor
@Test func failedDiscussionReplyPreservesDraftAndDoesNotAppendHalfAConversation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw ExchangeWriteFailure.disk }; try context.save()
    })
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: record.revision, text: "Fictional draft")
    fail = true
    #expect(throws: ExchangeWriteFailure.self) {
        try repository.replyToDiscussion(recordID: record.id, expectedRevision: record.revision, text: "Fictional draft")
    }
    #expect(try repository.fetchAll().first == record)
    #expect(try repository.workspace().discussionReplies == nil)
    #expect(try repository.workspace().discussionDrafts?[record.id.uuidString]?.text == "Fictional draft")
}

@MainActor
@Test func importedAnswerAcknowledgesOnlyItsPacketWithoutApplyingClassification() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    var value = record.draft; value.notes = "Fictional newer edit"
    let newer = try repository.update(id: record.id, expectedRevision: record.revision, draft: value)
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: String(record.revision), text: "Fictional answer")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    try repository.stageIncoming(ExchangeJSON.encode(response))
    #expect(try repository.fetchAll().first == newer)
    #expect(try repository.workspace().processedFiles.isEmpty)
    #expect(try repository.workspace().importReceipts?.contains { $0.id == response.id } == true)
    #expect(try repository.workspace().pending.count == 1)
    #expect(try repository.workspace().discussion(for: newer)?.answers == [answer])
}

@MainActor
@Test func chartExamplesAppendWithoutReplacingExistingEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let today = try TransactionDate("2026-10-24")
    #expect(try repository.addSyntheticSpendingExamples(asOf: today) == 66)
    let first = try #require(repository.fetchAll().first)
    var draft = first.draft; draft.notes = "Fictional saved edit"
    let edited = try repository.update(id: first.id, expectedRevision: first.revision, draft: draft)
    #expect(try repository.addSyntheticSpendingExamples(asOf: today) == 0)
    #expect(try repository.fetchAll().first(where: { $0.id == first.id }) == edited)
    #expect(try repository.fetchAll().count == 66)
}

@MainActor
@Test func ledgerAndFeedbackCommitOrRollbackTogetherIncludingDrafts() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url, commit: { context in
        if fail { throw ExchangeWriteFailure.disk }
        try context.save()
    })
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let before = try repository.workspace()
    try repository.saveDraft(id: record.id, data: Data("synthetic draft".utf8))
    var value = record.draft; value.notes = "Synthetic correction"
    fail = true
    #expect(throws: ExchangeWriteFailure.self) { try repository.update(id: record.id, expectedRevision: record.revision, draft: value) }
    #expect(try repository.fetchAll().first == record)
    #expect(try repository.workspace().pending == before.pending)
    #expect(try repository.workspace().drafts[record.id.uuidString] != nil)
    fail = false
    _ = try repository.update(id: record.id, expectedRevision: record.revision, draft: value)
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.workspace().pending.last?.savedValues["userNote"] == "Synthetic correction")
    #expect(try reopened.workspace().drafts[record.id.uuidString] == nil)
}

@MainActor
@Test func responseReceiptsAndDecisionsAreDurableIdempotentAndProtectNewerEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    let proposal = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        categoryID: "sample-household", rationale: "Synthetic suggestion")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, proposals: [proposal])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    var draft = record.draft; draft.notes = "Synthetic newer note"
    _ = try repository.update(id: record.id, expectedRevision: record.revision, draft: draft)
    try repository.acknowledgeResponse(fileID: response.id)
    try repository.acknowledgeResponse(fileID: response.id)
    #expect(try repository.workspace().pending.count == 1)
    #expect(throws: LedgerError.staleRevision) { try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: true) }
    try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: false)
    let count = try repository.workspace().pending.count
    try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: false)
    #expect(try repository.workspace().pending.count == count)
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.workspace().importReceipts?.contains { $0.decisionIDs?.contains(proposal.id) == true } == true)
    #expect(try reopened.fetchAll().first?.draft.notes == "Synthetic newer note")
}

@MainActor
@Test func acceptingSuggestionDoesNotEchoAsManualCorrectionAndRollbackRetainsProposal() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw ExchangeWriteFailure.disk }; try context.save()
    })
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    let proposal = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        categoryID: "sample-household", rationale: "Synthetic")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, proposals: [proposal])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    fail = true
    #expect(throws: ExchangeWriteFailure.self) { try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: true) }
    #expect(try repository.fetchAll().first == record)
    #expect(try !repository.workspace().decidedProposals.contains(proposal.id))
    #expect(try repository.workspace().staged.contains { $0.id == response.id })
    #expect(try repository.workspace().importReceipts?.contains { $0.id == response.id } != true)
    fail = false
    try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: true)
    #expect(try repository.fetchAll().first?.classificationProvenance.category == .assistant)
    #expect(try repository.workspace().pending.last?.kind == "proposal-decision")
    let change = try #require(repository.workspace().pending.first { $0.kind == "accepted-assistant-change" })
    #expect(change.recordID == record.id && change.savedValues["categoryID"] == "sample-household")
    let next = try repository.prepareReview(mode: .pending)
    #expect(next.snapshot?.transactions.first { $0.transactionID == record.id }?.categoryID == "sample-household")
}

@MainActor
@Test func bankIdentityDedupAndExplicitPendingToPostedReconciliationPreserveUserFields() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let pending = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "synthetic-pending"),
        date: "2026-10-10", merchant: "Synthetic Cafe", amountMinorUnits: "1000", postingStatus: .pending,
        categoryID: "sample-household")
    let batch = WeeklyBatch(coverage: "Synthetic source only", transactions: [pending])
    try repository.stageIncoming(ExchangeJSON.encode(batch))
    try repository.acceptWeekly(fileID: batch.id, identity: pending.identity)
    try repository.acceptWeekly(fileID: batch.id, identity: pending.identity)
    #expect(try repository.fetchAll().count == 1)
    let first = try #require(repository.fetchAll().first)
    var edit = first.draft; edit.notes = "Synthetic user note"; edit.tags = ["User tag"]
    let edited = try repository.update(id: first.id, expectedRevision: first.revision, draft: edit)
    let posted = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "synthetic-posted"),
        date: "2026-10-11", merchant: "Synthetic Cafe", amountMinorUnits: "1200", categoryID: "sample-groceries")
    let next = WeeklyBatch(coverage: "Synthetic posted update", transactions: [posted])
    try repository.stageIncoming(ExchangeJSON.encode(next))
    try repository.acceptWeekly(fileID: next.id, identity: posted.identity, matchingRecordID: edited.id, expectedRevision: edited.revision)
    let saved = try #require(repository.fetchAll().first)
    #expect(try repository.fetchAll().count == 1)
    #expect(saved.draft.amount.minorUnits == 1200)
    #expect(saved.draft.notes == "Synthetic user note")
    #expect(saved.draft.tags == ["User tag"])
    #expect(saved.draft.categoryID == "sample-household")
    #expect(try repository.workspace().sourceLinks.count == 2)
    #expect(try repository.workspace().sourceLinks[0].original == pending)
}

@MainActor
@Test func possibleManualDuplicateRequiresExplicitChoiceAndFailedIntakeIsAtomic() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw ExchangeWriteFailure.disk }; try context.save()
    })
    let original = try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-10-10"),
        payee: "Synthetic Shop", amount: Money(minorUnits: 1000), treatment: .spending))
    try repository.insert(original)
    let incoming = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "synthetic-duplicate"),
        date: "2026-10-10", merchant: "Synthetic Shop", amountMinorUnits: "1000")
    let batch = WeeklyBatch(coverage: "Synthetic", transactions: [incoming])
    try repository.stageIncoming(ExchangeJSON.encode(batch))
    #expect(throws: (any Error).self) { try repository.acceptWeekly(fileID: batch.id, identity: incoming.identity) }
    fail = true
    #expect(throws: ExchangeWriteFailure.self) {
        try repository.acceptWeekly(fileID: batch.id, identity: incoming.identity, allowSeparate: true)
    }
    #expect(try repository.fetchAll().count == 1)
    #expect(try repository.workspace().sourceLinks.isEmpty)
    fail = false
    try repository.acceptWeekly(fileID: batch.id, identity: incoming.identity, allowSeparate: true)
    #expect(try repository.fetchAll().count == 2)
}

@MainActor
@Test func manualKnowledgeEditInvalidatesRemainingSuggestionsFromOldResponse() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let packet = try repository.prepareReview(mode: .fullHistory)
    let p1 = KnowledgeProposal(text: "Synthetic rule one", rationale: "Synthetic")
    let p2 = KnowledgeProposal(text: "Synthetic rule two", rationale: "Synthetic")
    let p3 = KnowledgeProposal(text: "Synthetic rule three", rationale: "Synthetic")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        knowledgeProposals: [p1, p2, p3])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    try repository.decideProposal(fileID: response.id, proposalID: p1.id, accept: true)
    try repository.decideProposal(fileID: response.id, proposalID: p2.id, accept: true)
    #expect(try repository.workspace().knowledge.count == 2)
    var rules = try repository.workspace().knowledge
    rules[0].text = "Synthetic manual correction"
    try repository.saveKnowledge(rules)
    #expect(throws: LedgerError.staleRevision) { try repository.decideProposal(fileID: response.id, proposalID: p3.id, accept: true) }
}

@MainActor
@Test func fullRestorePreservesIDsAndExchangeStateAndRollsBackOnFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw ExchangeWriteFailure.disk }; try context.save()
    })
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    _ = try repository.prepareReview(mode: .fullHistory)
    try repository.saveDraft(id: record.id, data: Data("synthetic raw draft".utf8))
    let backup = try repository.backup()
    var draft = record.draft; draft.notes = "Synthetic later change"
    let newer = try repository.update(id: record.id, expectedRevision: record.revision, draft: draft)
    fail = true
    #expect(throws: ExchangeWriteFailure.self) { try repository.restore(backup) }
    #expect(try repository.fetchAll().first == newer)
    fail = false
    try repository.restore(backup)
    #expect(try repository.fetchAll() == backup.records)
    #expect(try repository.workspace().pending == backup.workspace.pending)
    #expect(try repository.workspace().drafts == backup.workspace.drafts)
    #expect(try repository.workspace().manifests.first?.id == backup.workspace.manifests.first?.id)
}

@MainActor
@Test func schemaV2MigratesToWorkspaceWithoutChangingExistingRecords() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("test.store")
    let record = try SyntheticTransactions.make()[0]
    try autoreleasepool {
        let schema = Schema(versionedSchema: LedgerSchemaV2.self)
        let config = ModelConfiguration("FinTrack", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        context.insert(try LedgerSchemaV2.StoredTransaction(record))
        try context.save()
    }
    try Data(Money.amountSignConvention.utf8).write(to: url.appendingPathExtension("amount-sign"))
    let repository = try LocalTransactionRepository(storeURL: url)
    #expect(try repository.fetchAll() == [record])
    try repository.migrateDrafts([:])
    let packet = try repository.prepareReview(mode: .pending)
    #expect(packet.feedback.count == 1)
    #expect(packet.snapshot?.transactions.first?.transactionID == record.id)
}

@MainActor
@Test func newWeeklyBatchAddsAtomicallyAndCanBeRetriedWithoutDuplicates() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw ExchangeWriteFailure.disk }; try context.save()
    })
    let rows = ["synthetic-a", "synthetic-b"].map {
        WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: $0),
            date: "2026-10-10", merchant: "Synthetic Shop", amountMinorUnits: "1000")
    }
    let batch = WeeklyBatch(coverage: "Two distinct source purchases", transactions: rows)
    try repository.stageIncoming(ExchangeJSON.encode(batch))
    fail = true
    #expect(throws: ExchangeWriteFailure.self) { try repository.acceptNewWeeklyBatch(fileID: batch.id) }
    #expect(try repository.fetchAll().isEmpty)
    #expect(try repository.workspace().sourceLinks.isEmpty)
    fail = false
    #expect(try repository.acceptNewWeeklyBatch(fileID: batch.id) == 2)
    #expect(try repository.acceptNewWeeklyBatch(fileID: batch.id) == 0)
    #expect(try repository.fetchAll().count == 2) // same facts, different genuine IDs
}

import Foundation
import Testing
@testable import FinTrackCore

private func lifecycleRecord(_ note: String = "Fictional category question") throws -> LedgerTransaction {
    try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-03-01"), payee: "Fictional Market",
        amount: Money(minorUnits: 1000), notes: note, treatment: .spending, categoryID: "sample-household"), discussionRequested: true)
}

@Test func portableDigestsMatchStandardSHA256Vectors() {
    #expect(ContentDigest.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(ContentDigest.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func completedReplyFileCompactsWhileOpenAnswerSurvivesAndApprovalThenRemovesIt() throws {
    let original = try lifecycleRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [original], catalog: .prototype, mode: .pending)
    let answer = DiscussionAnswer(recordID: original.id, expectedRevision: "1", text: "SYNTHETIC_RESOLVABLE_ANSWER")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    let bytes = try ExchangeJSON.encode(response)
    try workspace.receive(bytes); try workspace.compactCompletedExchanges(records: [original])
    #expect(workspace.staged.isEmpty && workspace.processedFiles.isEmpty)
    #expect(workspace.discussionAnswers == [answer])
    #expect(workspace.discussion(for: original)?.isResolved == false)
    #expect(workspace.importReceipts?.first?.id == response.id)
    #expect(workspace.retiredPacketIDs?.contains(packet.manifest.id) == true)
    try workspace.receive(bytes)
    #expect(workspace.importReceipts?.count == 1 && workspace.pending.isEmpty)
    let approved = try original.applying(.init(transactionID: original.id, expectedRevision: 1, action: .approve), catalog: .prototype)
    workspace.closeDiscussion(for: approved)
    workspace.recordUserChange(before: original, after: approved, kind: "approve")
    try workspace.compactCompletedExchanges(records: [approved])
    #expect(workspace.discussionAnswers?.isEmpty == true)
    #expect(workspace.discussion(for: approved)?.isResolved == true)
    #expect(!String(decoding: try ExchangeJSON.encode(workspace), as: UTF8.self).contains("SYNTHETIC_RESOLVABLE_ANSWER"))
    #expect(workspace.pending.count == 1)
}

@Test func compactReceiptRejectsChangedFileAndReusedItemIDsAndLateNewResponses() throws {
    let record = try lifecycleRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: "1", text: "Fictional reply")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    try workspace.receive(ExchangeJSON.encode(response)); try workspace.compactCompletedExchanges(records: [record])
    var object = try #require(JSONSerialization.jsonObject(with: ExchangeJSON.encode(response)) as? [String: Any])
    object["summary"] = "Changed content under an old ID"
    #expect(throws: (any Error).self) { try workspace.receive(JSONSerialization.data(withJSONObject: object)) }
    let late = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion)
    #expect(throws: (any Error).self) { try workspace.receive(ExchangeJSON.encode(late)) }
    let next = try workspace.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    let reused = ReviewResponse(packetID: next.manifest.id, knowledgeVersion: next.manifest.knowledgeVersion, answers: [answer])
    #expect(throws: (any Error).self) { try workspace.receive(ExchangeJSON.encode(reused)) }
}

@Test func approvalPreservesUnsentCorrectionsAndANewDiscussionCanStartAfterwards() throws {
    let original = try lifecycleRecord()
    var workspace = ReviewWorkspace(); workspace.establishBaseline(records: [])
    var value = original.draft; value.categoryID = "sample-groceries"
    let corrected = try original.revising(with: value, expectedRevision: 1)
    workspace.recordUserChange(before: original, after: corrected)
    let approved = try corrected.applying(.init(transactionID: corrected.id, expectedRevision: 2, action: .approve), catalog: .prototype)
    workspace.closeDiscussion(for: approved)
    try workspace.compactCompletedExchanges(records: [approved])
    #expect(workspace.pending.first?.savedValues["categoryID"] == "sample-groceries")
    #expect(workspace.discussion(for: approved)?.isResolved == true)
    let reopened = try approved.applying(.init(transactionID: approved.id, expectedRevision: 3, action: .discuss), catalog: .prototype)
    #expect(workspace.discussion(for: reopened)?.isResolved == false)
}

@Test func unsettledProposalsRemainUntilDecisionButApprovalSettlesOlderClassificationOnly() throws {
    let record = try lifecycleRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let proposal = ClassificationProposal(recordID: record.id, expectedRevision: "1", categoryID: "sample-groceries", rationale: "Fictional suggestion")
    let knowledge = KnowledgeProposal(text: "Fictional scoped rule", rationale: "Fictional reason")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        proposals: [proposal], knowledgeProposals: [knowledge])
    try workspace.receive(ExchangeJSON.encode(response)); try workspace.compactCompletedExchanges(records: [record])
    #expect(workspace.staged.count == 1)
    let approved = try record.applying(.init(transactionID: record.id, expectedRevision: 1, action: .approve), catalog: .prototype)
    workspace.closeDiscussion(for: approved); try workspace.compactCompletedExchanges(records: [approved])
    #expect(workspace.staged.count == 1 && workspace.decidedProposals.contains(proposal.id))
    #expect(!workspace.decidedProposals.contains(knowledge.id))
}

@Test func explicitDismissalDropsRawFileWithoutAcknowledgingPendingUserWork() throws {
    let record = try lifecycleRecord()
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        answers: [.init(recordID: record.id, expectedRevision: "1", text: "Fictional open answer")])
    try workspace.receive(ExchangeJSON.encode(response))
    let pending = workspace.pending
    try workspace.dismissIncoming(fileID: response.id, records: [record])
    #expect(workspace.staged.isEmpty && workspace.pending == pending)
    #expect(workspace.importReceipts?.first?.disposition == "dismissed")
    #expect(workspace.discussionAnswers?.count == 1)
}

@Test func oldManifestCanRetireWithoutDeletingItsUnacknowledgedFeedback() throws {
    let record = try lifecycleRecord()
    var workspace = ReviewWorkspace()
    let then = Date(timeIntervalSinceReferenceDate: 1000)
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending, at: then)
    let pending = workspace.pending
    try workspace.compactCompletedExchanges(records: [record], at: then.addingTimeInterval(91 * 86_400))
    #expect(workspace.manifests.isEmpty && workspace.pending == pending)
    #expect(workspace.retiredPacketIDs?.contains(packet.manifest.id) == true)
}

@Test func intakeCandidatesIncludePostedVariantsOfLinkedOrSameBatchPurchases() throws {
    let record = try lifecycleRecord()
    let incoming = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "new-posted-id"),
        date: "2026-03-03", merchant: "FICTIONAL MARKET 123", amountMinorUnits: "1200")
    #expect(try IntakeMatching.candidates(for: incoming, in: [record]) == [record.id])
    let distant = WeeklyTransaction(identity: incoming.identity, date: "2026-04-03", merchant: incoming.merchant, amountMinorUnits: "1200")
    #expect(try IntakeMatching.candidates(for: distant, in: [record]).isEmpty)
}

@Test func archiveRoundTripPreservesLedgerDraftsVisibilityAndCompactReceipts() throws {
    let record = try lifecycleRecord()
    var workspace = ReviewWorkspace(); workspace.summaryVisibility = .init(recordIDs: [record.id])
    workspace.drafts[UUID().uuidString] = Data("Synthetic raw editor input".utf8)
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .pending)
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion)
    try workspace.receive(ExchangeJSON.encode(response)); try workspace.compactCompletedExchanges(records: [record])
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("test.fintrack")
    try BackupArchive.write(.init(records: [record], workspace: workspace), to: file)
    let restored = try BackupArchive.read(from: file)
    #expect(restored.records == [record] && restored.workspace.drafts == workspace.drafts)
    #expect(restored.workspace.summaryVisibility == workspace.summaryVisibility)
    #expect(restored.workspace.importReceipts == workspace.importReceipts)
    #expect(restored.workspace.pending == workspace.pending)
}

@Test func archiveRejectsCorruptionTruncationAndTrailingDataAndKeepsOldDestinationOnFailure() throws {
    let record = try lifecycleRecord()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("test.fintrack")
    try BackupArchive.write(.init(records: [record], workspace: .init()), to: file)
    let valid = try Data(contentsOf: file)
    for changed in [Data(valid.dropLast(10)), valid + Data([1]), Data(valid.enumerated().map { $0.offset == valid.count / 2 ? $0.element ^ 1 : $0.element })] {
        try changed.write(to: file)
        #expect(throws: (any Error).self) { try BackupArchive.read(from: file) }
    }
    try valid.write(to: file)
    #expect(throws: (any Error).self) { try BackupArchive.write(.init(records: [record, record], workspace: .init()), to: file) }
    #expect(try Data(contentsOf: file) == valid)
    let replacement = try lifecycleRecord("Replacement synthetic ledger note")
    try BackupArchive.write(.init(records: [replacement], workspace: .init()), to: file)
    #expect(try BackupArchive.read(from: file).records == [replacement])
}

@Test func currentArchiveCanExceedFiftyMiBAndRetiredJSONBackupsAreRejected() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let note = String(repeating: "s", count: 500_000)
    var records: [LedgerTransaction] = []
    for _ in 0..<112 { records.append(try lifecycleRecord(note)) }
    let file = directory.appendingPathComponent("large.fintrack")
    try BackupArchive.write(.init(records: records, workspace: .init()), to: file)
    #expect((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > ExchangeJSON.maximumBytes)
    let restored = try BackupArchive.read(from: file)
    #expect(restored.records.count == 112 && restored.records.first?.draft.notes.count == 500_000)
    let legacy = directory.appendingPathComponent("legacy.json")
    try ExchangeJSON.encode(FullBackup(records: [lifecycleRecord()], workspace: .init())).write(to: legacy)
    #expect(throws: (any Error).self) { try BackupArchive.read(from: legacy) }
}

@Test func capacityChecksFailBeforeAcceptingAnUnrecoverableState() throws {
    #expect(throws: (any Error).self) { try BackupCapacity.validate(recordCount: BackupCapacity.maximumRecords + 1, recordBytes: 0, workspace: .init()) }
    #expect(throws: (any Error).self) { try BackupCapacity.validate(recordCount: 1, recordBytes: BackupCapacity.maximumLogicalBytes, workspace: .init()) }
    try BackupCapacity.validate(recordCount: 10, recordBytes: 10_000, workspace: .init())
}

@Test func closedDiscussionCompactsWithoutReopeningAndPlainApprovalInventsNoDiscussion() throws {
    let record = try lifecycleRecord()
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: "1", text: "Synthetic old closed answer")
    var workspace = ReviewWorkspace()
    workspace.discussionAnswers = [answer]
    workspace.closeDiscussion(for: record)
    try workspace.compactCompletedExchanges(records: [record])
    #expect(workspace.discussionAnswers?.isEmpty == true)
    #expect(workspace.discussion(for: record)?.isResolved == true)
    let plain = try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-03-01"), payee: "Fictional Plain Purchase",
        amount: Money(minorUnits: 100), treatment: .spending, categoryID: "sample-household"))
    let approved = try plain.applying(.init(transactionID: plain.id, expectedRevision: 1, action: .approve), catalog: .prototype)
    var clean = ReviewWorkspace(); try clean.compactCompletedExchanges(records: [approved])
    #expect(clean.discussion(for: approved) == nil)
}

@Test func aNewHistoryReviewProposalIsNotDiscardedJustBecauseTheRecordWasAlreadyApproved() throws {
    let record = try lifecycleRecord()
    let approved = try record.applying(.init(transactionID: record.id, expectedRevision: 1, action: .approve), catalog: .prototype)
    var workspace = ReviewWorkspace(); workspace.establishBaseline(records: [])
    let packet = try workspace.prepare(records: [approved], catalog: .prototype, mode: .fullHistory)
    let proposal = ClassificationProposal(recordID: approved.id, expectedRevision: String(approved.revision),
        categoryID: "sample-groceries", rationale: "A new fictional history review suggestion")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, proposals: [proposal])
    try workspace.receive(ExchangeJSON.encode(response))
    try workspace.compactCompletedExchanges(records: [approved])
    #expect(workspace.staged.count == 1 && !workspace.decidedProposals.contains(proposal.id))
}

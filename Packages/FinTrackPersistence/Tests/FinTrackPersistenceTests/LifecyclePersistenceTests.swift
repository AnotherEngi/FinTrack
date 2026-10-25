import Foundation
import SwiftData
import Testing
import FinTrackCore
@testable import FinTrackPersistence

private func lifecycleDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
}
@MainActor
private func stageWeekly(_ repository: LocalTransactionRepository, _ rows: [WeeklyTransaction]) throws -> UUID {
    let batch = WeeklyBatch(coverage: "Synthetic test coverage; not a real statement", transactions: rows)
    try repository.stageIncoming(ExchangeJSON.encode(batch)); return batch.id
}

@MainActor @Test func approvalCompactsRepliesAndReopenPreservesFinalValuesAndUnsentFeedback() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let record = try SyntheticTransactions.make()[0]; try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    let answer = DiscussionAnswer(recordID: record.id, expectedRevision: String(record.revision), text: "PRIVATE_SYNTHETIC_DISPOSABLE_REPLY")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, answers: [answer])
    let bytes = try ExchangeJSON.encode(response)
    try repository.stageIncoming(bytes)
    #expect(try repository.workspace().staged.isEmpty)
    #expect(try repository.workspace().discussionAnswers == [answer])
    let request = ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: .approve)
    let approved = try repository.perform(request)
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.workspace().discussionAnswers?.isEmpty == true)
    #expect(try reopened.workspace().pending.contains { $0.kind == "approve" })
    #expect(try reopened.fetchAll().first?.draft.notes == record.draft.notes)
    #expect(try reopened.fetchAll().first?.draft.categoryID == record.draft.categoryID)
    #expect(try reopened.workspace().discussion(for: approved)?.isResolved == true)
    try reopened.stageIncoming(bytes)
    #expect(try reopened.fetchAll().first == approved)
    #expect(!String(decoding: try ExchangeJSON.encode(reopened.backup()), as: UTF8.self).contains("PRIVATE_SYNTHETIC_DISPOSABLE_REPLY"))
}

@MainActor @Test func unfinishedReplyBlocksApprovalAndCompletedApprovalReplayRemainsHarmless() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]; try repository.insert(record)
    let request = ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: .approve)
    try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: record.revision, text: "Fictional unfinished reply")
    #expect(throws: (any Error).self) { try repository.perform(request) }
    try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: record.revision, text: "")
    let approved = try repository.perform(request)
    try repository.saveDiscussionDraft(recordID: record.id, expectedRevision: approved.revision, text: "Fictional new question draft")
    #expect(try repository.perform(request) == approved)
    #expect(try repository.workspace().discussionDrafts?[record.id.uuidString]?.text == "Fictional new question draft")
}

@MainActor @Test func assistantGuidanceCannotExceedTheSameLimitAsManualGuidance() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]; try repository.insert(record)
    try repository.saveKnowledge((0..<1000).map { KnowledgeRule(text: "Fictional scoped rule \($0)") })
    let packet = try repository.prepareReview(mode: .pending)
    let proposal = KnowledgeProposal(text: "Fictional extra rule", rationale: "Synthetic capacity regression")
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion, knowledgeProposals: [proposal])
    try repository.stageIncoming(ExchangeJSON.encode(response))
    #expect(throws: (any Error).self) { try repository.decideProposal(fileID: response.id, proposalID: proposal.id, accept: true) }
    #expect(try repository.workspace().knowledge.count == 1000)
    #expect(try !repository.workspace().decidedProposals.contains(proposal.id))
    try repository.backup().validate(catalog: .prototype)
}

@MainActor @Test func newPostedIDCannotBypassSingleOrBatchPendingDuplicateChecks() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let pending = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "pending-id"),
        date: "2026-03-01", merchant: "Fictional Cafe", amountMinorUnits: "1000", postingStatus: .pending, categoryID: "sample-household")
    let originalFile = try stageWeekly(repository, [pending])
    try repository.acceptWeekly(fileID: originalFile, identity: pending.identity)
    let old = try #require(repository.fetchAll().first)
    let posted = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "posted-id"),
        date: "2026-03-03", merchant: "FICTIONAL CAFE 123", amountMinorUnits: "1200", categoryID: "sample-household")
    let file = try stageWeekly(repository, [posted])
    #expect(throws: (any Error).self) { try repository.acceptWeekly(fileID: file, identity: posted.identity) }
    #expect(throws: (any Error).self) { try repository.acceptNewWeeklyBatch(fileID: file) }
    #expect(try repository.fetchAll() == [old])
    try repository.acceptWeekly(fileID: file, identity: posted.identity, matchingRecordID: old.id, expectedRevision: old.revision)
    #expect(try repository.fetchAll().count == 1)
    #expect(try repository.fetchAll().first?.draft.amount.minorUnits == 1200)
    #expect(try repository.workspace().sourceLinks.first { $0.identity == pending.identity }?.supersededBy == posted.identity)
    let changedOld = WeeklyTransaction(identity: pending.identity, date: pending.date, merchant: pending.merchant,
        amountMinorUnits: "1100", postingStatus: .pending, categoryID: "sample-household")
    let staleFile = try stageWeekly(repository, [changedOld])
    let current = try #require(repository.fetchAll().first)
    #expect(throws: (any Error).self) { try repository.acceptWeekly(fileID: staleFile, identity: changedOld.identity,
        matchingRecordID: current.id, expectedRevision: current.revision) }
    #expect(try repository.fetchAll().first == current)
}

@MainActor @Test func twoAmbiguousRowsInOneBatchRollBackAllAdditions() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let a = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "a"), date: "2026-03-01",
        merchant: "Fictional Shop", amountMinorUnits: "1000", categoryID: "sample-household")
    let b = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "b"), date: "2026-03-02",
        merchant: "Fictional Shop", amountMinorUnits: "1200", categoryID: "sample-household")
    let file = try stageWeekly(repository, [a, b])
    let before = try repository.workspace().generation
    #expect(throws: (any Error).self) { try repository.acceptNewWeeklyBatch(fileID: file) }
    #expect(try repository.fetchAll().isEmpty)
    #expect(try repository.workspace().sourceLinks.isEmpty)
    #expect(try repository.workspace().generation == before)
}

@MainActor @Test func recoveryWorksWithoutOpeningTheDamagedOriginalAndNeverActivatesAnUnpreparedStore() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let damaged = directory.appendingPathComponent("FinTrack.store")
    let originalBytes = Data("SYNTHETIC DAMAGED DATABASE".utf8)
    try originalBytes.write(to: damaged)
    try Data("unsupported-convention".utf8).write(to: damaged.appendingPathExtension("amount-sign"))
    #expect(throws: (any Error).self) { try LocalTransactionRepository(storeURL: damaged) }
    #expect(throws: (any Error).self) { try StoreRecovery.activate(UUID(), in: directory) }
    let record = try SyntheticTransactions.make()[0]
    let snapshot = FullBackup(records: [record], workspace: .init())
    let id = try StoreRecovery.prepare(snapshot, in: directory)
    #expect(try StoreRecovery.activeURL(in: directory) == damaged)
    try StoreRecovery.activate(id, in: directory)
    let active = try StoreRecovery.activeURL(in: directory)
    let reopened = try LocalTransactionRepository(storeURL: active)
    #expect(try reopened.fetchAll() == [record])
    #expect(try Data(contentsOf: damaged) == originalBytes)
    #expect(throws: (any Error).self) { try StoreRecovery.deletePreservedStore(id: id.uuidString, in: directory) }
    #expect(try StoreRecovery.preservedStores(in: directory).contains { $0.id == "legacy" })
}

@MainActor @Test func invalidRestoreLeavesTheOriginalStoreAndPointerUnchanged() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let original = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("FinTrack.store"))
    let record = try SyntheticTransactions.make()[0]; try original.insert(record)
    #expect(throws: (any Error).self) { try StoreRecovery.prepare(.init(records: [record, record], workspace: .init()), in: directory) }
    #expect(try StoreRecovery.activeURL(in: directory) == directory.appendingPathComponent("FinTrack.store"))
    #expect(try original.fetchAll() == [record])
}

@Test func compressedNativeArchiveRoundTripAndFingerprintMatchPortableSHA() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let record = try SyntheticTransactions.make()[0]
    let snapshot = FullBackup(records: [record], workspace: .init())
    let url = directory.appendingPathComponent("test.fintrack")
    try NativeBackupArchive.write(snapshot, to: url)
    #expect(try NativeBackupArchive.read(from: url).records == [record])
    #expect(try NativeBackupArchive.fingerprint(url) == ContentDigest.sha256(Data(contentsOf: url)))
}

@MainActor @Test func anExistingMarkerWithoutItsDatabaseDoesNotSilentlyCreateAnEmptyStore() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("FinTrack.store")
    try Data(Money.amountSignConvention.utf8).write(to: url.appendingPathExtension("amount-sign"))
    #expect(throws: (any Error).self) { try LocalTransactionRepository(storeURL: url) }
    #expect(!FileManager.default.fileExists(atPath: url.path))
    let id = try StoreRecovery.prepare(.init(records: [], workspace: .init()), in: directory)
    try StoreRecovery.activate(id, in: directory)
    #expect(try StoreRecovery.activeURL(in: directory) != url)
}

@MainActor @Test(arguments: [0, 0o400])
func recoveryReplacesAnUnreadableMalformedPointerWithoutDecodingIt(permissions: Int) throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let record = try SyntheticTransactions.make()[0]
    let backup = FullBackup(records: [record], workspace: .init())
    let first = try StoreRecovery.prepare(backup, in: directory)
    try StoreRecovery.activate(first, in: directory)
    let pointer = directory.appendingPathComponent("ActiveStore.json")
    let damaged = Data("SYNTHETIC MALFORMED POINTER".utf8)
    try damaged.write(to: pointer)
    try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: pointer.path)
    #expect(throws: (any Error).self) { try StoreRecovery.activeURL(in: directory) }
    let next = try StoreRecovery.prepare(backup, in: directory)
    try StoreRecovery.activate(next, in: directory)
    #expect(try StoreRecovery.activeURL(in: directory).deletingLastPathComponent().lastPathComponent == next.uuidString)
    let preserved = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .first { $0.lastPathComponent.hasPrefix("PreviousStore-") })
    let attributes = try FileManager.default.attributesOfItem(atPath: preserved.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == permissions)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: preserved.path)
    #expect(try Data(contentsOf: preserved) == damaged)
    #expect(try LocalTransactionRepository(storeURL: StoreRecovery.activeURL(in: directory)).fetchAll() == [record])
}

@MainActor @Test func recoveryRejectsADirectoryPointerWithoutRemovingItsContents() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let record = try SyntheticTransactions.make()[0]
    let next = try StoreRecovery.prepare(.init(records: [record], workspace: .init()), in: directory)
    let pointer = directory.appendingPathComponent("ActiveStore.json", isDirectory: true)
    try FileManager.default.createDirectory(at: pointer, withIntermediateDirectories: false)
    let original = pointer.appendingPathComponent("synthetic-recovery-evidence.txt")
    let bytes = Data("SYNTHETIC PRESERVED EVIDENCE".utf8)
    try bytes.write(to: original)
    #expect(throws: (any Error).self) { try StoreRecovery.activate(next, in: directory) }
    #expect(try Data(contentsOf: original) == bytes)
    #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .allSatisfy { !$0.lastPathComponent.hasPrefix("PreviousStore-") })
}

@MainActor @Test func unreadSummarySurvivesCompactionUntilOpenedAndReplayDoesNotRecreateIt() throws {
    let directory = try lifecycleDirectory(); defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    let record = try SyntheticTransactions.make()[0]; try repository.insert(record)
    let packet = try repository.prepareReview(mode: .pending)
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        acknowledgedOperationIDs: packet.manifest.operationIDs, summary: "SYNTHETIC UNREAD SUMMARY")
    let data = try ExchangeJSON.encode(response)
    try repository.stageIncoming(data)
    #expect(try repository.workspace().staged.isEmpty)
    #expect(try repository.workspace().importReceipts?.first?.unreadSummary == response.summary)
    try repository.markImportSummaryRead(fileID: response.id)
    #expect(try repository.workspace().importReceipts?.first?.unreadSummary == nil)
    try repository.stageIncoming(data)
    #expect(try repository.workspace().importReceipts?.first?.unreadSummary == nil)
    #expect(try repository.fetchAll() == [record])
}

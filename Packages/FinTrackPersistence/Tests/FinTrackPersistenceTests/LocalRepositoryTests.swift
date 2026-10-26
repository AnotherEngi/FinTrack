import Foundation
import SwiftData
import Testing
import FinTrackCore
@testable import FinTrackPersistence

@MainActor
@Test func reopeningPreservesEditsAndDuplicateIDsDoNotOverwrite() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let sample = try SyntheticTransactions.make()[0]
    let repository = try LocalTransactionRepository(storeURL: url)
    try repository.insert(sample)
    var draft = sample.draft
    draft.notes = "Saved offline"
    try repository.update(id: sample.id, expectedRevision: 1, draft: draft)
    #expect(throws: LedgerError.duplicateID) { try repository.insert(sample) }
    #expect(throws: LedgerError.staleRevision) {
        try repository.update(id: sample.id, expectedRevision: 1, draft: sample.draft)
    }
    let reopened = try LocalTransactionRepository(storeURL: url)
    let reopenedRecords = try reopened.fetchAll()
    let saved = try #require(reopenedRecords.first)
    #expect(saved.revision == 2)
    #expect(saved.draft.notes == "Saved offline")
    #expect(saved.draft.amount.minorUnits == 4_325)
    #expect(try reopened.fetchAll().count == 1)
}

@MainActor
@Test func unmarkedEarlierStoreIsPreservedWithoutGuessingItsSigns() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("test.store")
    let original = Data("Unmarked earlier store: never open or rewrite automatically".utf8)
    try original.write(to: url)
    #expect(throws: PersistenceError.unsupportedFormat) {
        try LocalTransactionRepository(storeURL: url)
    }
    #expect(try Data(contentsOf: url) == original)
    #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("amount-sign").path))
}

@MainActor
@Test func unsupportedConventionAndOrphanedDraftsArePreserved() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("test.store")
    let marker = url.appendingPathExtension("amount-sign")
    try Data("unknown-convention".utf8).write(to: marker)
    #expect(throws: PersistenceError.unsupportedFormat) {
        try LocalTransactionRepository(storeURL: url)
    }
    #expect(try String(contentsOf: marker, encoding: .utf8) == "unknown-convention")

    try FileManager.default.removeItem(at: marker)
    let drafts = directory.appendingPathComponent("Drafts", isDirectory: true)
    try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
    let original = Data("Unfinished earlier amount: -12.".utf8)
    let draftURL = drafts.appendingPathComponent("earlier.json")
    try original.write(to: draftURL)
    #expect(throws: PersistenceError.unsupportedFormat) {
        try LocalTransactionRepository(storeURL: url)
    }
    #expect(try Data(contentsOf: draftURL) == original)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
}

private enum SimulatedFailure: Error { case diskWrite }

@MainActor
@Test func failedWriteRollsBackAndCanBeRetried() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var shouldFail = false
    let repository = try LocalTransactionRepository(
        storeURL: directory.appendingPathComponent("test.store"), commit: { context in
            if shouldFail { throw SimulatedFailure.diskWrite }
            try context.save()
        })
    let original = try SyntheticTransactions.make()[0]
    try repository.insert(original)
    var draft = original.draft
    draft.notes = "Recoverable draft"
    shouldFail = true
    #expect(throws: SimulatedFailure.self) {
        try repository.update(id: original.id, expectedRevision: 1, draft: draft)
    }
    #expect(try repository.fetchAll().first == original)
    shouldFail = false
    try repository.update(id: original.id, expectedRevision: 1, draft: draft)
    #expect(try repository.fetchAll().first?.draft.notes == "Recoverable draft")
}

@MainActor
@Test func sampleLoadingIsExplicitAndCannotReplaceExistingData() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    #expect(try repository.fetchAll().isEmpty)
    try repository.loadSyntheticExamples()
    #expect(try repository.fetchAll().count == 24)
    #expect(throws: LedgerError.demoRequiresEmptyStore) { try repository.loadSyntheticExamples() }
    #expect(try repository.fetchAll().count == 24)
}

@MainActor
@Test func reviewDecisionsAndSeparatedCommentsSurviveReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let original = try SyntheticTransactions.make()[0]
    try repository.insert(original)
    let request = ReviewRequest(transactionID: original.id, expectedRevision: original.revision, action: .approve)
    let approved = try repository.perform(request)
    var draft = approved.draft
    draft.notes = "My own note"
    let edited = try repository.update(id: approved.id, expectedRevision: approved.revision, draft: draft)
    let discussed = try repository.perform(ReviewRequest(transactionID: edited.id,
        expectedRevision: edited.revision, action: .discuss))
    let reopened = try LocalTransactionRepository(storeURL: url)
    let rows = try reopened.fetchAll()
    let saved = try #require(rows.first)
    #expect(saved == discussed)
    #expect(saved.approval == .unreviewed)
    #expect(saved.discussionRequested)
    #expect(saved.reviewHistory.count == 2)
    #expect(saved.draft.notes == "My own note")
    #expect(saved.assistantContext.question.isEmpty)
    #expect(saved.assistantContext.reason.isEmpty)
    #expect(saved.assistantContext.ledgerNotes == original.assistantContext.ledgerNotes)
}

@MainActor
@Test func failedReviewWritePreservesStateAndTheSameRequestCanBeRetried() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var shouldFail = false
    let repository = try LocalTransactionRepository(
        storeURL: directory.appendingPathComponent("test.store"), commit: { context in
            if shouldFail { throw SimulatedFailure.diskWrite }
            try context.save()
        })
    let original = try SyntheticTransactions.make()[0]
    try repository.insert(original)
    let request = ReviewRequest(transactionID: original.id, expectedRevision: original.revision, action: .approve)
    shouldFail = true
    #expect(throws: SimulatedFailure.self) { try repository.perform(request) }
    #expect(try repository.fetchAll().first == original)
    shouldFail = false
    let approved = try repository.perform(request)
    #expect(approved.approval == .confirmed)
    #expect(try repository.perform(request) == approved)
    #expect(try repository.fetchAll().first?.reviewHistory.count == 1)
}

@MainActor
@Test func sourceProvenanceAndUserTrackedDiscussionSurviveStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let original = try SyntheticTableExamples.make(asOf: TransactionDate("2026-10-24"))[2]
    let repository = try LocalTransactionRepository(storeURL: url)
    try repository.insert(original)
    let progressed = try repository.perform(ReviewRequest(transactionID: original.id,
        expectedRevision: original.revision, action: .markDiscussionInProgress))
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.fetchAll().first == progressed)
    #expect(progressed.discussionProgress == .reviewingInChatGPT)
    #expect(progressed.draft.source == original.draft.source)
    #expect(progressed.classificationProvenance == original.classificationProvenance)
}

@MainActor
@Test func appendedTableExamplesAreIdempotentAndPreserveManualEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let earlier = try SyntheticTransactions.make()[0]
    try repository.insert(earlier)
    #expect(try repository.addSyntheticTableExamples(asOf: TransactionDate("2026-10-24")) == 12)
    let sample = try #require(repository.fetchAll().first { $0.id != earlier.id })
    var draft = sample.draft
    draft.notes = "My edited synthetic example"
    let edited = try repository.update(id: sample.id, expectedRevision: sample.revision, draft: draft)
    #expect(try repository.addSyntheticTableExamples(asOf: TransactionDate("2026-10-25")) == 0)
    let reopened = try LocalTransactionRepository(storeURL: url)
    let rows = try reopened.fetchAll()
    #expect(rows.count == 13)
    #expect(rows.first { $0.id == earlier.id } == earlier)
    #expect(rows.first { $0.id == edited.id } == edited)
}

@MainActor
@Test func tableSampleWriteFailureRollsBackEntireAppendAndRetryIsSafe() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    var failNext = false
    let repository = try LocalTransactionRepository(storeURL: url, commit: { context in
        if failNext { failNext = false; throw SimulatedFailure.diskWrite }
        try context.save()
    })
    let original = try SyntheticTransactions.make()[0]
    try repository.insert(original)
    failNext = true
    #expect(throws: SimulatedFailure.diskWrite) {
        try repository.addSyntheticTableExamples(asOf: TransactionDate("2026-10-24"))
    }
    #expect(try repository.fetchAll() == [original])
    #expect(try repository.addSyntheticTableExamples(asOf: TransactionDate("2026-10-24")) == 12)
    #expect(try repository.fetchAll().count == 13)
}

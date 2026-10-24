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
    #expect(throws: PersistenceError.amountConventionMigrationRequired) {
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
    #expect(throws: PersistenceError.unsupportedAmountConvention) {
        try LocalTransactionRepository(storeURL: url)
    }
    #expect(try String(contentsOf: marker, encoding: .utf8) == "unknown-convention")

    try FileManager.default.removeItem(at: marker)
    let drafts = directory.appendingPathComponent("Drafts", isDirectory: true)
    try FileManager.default.createDirectory(at: drafts, withIntermediateDirectories: true)
    let original = Data("Unfinished earlier amount: -12.".utf8)
    let draftURL = drafts.appendingPathComponent("earlier.json")
    try original.write(to: draftURL)
    #expect(throws: PersistenceError.amountConventionMigrationRequired) {
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
    #expect(saved.approval == .confirmed)
    #expect(saved.discussionRequested)
    #expect(saved.reviewHistory.count == 2)
    #expect(saved.draft.notes == "My own note")
    #expect(saved.assistantContext == original.assistantContext)
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
@Test func v1MigrationPreservesRecordsAndNeverGuessesTreatmentOrApproval() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("test.store")
    let original = try SyntheticTransactions.make()[0]
    try autoreleasepool {
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let configuration = ModelConfiguration("FinTrack", schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(LedgerSchemaV1.StoredTransaction(original, reviewStatusCode: "reviewed"))
        try context.save()
    }
    // Represents the already-agreed positive-outflow prototype, not an unmarked store.
    try Data(Money.amountSignConvention.utf8).write(to: url.appendingPathExtension("amount-sign"))
    let repository = try LocalTransactionRepository(storeURL: url)
    let migratedRows = try repository.fetchAll()
    let migrated = try #require(migratedRows.first)
    #expect(migrated.id == original.id)
    #expect(migrated.revision == original.revision)
    #expect(migrated.draft.amount == original.draft.amount)
    #expect(migrated.draft.notes == original.draft.notes)
    #expect(migrated.draft.legacyReviewStatus == .reviewed)
    #expect(migrated.draft.treatment == .unresolved)
    #expect(migrated.draft.postingStatus == .unresolved)
    #expect(migrated.approval == .unreviewed)
    #expect(migrated.assistantContext == AssistantContext())
    var draft = migrated.draft
    draft.treatment = .spending
    draft.postingStatus = .posted
    draft.categoryID = "sample-groceries"
    let classified = try repository.update(id: migrated.id, expectedRevision: migrated.revision, draft: draft)
    let approved = try repository.perform(ReviewRequest(transactionID: classified.id,
        expectedRevision: classified.revision, action: .approve))
    #expect(approved.approval == .confirmed)
    #expect(approved.draft.legacyReviewStatus == .reviewed)
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.fetchAll().first == approved)
}

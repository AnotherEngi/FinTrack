import Foundation
import Testing
import FinTrackCore
@testable import FinTrackPersistence

private enum HistoryDiskFailure: Error { case disk }
private func historyStoreSnapshot() throws -> FullBackup {
    let category = ReviewCategory(id: "fictional-food", label: "Fictional Food")
    let draft = try TransactionDraft(date: TransactionDate("2026-03-01"), payee: "Fictional Market",
        amount: Money(minorUnits: 1234), notes: "User's preserved note", treatment: .spending, categoryID: category.id)
    let record = try LedgerTransaction(draft: draft, approval: .confirmed)
    var workspace = ReviewWorkspace(); workspace.importedCategories = [category]
    workspace.historyDetails = [record.id.uuidString: ["Subcategory": "Fictional pantry"]]
    workspace.baselineEstablished = true
    return FullBackup(records: [record], workspace: workspace)
}

@MainActor @Test func migratedCategoriesReopenAndNewWeeklyRowsUseTheSameTaxonomy() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let initial = try historyStoreSnapshot()
    try LocalTransactionRepository(storeURL: url).restore(initial)
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.fetchAll() == initial.records)
    #expect(reopened.catalog.categories == initial.workspace.importedCategories)
    let row = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "new-weekly-id"),
        date: "2026-04-01", merchant: "Fictional Bakery", amountMinorUnits: "500", categoryID: "fictional-food")
    let batch = WeeklyBatch(coverage: "Synthetic incremental import", transactions: [row])
    try reopened.stageIncoming(ExchangeJSON.encode(batch))
    #expect(try reopened.acceptNewWeeklyBatch(fileID: batch.id) == 1)
    #expect(try reopened.acceptNewWeeklyBatch(fileID: batch.id) == 0)
    #expect(try reopened.fetchAll().first { $0.id == initial.records[0].id } == initial.records[0])
    #expect(try reopened.workspace().historyDetails == initial.workspace.historyDetails)
    try reopened.backup().validate(catalog: .prototype)
}

@MainActor @Test func failedHistoryRestoreRollsBackBothTaxonomyAndFinancialState() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: {
        if fail { throw HistoryDiskFailure.disk }; try $0.save()
    })
    let original = try SyntheticTransactions.make()[0]; try repository.insert(original)
    let before = try repository.workspace().generation
    let next = try historyStoreSnapshot(); fail = true
    #expect(throws: HistoryDiskFailure.self) { try repository.restore(next) }
    #expect(repository.catalog.categories == ReviewCatalog.prototype.categories)
    #expect(try repository.fetchAll() == [original])
    #expect(try repository.workspace().generation == before)
    #expect(try repository.workspace().importedCategories == nil)
}

@MainActor @Test func isolatedHistoryRestorePreservesTheOriginalSyntheticLedger() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let originalURL = directory.appendingPathComponent("FinTrack.store")
    let original = try LocalTransactionRepository(storeURL: originalURL)
    let sample = try SyntheticTransactions.make()[0]; try original.insert(sample)
    let snapshot = try historyStoreSnapshot()
    let id = try StoreRecovery.prepare(snapshot, in: directory)
    try StoreRecovery.activate(id, in: directory)
    let active = try LocalTransactionRepository(storeURL: StoreRecovery.activeURL(in: directory))
    #expect(try active.fetchAll() == snapshot.records)
    #expect(active.catalog.categories == snapshot.workspace.importedCategories)
    #expect(try LocalTransactionRepository(storeURL: originalURL).fetchAll() == [sample])
}

@MainActor @Test func legacyBackupCanRestoreAfterAnImportedTaxonomyWithoutUsingTheWrongCatalog() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"))
    try repository.restore(historyStoreSnapshot())
    let original = try SyntheticTransactions.make()[0]
    let approved = try original.applying(.init(transactionID: original.id, expectedRevision: original.revision, action: .approve), catalog: .prototype)
    try repository.restore(.init(records: [approved], workspace: .init()))
    #expect(repository.catalog.categories == ReviewCatalog.prototype.categories)
    #expect(try repository.fetchAll() == [approved])
    #expect(try repository.workspace().importedCategories == nil)
}

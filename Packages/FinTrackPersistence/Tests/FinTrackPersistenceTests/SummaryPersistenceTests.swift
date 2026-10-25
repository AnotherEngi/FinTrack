import Foundation
import SwiftData
import Testing
import FinTrackCore
@testable import FinTrackPersistence

private enum SummaryWriteFailure: Error { case disk }

@MainActor
@Test func visibilityReopensAndRestoresWithoutEditingTransactionsOrQueuingFeedback() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let before = try repository.workspace()
    let settings = SummaryVisibility(recordIDs: [record.id], categoryIDs: ["sample-transit"], tags: ["Fictional"])
    try repository.saveSummaryVisibility(settings)
    let after = try repository.workspace()
    #expect(after.generation != before.generation && after.pending == before.pending)
    #expect(try repository.fetchAll() == [record])
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.workspace().summaryVisibility == settings)
    let backup = try reopened.backup()
    let restored = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("restored.store"))
    try restored.restore(ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(backup)))
    #expect(try restored.workspace().summaryVisibility == settings)
    #expect(try restored.fetchAll() == [record])
}

@MainActor
@Test func failedVisibilitySaveRollsBackSettingsAndBackupGeneration() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("test.store"), commit: { context in
        if fail { throw SummaryWriteFailure.disk }; try context.save()
    })
    let record = try SyntheticTransactions.make()[0]
    try repository.insert(record)
    let before = try repository.workspace()
    fail = true
    #expect(throws: SummaryWriteFailure.self) { try repository.saveSummaryVisibility(.init(recordIDs: [record.id])) }
    #expect(try repository.workspace().summaryVisibility == nil)
    #expect(try repository.workspace().generation == before.generation)
    #expect(try repository.fetchAll() == [record])
}

@MainActor
@Test func refundLinksReopenAndRejectPurchaseEditsThatWouldInvalidateAllocations() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("test.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let purchase = try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-03-01"),
        payee: "Fictional purchase", amount: Money(minorUnits: 1000), treatment: .spending, categoryID: "sample-household"))
    let refund = try LedgerTransaction(draft: TransactionDraft(date: TransactionDate("2026-06-12"),
        payee: "Fictional refund", amount: Money(minorUnits: -700), treatment: .refund, categoryID: "sample-household",
        refundAllocations: [.init(purchaseID: purchase.id, amount: Money(minorUnits: 700))]))
    try repository.insert(purchase); try repository.insert(refund)
    var changed = purchase.draft; changed.amount = Money(minorUnits: 600)
    let before = try repository.workspace()
    #expect(throws: (any Error).self) { try repository.update(id: purchase.id, expectedRevision: 1, draft: changed) }
    #expect(try repository.workspace().generation == before.generation)
    let reopened = try LocalTransactionRepository(storeURL: url)
    let records = try reopened.fetchAll()
    #expect(records.first { $0.id == purchase.id } == purchase)
    #expect(records.first { $0.id == refund.id } == refund)
    #expect(try SummaryReport(records: records, catalog: .prototype).total.minorUnits == 300)
    let backup = try reopened.backup()
    try backup.validate(catalog: .prototype)
    let restored = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("restored.store"))
    try restored.restore(ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(backup)))
    #expect(try restored.fetchAll().first { $0.id == refund.id }?.draft.refundAllocations == refund.draft.refundAllocations)
    #expect(try SummaryReport(records: restored.fetchAll(), catalog: .prototype).total.minorUnits == 300)
}

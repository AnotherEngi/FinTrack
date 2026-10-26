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
    workspace.programs = [.init(label: "Fictional program")]
    workspace.baselineEstablished = true
    return FullBackup(records: [record], workspace: workspace)
}

@MainActor @Test func financialSettingsAndSplitAmountsReopenAndFailedSaveRollsBack() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let url = directory.appendingPathComponent("financial.store")
    let repository = try LocalTransactionRepository(storeURL: url, commit: { if fail { throw HistoryDiskFailure.disk }; try $0.save() })
    try repository.restore(historyStoreSnapshot())
    let record = try #require(repository.fetchAll().first)
    var financial = FinancialContext(workspace: try repository.workspace())
    let categories = repository.catalog.categories + [ReviewCategory(id: "other", label: "Other", subcategories: [.init(id: "detail", label: "Detail")])]
    financial.programs = [.init(label: "Fictional annual program", limit: nil)]
    financial.claims = [.init(expenseID: record.id, programID: financial.programs[0].id, expected: .init(minorUnits: 400))]
    try repository.saveFinancialSettings(financial, categories: categories)
    var draft = record.draft
    draft.allocations = [.init(id: TransactionDraft.primaryAllocationID, categoryID: "fictional-food", amount: .init(minorUnits: 834), origin: .user),
        .init(categoryID: "other", subcategoryID: "detail", amount: .init(minorUnits: 400), origin: .user)]
    let split = try repository.update(id: record.id, expectedRevision: record.revision, draft: draft)
    let savedGeneration = try repository.workspace().generation
    financial.programs[0].label = "Should roll back"
    fail = true
    #expect(throws: HistoryDiskFailure.self) { try repository.saveFinancialSettings(financial, categories: categories + [.init(id: "new", label: "Should roll back")]) }
    #expect(repository.catalog.categories == categories)
    #expect(try repository.workspace().generation == savedGeneration)
    fail = false
    let reopened = try LocalTransactionRepository(storeURL: url)
    #expect(try reopened.fetchAll().first == split)
    #expect(try reopened.workspace().programs[0].label == "Fictional annual program")
    #expect(try reopened.workspace().programs[0].period.basis == .unknown)
    #expect(try reopened.workspace().claims.count == 1)
    var invalid = FinancialContext(workspace: try reopened.workspace()); invalid.claims[0].expenseID = UUID()
    #expect(throws: (any Error).self) { try reopened.saveFinancialSettings(invalid, categories: categories) }
    #expect(try reopened.workspace().generation == savedGeneration)
}

@MainActor @Test func weeklyReconciliationRetainsCompletePendingVersionAndUserEdits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("versions.store")
    let repository = try LocalTransactionRepository(storeURL: url)
    let pending = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "pending-original"),
        date: "2026-03-01", merchant: "Fictional Pending Shop", amountMinorUnits: "1000", postingStatus: .pending, categoryID: "sample-groceries")
    let first = WeeklyBatch(coverage: "Synthetic pending", transactions: [pending])
    try repository.stageIncoming(ExchangeJSON.encode(first)); #expect(try repository.acceptNewWeeklyBatch(fileID: first.id) == 1)
    let original = try #require(repository.fetchAll().first)
    var user = original.draft; user.notes = "User note stays"; user.tags = ["User tag"]
    let edited = try repository.update(id: original.id, expectedRevision: original.revision, draft: user)
    let posted = WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "posted-successor"),
        date: "2026-03-03", activityDate: "2026-03-01", merchant: "Fictional Final Shop", amountMinorUnits: "1200", categoryID: "sample-household")
    let second = WeeklyBatch(coverage: "Synthetic posted", transactions: [posted])
    try repository.stageIncoming(ExchangeJSON.encode(second))
    try repository.acceptWeekly(fileID: second.id, identity: posted.identity, matchingRecordID: edited.id, expectedRevision: edited.revision)
    let saved = try #require(LocalTransactionRepository(storeURL: url).fetchAll().first)
    #expect(saved.id == original.id && saved.draft.sourceVersions.count == 2)
    #expect(saved.draft.sourceVersions[0].merchant == "Fictional Pending Shop" && saved.draft.sourceVersions[0].amount.minorUnits == 1000)
    #expect(saved.draft.sourceVersions[0].lifecycle == .superseded && saved.draft.sourceVersions[1].observedStatus == .posted)
    #expect(saved.draft.notes == "User note stays" && saved.draft.tags == ["User tag"] && saved.draft.categoryID == "sample-groceries")
    #expect(saved.draft.amount.minorUnits == 1200 && saved.approval == .unreviewed)
    var tamper = saved.draft; tamper.sourceVersions[0].merchant = "Rewrite forbidden"
    #expect(throws: (any Error).self) { try repository.update(id: saved.id, expectedRevision: saved.revision, draft: tamper) }
}

@MainActor @Test func currentNativeArchiveRetainsProgramsClaimsAllocationsAndUnusedDefinitions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let initial = try historyStoreSnapshot()
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("original.store")); try repository.restore(initial)
    var financial = FinancialContext(workspace: initial.workspace)
    financial.claims = [.init(expenseID: initial.records[0].id, programID: financial.programs[0].id, eligibility: .unknown)]
    try repository.saveFinancialSettings(financial, categories: repository.catalog.categories + [.init(id: "unused", label: "Unused", definition: .string("Keep this definition"))])
    let archive = directory.appendingPathComponent("synthetic.fintrack"); try NativeBackupArchive.write(repository.backup(), to: archive)
    let recovered = try NativeBackupArchive.read(from: archive)
    let fresh = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("restored.store")); try fresh.restore(recovered)
    #expect(try fresh.fetchAll() == initial.records)
    #expect(try fresh.workspace().claims == financial.claims && fresh.workspace().programs == financial.programs)
    #expect(fresh.catalog.category(id: "unused")?.definition.text == "Keep this definition")
}

@MainActor @Test func dedicatedRefundImportRollsBackAndRetriesWithoutDuplicateOrGenerationChange() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var fail = false
    let repository = try LocalTransactionRepository(storeURL: directory.appendingPathComponent("refunds.store"), commit: { if fail { throw HistoryDiskFailure.disk }; try $0.save() })
    let purchase = try #require(historyStoreSnapshot().records.first)
    let refundID = UUID()
    let rows = [MigrationRow(locator: "Fiction!2", disposition: .active, recordID: purchase.id, source: "Fiction", tab: "Fiction", treatment: .spending, amount: purchase.draft.amount),
        MigrationRow(locator: "Fiction!3", disposition: .deferredRefund, recordID: refundID, source: "Fiction", tab: "Fiction", treatment: .refund, amount: .init(minorUnits: -100))]
    let history = HistoryImport(sourceName: "Synthetic only", records: [purchase], categories: try historyStoreSnapshot().workspace.importedCategories!,
        audit: .init(columns: [.init(name: "Fiction!Amount", handling: "mapped", target: .amount, explanation: "Exact cents")], rows: rows, controls: try HistoryAudit.calculate(rows: rows, records: [purchase])))
    try repository.restore(history.snapshot())
    let refund = try LedgerTransaction(id: refundID, draft: .init(date: .init("2026-06-12"), payee: "Fictional refund", amount: .init(minorUnits: -100), treatment: .refund,
        categoryID: "fictional-food", refundAllocations: [.init(purchaseID: purchase.id, amount: .init(minorUnits: 100))]))
    let value = RefundImport(migrationID: history.id, records: [refund], locators: ["Fiction!3"], purchaseRevisions: [purchase.id.uuidString: String(purchase.revision)])
    fail = true
    #expect(throws: HistoryDiskFailure.self) { try repository.acceptRefundImport(value) }
    #expect(try repository.fetchAll() == [purchase] && repository.workspace().refundImports.isEmpty)
    fail = false; try repository.acceptRefundImport(value)
    let generation = try repository.workspace().generation
    try repository.acceptRefundImport(value)
    #expect(try repository.fetchAll().count == 2 && repository.workspace().refundImports.count == 1)
    #expect(try repository.workspace().generation == generation)
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
    #expect(try reopened.workspace().programs == initial.workspace.programs)
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

@MainActor @Test func currentBackupCanReplaceAnImportedTaxonomyWithoutUsingTheWrongCatalog() throws {
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

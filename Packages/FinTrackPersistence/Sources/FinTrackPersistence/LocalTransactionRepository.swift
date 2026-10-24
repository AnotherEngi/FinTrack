import Foundation
import SwiftData
import FinTrackCore

@MainActor
public final class LocalTransactionRepository: TransactionRepository {
    private typealias Row = LedgerSchemaV2.StoredTransaction
    private let container: ModelContainer
    private let context: ModelContext
    private let commit: (ModelContext) throws -> Void
    public let catalog: ReviewCatalog

    public convenience init(storeURL: URL, catalog: ReviewCatalog = .prototype) throws {
        try self.init(storeURL: storeURL, catalog: catalog, commit: { try $0.save() })
    }

    // Injection lets tests exercise real SwiftData rollback after a write failure.
    init(storeURL: URL, catalog: ReviewCatalog = .prototype,
         commit: @escaping (ModelContext) throws -> Void) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Self.verifyAmountConvention(at: storeURL)
        let schema = Schema(versionedSchema: LedgerSchemaV2.self)
        let configuration = ModelConfiguration("FinTrack", schema: schema,
            url: storeURL, cloudKitDatabase: .none)
        let openedContainer = try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self,
                                                 configurations: [configuration])
        let openedContext = ModelContext(openedContainer)
        openedContext.autosaveEnabled = false
        container = openedContainer
        context = openedContext
        self.commit = commit
        self.catalog = catalog
    }

    /// Unmarked stores/drafts predate the agreed positive-outflow convention.
    /// Never guess their meaning, change their signs, or reset their contents.
    private static func verifyAmountConvention(at storeURL: URL) throws {
        let marker = storeURL.appendingPathExtension("amount-sign")
        if FileManager.default.fileExists(atPath: marker.path) {
            let convention = try String(contentsOf: marker, encoding: .utf8)
            guard convention == Money.amountSignConvention else {
                throw PersistenceError.unsupportedAmountConvention
            }
            return
        }

        let storePaths = [storeURL.path, storeURL.path + "-wal", storeURL.path + "-shm"]
        let draftsDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent("Drafts", isDirectory: true)
        let hasDrafts: Bool
        if FileManager.default.fileExists(atPath: draftsDirectory.path) {
            hasDrafts = !(try FileManager.default.contentsOfDirectory(atPath: draftsDirectory.path)).isEmpty
        } else {
            hasDrafts = false
        }
        guard !storePaths.contains(where: { FileManager.default.fileExists(atPath: $0) }),
              !hasDrafts else {
            throw PersistenceError.amountConventionMigrationRequired
        }
        try Data(Money.amountSignConvention.utf8).write(to: marker, options: .atomic)
    }

    public static func applicationSupportDirectory() throws -> URL {
        var directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("FinTrack", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try directory.setResourceValues(values)
        return directory
    }

    public static func openDefault(catalog: ReviewCatalog = .prototype) throws -> LocalTransactionRepository {
        try LocalTransactionRepository(storeURL:
            applicationSupportDirectory().appendingPathComponent("FinTrack.store"), catalog: catalog)
    }

    public func fetchAll() throws -> [LedgerTransaction] {
        let descriptor = FetchDescriptor<Row>(sortBy: [
            SortDescriptor(\Row.dateText, order: .reverse),
            SortDescriptor(\Row.createdAt, order: .reverse)
        ])
        return try context.fetch(descriptor).map {
            let record = try $0.value()
            try record.validateReviewState(catalog: catalog)
            return record
        }
    }

    public func insert(_ transaction: LedgerTransaction) throws {
        guard try row(id: transaction.id) == nil else { throw LedgerError.duplicateID }
        try transaction.draft.validate()
        try transaction.validateReviewState(catalog: catalog)
        try committing {
            context.insert(try Row(transaction))
        }
    }

    @discardableResult
    public func update(id: UUID, expectedRevision: Int64, draft: TransactionDraft) throws -> LedgerTransaction {
        guard let stored = try row(id: id) else { throw LedgerError.recordNotFound }
        let current = try stored.value()
        let updated = try current.revising(with: draft, expectedRevision: expectedRevision)
        try updated.validateReviewState(catalog: catalog)
        if updated != current { try committing { try stored.apply(updated) } }
        return updated
    }

    public func perform(_ request: ReviewRequest) throws -> LedgerTransaction {
        guard let stored = try row(id: request.transactionID) else { throw LedgerError.recordNotFound }
        let current = try stored.value()
        let updated = try current.applying(request, catalog: catalog)
        if updated != current { try committing { try stored.apply(updated) } }
        return updated
    }

    /// Explicit opt-in only; never repopulate an empty store on app launch.
    public func loadSyntheticExamples() throws {
        guard try context.fetchCount(FetchDescriptor<Row>()) == 0 else {
            throw LedgerError.demoRequiresEmptyStore
        }
        let records = try SyntheticTransactions.make()
        try committing {
            for record in records {
                try record.validateReviewState(catalog: catalog)
                context.insert(try Row(record))
            }
        }
    }

    private func row(id: UUID) throws -> Row? {
        var descriptor = FetchDescriptor<Row>(predicate: #Predicate { $0.recordID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func committing(_ changes: () throws -> Void) throws {
        do {
            try changes()
            try commit(context)
        } catch {
            context.rollback()
            throw error
        }
    }
}

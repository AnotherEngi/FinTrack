import Foundation
import Observation
import FinTrackCore
import FinTrackPersistence

@MainActor
@Observable
final class LedgerViewModel {
    private var repository: LocalTransactionRepository?
    private var draftStore: DraftStore?
    private(set) var catalog = ReviewCatalog.prototype
    private(set) var records: [LedgerTransaction] = []
    private(set) var drafts: [EditorDraft] = []
    private(set) var startupFailure: String?
    private(set) var sessionChanges = SessionChanges()
    private(set) var workspace = ReviewWorkspace()
    private(set) var discussions: [UUID: DiscussionThread] = [:]
    private(set) var backup: CloudBackup?
    private(set) var capacityNotice: String?
    private(set) var preservedStores: [PreservedStore] = []
    var canExportBackup: Bool { repository != nil && startupFailure == nil }
    var message: String?
    // Real history migration is paused by the user's full-framework prerequisite.
    // One current format. Enable real migration only after the framework acceptance checks.
    var historyImportBlockReason: String? {
        "Real history and deferred-refund migration are paused until this financial-framework revision passes Mac package tests, an Xcode build and the physical-iPad backup/restore checks. Use synthetic development data only."
    }

    func saveFinancialSettings(_ value: FinancialContext, categories: [ReviewCategory]) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.saveFinancialSettings(value, categories: categories); reload()
    }
    func importRefunds(_ value: RefundImport) throws {
        if let reason = historyImportBlockReason { throw ExchangeError.invalid(reason) }
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.acceptRefundImport(value); reload()
    }

    func saveSummaryVisibility(_ value: SummaryVisibility) {
        do {
            guard let repository else { throw LedgerError.recordNotFound }
            try repository.saveSummaryVisibility(value)
            reload()
        } catch { message = "Visibility settings were not saved: " + error.localizedDescription }
    }

    func setSummaryHidden(_ hidden: Bool, recordID: UUID) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        var value = try repository.workspace().summaryVisibility ?? .init()
        if hidden { value.recordIDs.insert(recordID) } else { value.recordIDs.remove(recordID) }
        try repository.saveSummaryVisibility(value)
        reload()
    }

    init() {
        do { try Self.cleanupPreparedFiles() }
        catch { message = "Older temporary review files could not be removed: \(error.localizedDescription)" }
        do { try Self.cleanupArchivePartials() }
        catch { message = "Interrupted backup files could not be cleaned: \(error.localizedDescription)" }
        do { backup = try CloudBackup(directory: LocalTransactionRepository.applicationSupportDirectory()) }
        catch { message = "Automatic backup could not start: \(error.localizedDescription)" }
        do {
            let openedRepository = try LocalTransactionRepository.openDefault()
            let openedDraftStore = try DraftStore(directory:
                LocalTransactionRepository.applicationSupportDirectory()
                    .appendingPathComponent("Drafts", isDirectory: true), repository: openedRepository)
            try openedRepository.maintainRetention()
            repository = openedRepository
            draftStore = openedDraftStore
        } catch {
            repository = nil
            draftStore = nil
            startupFailure = error.localizedDescription
        }
        reload()
        refreshPreservedStores()
    }

    func reload() {
        guard let repository, let draftStore else { return }
        do {
            let savedRecords = try repository.fetchAll()
            let savedDrafts = try draftStore.fetchAll()
            let savedWorkspace = try repository.workspace()
            let savedDiscussions = savedWorkspace.discussions(in: savedRecords)
            records = savedRecords; drafts = savedDrafts; workspace = savedWorkspace; catalog = repository.catalog
            discussions = Dictionary(uniqueKeysWithValues: savedDiscussions.map { ($0.id, $0) })
            let capacity = try repository.capacityUsage()
            capacityNotice = capacity.records >= BackupCapacity.maximumRecords * 4 / 5
                || capacity.bytes >= BackupCapacity.maximumLogicalBytes * 4 / 5
                ? "Backup capacity is approaching its supported limit. Review storage in Backup." : nil
            backup?.schedule(FullBackup(records: savedRecords, workspace: savedWorkspace))
        } catch {
            message = "Unable to read saved data: \(error.localizedDescription)"
            startupFailure = error.localizedDescription
        }
    }

    func loadSamples() {
        do {
            guard let repository else { throw LedgerError.recordNotFound }
            try repository.loadSyntheticExamples()
            reload()
        } catch { message = error.localizedDescription }
    }

    func loadTableSamples() {
        do {
            guard let repository else { throw LedgerError.recordNotFound }
            let count = try repository.addSyntheticTableExamples(asOf: TransactionDate(ReportingCalendar.dayText(at: .now)))
            reload()
            message = count == 0 ? "Table examples already exist. Your edits were preserved."
                : "Added \(count) fictional table examples. Existing records were preserved."
        } catch { message = error.localizedDescription }
    }

    func loadSpendingSamples() {
        do {
            guard let repository else { throw LedgerError.recordNotFound }
            let count = try repository.addSyntheticSpendingExamples(asOf: TransactionDate(ReportingCalendar.dayText(at: .now)))
            reload()
            message = "Added \(count) fictional chart transactions. Existing records and edits were preserved."
        } catch { message = error.localizedDescription }
    }

    func storeDraft(_ draft: EditorDraft) throws {
        guard let draftStore else { throw LedgerError.recordNotFound }
        try draftStore.write(draft)
        reload()
    }

    func commitDraft(_ draft: EditorDraft) throws -> EditorDraft {
        guard let repository, let draftStore else { throw LedgerError.recordNotFound }
        let value = try draft.input.value()
        let before = records.first { $0.id == draft.id }
        let saved: LedgerTransaction
        if let revision = draft.expectedRevision {
            saved = try repository.update(id: draft.id, expectedRevision: revision, draft: value)
        } else {
            saved = try LedgerTransaction(id: draft.id, createdAt: draft.createdAt, updatedAt: .now,
                draft: value, classificationProvenance: .manual(value))
            try repository.insert(saved)
        }
        sessionChanges.register(before: before, after: saved)
        var committed = draft
        committed.expectedRevision = saved.revision
        committed.input.rebase(on: saved.draft)
        do { try draftStore.remove(id: draft.id) }
        catch { message = "The transaction saved, but its draft could not be removed: \(error.localizedDescription)" }
        reload()
        return committed
    }

    func discardDraft(id: UUID) throws {
        try draftStore?.remove(id: id)
        reload()
    }

    func editor(for record: LedgerTransaction) -> EditorDraft {
        drafts.first(where: { $0.id == record.id }) ?? EditorDraft(record: record)
    }

    func record(id: UUID) -> LedgerTransaction? { records.first { $0.id == id } }

    func prepareReview(mode: ReviewMode) throws -> URL {
        guard let repository else { throw LedgerError.recordNotFound }
        let packet = try repository.prepareReview(mode: mode)
        let url = try shareFile(data: ExchangeJSON.encode(packet), name: "Review-\(packet.manifest.id.uuidString).json")
        reload()
        return url
    }

    func stageIncoming(_ data: Data) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.stageIncoming(data); reload()
    }
    func importHistory(_ value: HistoryImport) throws {
        if let reason = historyImportBlockReason { throw ExchangeError.invalid(reason) }
        let snapshot = try value.snapshot()
        if let previous = workspace.historyImport {
            if previous.id == value.id, previous.digest == snapshot.workspace.historyImport?.digest {
                message = "This history was already imported. Current edits were preserved."
                return
            }
            throw ExchangeError.invalid("History is already established in this ledger. Use weekly intake for additions; a second history migration was not applied.")
        }
        try restoreBackup(snapshot)
        message = "Imported \(snapshot.records.count) history records. The previous ledger is preserved in Backup. Review the imported audit and compare totals with the original Sheet."
    }
    func dismissIncoming(_ id: UUID) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.dismissIncoming(fileID: id); reload()
    }
    func markImportSummaryRead(_ id: UUID) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.markImportSummaryRead(fileID: id); reload()
    }

    func acknowledge(_ id: UUID) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.acknowledgeResponse(fileID: id); reload()
    }

    func reply(recordID: UUID, expectedRevision: Int64, text: String) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.replyToDiscussion(recordID: recordID, expectedRevision: expectedRevision, text: text)
        reload()
    }

    func resolveDiscussion(_ record: LedgerTransaction) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.resolveDiscussion(recordID: record.id, expectedRevision: record.revision)
        reload()
    }

    func saveDiscussionDraft(recordID: UUID, expectedRevision: Int64, text: String) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.saveDiscussionDraft(recordID: recordID, expectedRevision: expectedRevision, text: text)
        reload()
    }

    func decide(fileID: UUID, proposalID: UUID, accept: Bool) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.decideProposal(fileID: fileID, proposalID: proposalID, accept: accept); reload()
    }

    func acceptWeekly(fileID: UUID, identity: BankIdentity, matching: LedgerTransaction? = nil, allowSeparate: Bool = false) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.acceptWeekly(fileID: fileID, identity: identity,
            matchingRecordID: matching?.id, expectedRevision: matching?.revision, allowSeparate: allowSeparate)
        reload()
    }

    func saveKnowledge(_ rules: [KnowledgeRule]) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        try repository.saveKnowledge(rules); reload()
    }

    func acceptWeeklyBatch(_ id: UUID) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        let added = try repository.acceptNewWeeklyBatch(fileID: id)
        reload()
        message = "Added \(added) transactions. Any changed source IDs still listed need individual reconciliation; they were not silently applied."
    }

    func exportBackup() async throws -> URL {
        guard let repository else { throw LedgerError.recordNotFound }
        let snapshot = try repository.backup()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrackPrepared", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("FinTrack-backup-\(UUID().uuidString).fintrack")
        return try await Task.detached(priority: .userInitiated) {
            try NativeBackupArchive.write(snapshot, to: url); return url
        }.value
    }

    private func validateRawDrafts(_ value: FullBackup) throws {
        try value.validate(catalog: .prototype)
        for (id, raw) in value.workspace.drafts {
            let draft = try StrictJSON.decode(EditorDraft.self, from: raw)
            guard draft.id.uuidString == id, draft.expectedRevision.map({ $0 > 0 }) ?? true else {
                throw ExchangeError.invalid("A backup draft has an invalid ID/revision.")
            }
            if let revision = draft.expectedRevision {
                guard let record = value.records.first(where: { $0.id == draft.id }), revision <= record.revision else {
                    throw ExchangeError.invalid("A draft references a missing record or future revision. No restore was applied.")
                }
            }
        }
    }

    func readBackup(_ url: URL) async throws -> FullBackup {
        let value = try await Task.detached(priority: .userInitiated) { try NativeBackupArchive.readSelectedFile(url) }.value
        try validateRawDrafts(value); return value
    }

    func restoreBackup(_ value: FullBackup) throws {
        try validateRawDrafts(value)
        let restoredCatalog = try value.workspace.effectiveCatalog(fallback: .prototype)
        let directory = try LocalTransactionRepository.applicationSupportDirectory()
        let id = try StoreRecovery.prepare(value, in: directory, catalog: restoredCatalog)
        let preparedURL = directory.appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("FinTrack.store")
        let opened = try LocalTransactionRepository(storeURL: preparedURL, catalog: restoredCatalog)
        let openedDrafts = try DraftStore(directory: directory.appendingPathComponent("Drafts", isDirectory: true), repository: opened)
        try StoreRecovery.activate(id, in: directory, catalog: restoredCatalog)
        repository = opened; draftStore = openedDrafts; startupFailure = nil
        sessionChanges = SessionChanges()
        reload(); refreshPreservedStores()
        message = "Backup restored and verified in a separate database. The previous database is preserved until you delete it in Backup."
    }

    func refreshPreservedStores() {
        do { preservedStores = try StoreRecovery.preservedStores(in: LocalTransactionRepository.applicationSupportDirectory()) }
        catch { preservedStores = [] }
    }
    func deletePreservedStore(_ id: String) throws {
        try StoreRecovery.deletePreservedStore(id: id, in: LocalTransactionRepository.applicationSupportDirectory())
        refreshPreservedStores()
    }
    func deleteLegacyRecoveryFiles() throws {
        let directory = try LocalTransactionRepository.applicationSupportDirectory()
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard url.lastPathComponent == "BeforeRestore.json" ||
                url.lastPathComponent == "PreviousStore.json" ||
                ((url.lastPathComponent.hasPrefix("BackupConnection-damaged-") || url.lastPathComponent.hasPrefix("PreviousStore-"))
                    && url.pathExtension == "json") else { continue }
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    func backupNow() async {
        guard let repository, startupFailure == nil else { return }
        do {
            if try repository.maintainRetention() { reload() }
            backup?.schedule(try repository.backup()); await backup?.retry()
        }
        catch { message = "Could not prepare automatic backup: \(error.localizedDescription)" }
        if backup?.isCurrent == true {
            do { try cleanupMigratedFiles() }
            catch { message = "The current backup is confirmed, but older local files could not be cleaned: \(error.localizedDescription)" }
        }
    }

    private func shareFile(data: Data, name: String) throws -> URL {
        // Fixed internal prefix and generated UUID names only. Keep recent files
        // so share extensions can finish reading after the sheet closes.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrackPrepared", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func cleanupPreparedFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinTrackPrepared", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let cutoff = Date.now.addingTimeInterval(-7 * 24 * 60 * 60)
        for url in try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey, .isRegularFileKey]) {
            let values = try url.resourceValues(forKeys: [.creationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let date = values.creationDate, date < cutoff,
                  ["json", "fintrack"].contains(url.pathExtension),
                  url.lastPathComponent.hasPrefix("Review-") || url.lastPathComponent.hasPrefix("FinTrack-backup-") else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func cleanupMigratedFiles() throws {
        try Self.cleanupPreparedFiles()
        try Self.cleanupArchivePartials()
    }

    private static func cleanupArchivePartials() throws {
        let support = try LocalTransactionRepository.applicationSupportDirectory()
        let directories = [support.appendingPathComponent("BackupCandidates", isDirectory: true),
            FileManager.default.temporaryDirectory.appendingPathComponent("FinTrackPrepared", isDirectory: true)]
        let cutoff = Date.now.addingTimeInterval(-86_400)
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey]) {
                guard file.lastPathComponent.hasPrefix(".archive-"), file.pathExtension == "partial",
                      UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.dropFirst(9))) != nil else { continue }
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard info.isRegularFile == true, let date = info.contentModificationDate, date < cutoff else { continue }
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    func perform(_ request: ReviewRequest) throws -> LedgerTransaction {
        guard let repository else { throw LedgerError.recordNotFound }
        guard !drafts.contains(where: { $0.id == request.transactionID }) else {
            throw LedgerError.unfinishedDraft
        }
        let before = records.first { $0.id == request.transactionID }
        let record = try repository.perform(request)
        sessionChanges.register(before: before, after: record)
        reload()
        return record
    }

    func nextReviewDraft(after id: UUID, visibleIDs: [UUID]) -> EditorDraft? {
        let index = visibleIDs.firstIndex(of: id) ?? -1
        let order = Array(visibleIDs.dropFirst(index + 1)) + Array(visibleIDs.prefix(max(0, index)))
        for nextID in order where nextID != id {
            if let record = record(id: nextID), record.approval == .unreviewed,
               !record.discussionRequested, !record.draft.treatment.excludedFromReview {
                return editor(for: record)
            }
        }
        return nil
    }
}

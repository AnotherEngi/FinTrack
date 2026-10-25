import Foundation
import Observation
import FinTrackCore
import FinTrackPersistence

@MainActor
@Observable
final class LedgerViewModel {
    private let repository: LocalTransactionRepository?
    private let draftStore: DraftStore?
    let catalog = ReviewCatalog.prototype
    private(set) var records: [LedgerTransaction] = []
    private(set) var drafts: [EditorDraft] = []
    private(set) var startupFailure: String?
    private(set) var sessionChanges = SessionChanges()
    private(set) var workspace = ReviewWorkspace()
    private(set) var discussions: [UUID: DiscussionThread] = [:]
    private(set) var backup: CloudBackup?
    var message: String?

    init() {
        do { try Self.cleanupPreparedFiles() }
        catch { message = "Older temporary review files could not be removed: \(error.localizedDescription)" }
        do {
            let openedRepository = try LocalTransactionRepository.openDefault()
            let openedDraftStore = try DraftStore(directory:
                LocalTransactionRepository.applicationSupportDirectory()
                    .appendingPathComponent("Drafts", isDirectory: true), repository: openedRepository)
            repository = openedRepository
            draftStore = openedDraftStore
            do { backup = try CloudBackup(directory: LocalTransactionRepository.applicationSupportDirectory()) }
            catch { message = "Automatic backup could not start: \(error.localizedDescription)" }
        } catch {
            repository = nil
            draftStore = nil
            startupFailure = error.localizedDescription
        }
        reload()
    }

    func reload() {
        guard let repository, let draftStore else { return }
        do {
            let savedRecords = try repository.fetchAll()
            let savedDrafts = try draftStore.fetchAll()
            let savedWorkspace = try repository.workspace()
            let savedDiscussions = savedWorkspace.discussions(in: savedRecords)
            records = savedRecords; drafts = savedDrafts; workspace = savedWorkspace
            discussions = Dictionary(uniqueKeysWithValues: savedDiscussions.map { ($0.id, $0) })
            backup?.schedule(FullBackup(records: savedRecords, workspace: savedWorkspace))
        } catch {
            message = "Unable to read saved data: \(error.localizedDescription)"
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
            let count = try repository.addSyntheticTableExamples(asOf: TransactionDate(EditorDraft.dateText(.now)))
            reload()
            message = count == 0 ? "Table examples already exist. Your edits were preserved."
                : "Added \(count) fictional table examples. Existing records were preserved."
        } catch { message = error.localizedDescription }
    }

    func loadSpendingSamples() {
        do {
            guard let repository else { throw LedgerError.recordNotFound }
            let count = try repository.addSyntheticSpendingExamples(asOf: TransactionDate(EditorDraft.dateText(.now)))
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
        _ = try repository.acceptNewWeeklyBatch(fileID: id)
        reload()
    }

    func exportBackup() throws -> URL {
        guard let repository else { throw LedgerError.recordNotFound }
        return try shareFile(data: ExchangeJSON.encode(repository.backup()), name: "FinTrack-backup-\(UUID().uuidString).json")
    }

    func validateBackup(_ data: Data) throws -> FullBackup {
        let value = try ExchangeJSON.decode(FullBackup.self, from: data)
        try value.validate(catalog: catalog)
        for (id, raw) in value.workspace.drafts {
            let draft = try JSONDecoder().decode(EditorDraft.self, from: raw)
            guard draft.id.uuidString == id, draft.expectedRevision.map({ $0 > 0 }) ?? true else {
                throw ExchangeError.invalid("A backup draft has an invalid ID/revision.")
            }
        }
        return value
    }

    func restoreBackup(_ value: FullBackup) throws {
        guard let repository else { throw LedgerError.recordNotFound }
        // Retain one local pre-restore recovery copy, not an automatic cloud history.
        let recovery = try LocalTransactionRepository.applicationSupportDirectory().appendingPathComponent("BeforeRestore.json")
        try ExchangeJSON.encode(repository.backup()).write(to: recovery, options: .atomic)
        try repository.restore(value)
        sessionChanges = SessionChanges()
        reload()
    }

    func backupNow() async {
        guard let repository else { return }
        do { backup?.schedule(try repository.backup()); await backup?.retry() }
        catch { message = "Could not prepare automatic backup: \(error.localizedDescription)" }
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
                  url.pathExtension == "json",
                  url.lastPathComponent.hasPrefix("Review-") || url.lastPathComponent.hasPrefix("FinTrack-backup-") else { continue }
            try FileManager.default.removeItem(at: url)
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

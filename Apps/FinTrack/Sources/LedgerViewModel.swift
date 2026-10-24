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
    var message: String?

    init() {
        do {
            let openedRepository = try LocalTransactionRepository.openDefault()
            let openedDraftStore = try DraftStore(directory:
                LocalTransactionRepository.applicationSupportDirectory()
                    .appendingPathComponent("Drafts", isDirectory: true))
            repository = openedRepository
            draftStore = openedDraftStore
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
            records = try repository.fetchAll()
            drafts = try draftStore.fetchAll()
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

    func storeDraft(_ draft: EditorDraft) throws {
        guard let draftStore else { throw LedgerError.recordNotFound }
        try draftStore.write(draft)
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

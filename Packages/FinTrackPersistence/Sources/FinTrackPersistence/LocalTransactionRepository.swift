import Foundation
import SwiftData
import FinTrackCore

@MainActor
public final class LocalTransactionRepository: TransactionRepository {
    private typealias Row = LedgerSchemaV2.StoredTransaction
    private let container: ModelContainer
    private let context: ModelContext
    private let commit: (ModelContext) throws -> Void
    private let fallbackCatalog: ReviewCatalog
    public private(set) var catalog: ReviewCatalog

    public convenience init(storeURL: URL, catalog: ReviewCatalog = .prototype) throws {
        try self.init(storeURL: storeURL, catalog: catalog, commit: { try $0.save() })
    }

    // Injection lets tests exercise real SwiftData rollback after a write failure.
    init(storeURL: URL, catalog: ReviewCatalog = .prototype,
         commit: @escaping (ModelContext) throws -> Void) throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try Self.verifyAmountConvention(at: storeURL)
        let schema = Schema(versionedSchema: LedgerSchemaV3.self)
        let configuration = ModelConfiguration("FinTrack", schema: schema,
            url: storeURL, cloudKitDatabase: .none)
        let openedContainer = try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self,
                                                 configurations: [configuration])
        let openedContext = ModelContext(openedContainer)
        openedContext.autosaveEnabled = false
        container = openedContainer
        context = openedContext
        self.commit = commit
        self.fallbackCatalog = catalog
        self.catalog = catalog
        self.catalog = try workspace().effectiveCatalog(fallback: catalog)
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
            guard FileManager.default.fileExists(atPath: storeURL.path) else {
                throw ExchangeError.invalid("The existing database file is missing. Its marker and recovery files were preserved. Restore a backup or explicitly create a separate empty ledger.")
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
        try LocalTransactionRepository(storeURL: StoreRecovery.activeURL(in: applicationSupportDirectory()), catalog: catalog)
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
        try RefundAccounting.validate(records: fetchAll() + [transaction])
        var workspace = try self.workspace()
        workspace.establishBaseline(records: try fetchAll())
        workspace.recordUserChange(before: nil, after: transaction)
        workspace.drafts.removeValue(forKey: transaction.id.uuidString)
        try committing {
            context.insert(try Row(transaction))
            try writeWorkspace(workspace)
        }
    }

    @discardableResult
    public func update(id: UUID, expectedRevision: Int64, draft: TransactionDraft) throws -> LedgerTransaction {
        guard let stored = try row(id: id) else { throw LedgerError.recordNotFound }
        let current = try stored.value()
        let updated = try current.revising(with: draft, expectedRevision: expectedRevision)
        try updated.validateReviewState(catalog: catalog)
        try RefundAccounting.validate(records: fetchAll().map { $0.id == id ? updated : $0 })
        if updated != current {
            var workspace = try self.workspace()
            workspace.establishBaseline(records: try fetchAll())
            workspace.recordUserChange(before: current, after: updated)
            workspace.drafts.removeValue(forKey: id.uuidString)
            try committing { try stored.apply(updated); try writeWorkspace(workspace) }
        }
        return updated
    }

    public func perform(_ request: ReviewRequest) throws -> LedgerTransaction {
        guard let stored = try row(id: request.transactionID) else { throw LedgerError.recordNotFound }
        let current = try stored.value()
        let updated = try current.applying(request, catalog: catalog)
        if updated != current {
            var workspace = try self.workspace()
            if request.action == .approve || request.action == .resolveDiscussion {
                guard workspace.discussionDrafts?[request.transactionID.uuidString]?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
                    throw ExchangeError.invalid("Finish or discard the unfinished reply before closing this discussion.")
                }
                workspace.discussionDrafts?.removeValue(forKey: request.transactionID.uuidString)
            }
            workspace.establishBaseline(records: try fetchAll())
            workspace.recordUserChange(before: current, after: updated, kind: request.action.rawValue)
            if (request.action == .approve || request.action == .resolveDiscussion), workspace.discussion(for: current) != nil {
                workspace.closeDiscussion(for: updated)
            }
            try committing { try stored.apply(updated); try writeWorkspace(workspace) }
        }
        return updated
    }

    /// Explicit opt-in only; never repopulate an empty store on app launch.
    public func loadSyntheticExamples() throws {
        guard try context.fetchCount(FetchDescriptor<Row>()) == 0 else {
            throw LedgerError.demoRequiresEmptyStore
        }
        let records = try SyntheticTransactions.make()
        var workspace = try self.workspace()
        workspace.establishBaseline(records: [])
        for record in records { workspace.pending.append(FeedbackEvent(before: nil, after: record, kind: "synthetic-example")) }
        try committing {
            for record in records {
                try record.validateReviewState(catalog: catalog)
                context.insert(try Row(record))
            }
            try writeWorkspace(workspace)
        }
    }

    /// Opt-in current-date fixtures for the table. Existing UUIDs and edits win.
    @discardableResult
    public func addSyntheticTableExamples(asOf date: TransactionDate) throws -> Int {
        let existing = Set(try fetchAll().map(\.id))
        let additions = try SyntheticTableExamples.make(asOf: date).filter { !existing.contains($0.id) }
        guard !additions.isEmpty else { return 0 }
        var workspace = try self.workspace()
        workspace.establishBaseline(records: try fetchAll())
        for record in additions { workspace.pending.append(FeedbackEvent(before: nil, after: record, kind: "synthetic-example")) }
        try committing {
            for record in additions {
                try record.validateReviewState(catalog: catalog)
                context.insert(try Row(record))
            }
            try writeWorkspace(workspace)
        }
        return additions.count
    }

    private func row(id: UUID) throws -> Row? {
        var descriptor = FetchDescriptor<Row>(predicate: #Predicate { $0.recordID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func addSyntheticSpendingExamples(asOf date: TransactionDate) throws -> Int {
        let old = try fetchAll()
        let ids = Set(old.map(\.id))
        let additions = try SyntheticSpendingExamples.make(asOf: date).filter { !ids.contains($0.id) }
        guard !additions.isEmpty else { return 0 }
        var workspace = try self.workspace()
        workspace.establishBaseline(records: old)
        for record in additions { workspace.pending.append(FeedbackEvent(before: nil, after: record, kind: "synthetic-example")) }
        try committing {
            for record in additions { context.insert(try Row(record)) }
            try writeWorkspace(workspace)
        }
        return additions.count
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

    public func workspace() throws -> ReviewWorkspace {
        let rows = try context.fetch(FetchDescriptor<LedgerSchemaV3.StoredWorkspace>())
        guard rows.count <= 1 else { throw PersistenceError.invalidStoredValue }
        if let row = rows.first {
            guard row.key == "workspace" else { throw PersistenceError.invalidStoredValue }
            return try JSONDecoder().decode(ReviewWorkspace.self, from: row.payload)
        }
        return ReviewWorkspace()
    }

    public func capacityUsage() throws -> (records: Int, bytes: Int) {
        let rows = try context.fetch(FetchDescriptor<Row>())
        var bytes = 1_048_576
        for row in rows { bytes += (try row.payload?.count ?? JSONEncoder().encode(row.value()).count) + 512 }
        for row in try context.fetch(FetchDescriptor<LedgerSchemaV3.StoredWorkspace>()) { bytes += row.payload.count }
        return (rows.count, bytes)
    }

    @discardableResult
    public func maintainRetention(at: Date = .now) throws -> Bool {
        let original = try workspace()
        let records = try fetchAll()
        let closed = Set(original.discussions(in: records).filter(\.isResolved).map(\.recordID))
        var updates: [LedgerTransaction] = []
        for record in records where (closed.contains(record.id) || (record.approval == .confirmed && !record.discussionRequested))
            && record.revision < Int64.max && original.drafts[record.id.uuidString] == nil
            && original.discussionDrafts?[record.id.uuidString] == nil {
            guard !record.assistantContext.question.isEmpty || !record.assistantContext.reason.isEmpty else { continue }
            updates.append(try LedgerTransaction(id: record.id, revision: record.revision + 1, createdAt: record.createdAt,
                updatedAt: max(at, record.updatedAt), draft: record.draft, approval: record.approval,
                discussionRequested: record.discussionRequested, assistantContext: AssistantContext(ledgerNotes: record.assistantContext.ledgerNotes),
                reviewHistory: record.reviewHistory, classificationProvenance: record.classificationProvenance,
                discussionProgress: record.discussionProgress))
        }
        var updated = original
        let replacements = Dictionary(uniqueKeysWithValues: updates.map { ($0.id, $0) })
        for record in records where closed.contains(record.id) && original.resolvedDiscussions?[record.id.uuidString] != nil {
            updated.closeDiscussion(for: replacements[record.id] ?? record)
        }
        try updated.compactCompletedExchanges(records: records.map { replacements[$0.id] ?? $0 }, at: at)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard try encoder.encode(original) != encoder.encode(updated) || !updates.isEmpty else { return false }
        try committing {
            for record in updates { if let stored = try row(id: record.id) { try stored.apply(record) } }
            try writeWorkspace(updated)
        }
        return true
    }

    private func writeWorkspace(_ value: ReviewWorkspace) throws {
        var value = value
        try value.compactCompletedExchanges(records: fetchAll())
        let rows = try context.fetch(FetchDescriptor<Row>())
        var recordBytes = 0
        for row in rows {
            let bytes = try row.payload?.count ?? JSONEncoder().encode(row.value()).count
            guard bytes <= BackupCapacity.maximumEntryBytes else { throw ExchangeError.invalid("A record exceeds the supported backup-entry size. Your previous saved data was preserved.") }
            recordBytes += bytes + 512
        }
        try BackupCapacity.validate(recordCount: rows.count, recordBytes: recordBytes, workspace: value)
        value.generation = UUID()
        let encoded = try JSONEncoder().encode(value)
        if let row = try context.fetch(FetchDescriptor<LedgerSchemaV3.StoredWorkspace>()).first {
            row.payload = encoded
        } else { context.insert(try LedgerSchemaV3.StoredWorkspace(value)) }
    }

    public func migrateDrafts(_ drafts: [String: Data]) throws {
        var workspace = try self.workspace()
        guard !workspace.legacyDraftsMigrated else { return }
        workspace.drafts.merge(drafts, uniquingKeysWith: { existing, _ in existing })
        workspace.legacyDraftsMigrated = true
        workspace.establishBaseline(records: try fetchAll())
        try committing { try writeWorkspace(workspace) }
    }

    public func saveDraft(id: UUID, data: Data?) throws {
        var workspace = try self.workspace()
        guard workspace.drafts[id.uuidString] != data else { return }
        workspace.drafts[id.uuidString] = data
        try committing { try writeWorkspace(workspace) }
    }

    public func saveSummaryVisibility(_ value: SummaryVisibility) throws {
        try value.validate(recordIDs: Set(fetchAll().map(\.id)))
        var workspace = try self.workspace()
        guard (workspace.summaryVisibility ?? SummaryVisibility()) != value else { return }
        workspace.summaryVisibility = value
        // Display preferences are backed up, but never create financial edits or AI feedback.
        try committing { try writeWorkspace(workspace) }
    }

    public func prepareReview(mode: ReviewMode) throws -> ReviewEnvelope {
        var workspace = try self.workspace()
        let packet = try workspace.prepare(records: fetchAll(), catalog: catalog, mode: mode)
        try committing { try writeWorkspace(workspace) }
        return packet
    }

    public func stageIncoming(_ data: Data) throws {
        var workspace = try self.workspace()
        let count = workspace.staged.count
        let processed = workspace.processedFiles.count
        try workspace.receive(data)
        if count != workspace.staged.count || processed != workspace.processedFiles.count {
            try committing { try writeWorkspace(workspace) }
        }
    }

    public func dismissIncoming(fileID: UUID) throws {
        var workspace = try self.workspace()
        try workspace.dismissIncoming(fileID: fileID, records: fetchAll())
        try committing { try writeWorkspace(workspace) }
    }

    public func markImportSummaryRead(fileID: UUID) throws {
        var workspace = try self.workspace()
        guard let index = workspace.importReceipts?.firstIndex(where: { $0.id == fileID }),
              workspace.importReceipts?[index].unreadSummary != nil else { return }
        workspace.importReceipts?[index].unreadSummary = nil
        try committing { try writeWorkspace(workspace) }
    }

    public func acknowledgeResponse(fileID: UUID) throws {
        var workspace = try self.workspace()
        if workspace.importReceipts?.contains(where: { $0.id == fileID && $0.purpose == "fintrack-review-response" }) == true { return }
        let response = try response(fileID, workspace: workspace)
        guard !workspace.processedFiles.contains(response.id) else { return }
        try workspace.acknowledge(response)
        try committing { try writeWorkspace(workspace) }
    }

    public func decideProposal(fileID: UUID, proposalID: UUID, accept: Bool) throws {
        var workspace = try self.workspace()
        if let receipt = workspace.importReceipts?.first(where: { $0.id == fileID }) {
            guard receipt.decisionIDs?.contains(proposalID) == true else { throw ExchangeError.invalid("This processed reply has no editable financial proposal with that ID.") }
            return
        }
        let response = try response(fileID, workspace: workspace)
        try workspace.validate(response)
        guard !workspace.decidedProposals.contains(proposalID) else { return }
        var updated: LedgerTransaction?
        var prior: LedgerTransaction?
        if let proposal = response.proposals.first(where: { $0.id == proposalID }) {
            guard proposal.categoryID != nil || proposal.tags != nil else {
                throw ExchangeError.invalid("Discussion answers have no accept or reject action. Read or reply in Discussions.")
            }
            prior = try row(id: proposal.recordID)?.value()
            if accept {
                guard workspace.drafts[proposal.recordID.uuidString] == nil else { throw LedgerError.unfinishedDraft }
                guard let stored = try row(id: proposal.recordID) else { throw LedgerError.recordNotFound }
                updated = try stored.value().applyingSuggestion(proposal, catalog: catalog)
                try updated?.validateReviewState(catalog: catalog)
            }
            if let prior {
                workspace.recordUserChange(before: prior, after: updated ?? prior,
                    kind: accept ? "accepted-assistant-change" : "proposal-kept-current")
            }
        } else if let proposal = response.knowledgeProposals.first(where: { $0.id == proposalID }) {
            if accept {
                try workspace.validateKnowledgeFreshness(response)
                if let replacing = proposal.replacingRuleID {
                    guard let index = workspace.knowledge.firstIndex(where: { $0.id == replacing }) else { throw LedgerError.recordNotFound }
                    workspace.knowledge[index] = KnowledgeRule(id: replacing, text: proposal.text, origin: "accepted-assistant")
                } else {
                    guard workspace.knowledge.count < 1_000 else { throw ExchangeError.invalid("The guidance library already contains 1,000 rules. Replace or retire a rule, then prepare a fresh review before adding another.") }
                    workspace.knowledge.append(KnowledgeRule(id: proposal.id, text: proposal.text, origin: "accepted-assistant"))
                }
                workspace.knowledgeVersion = UUID()
                workspace.knowledgeResponseID = response.id
                workspace.pending.append(FeedbackEvent(kind: "knowledge-response", detail: response.id.uuidString))
            }
        } else { throw ExchangeError.invalid("Proposal not found in this response.") }
        workspace.decidedProposals.append(proposalID)
        workspace.pending.append(FeedbackEvent(kind: "proposal-decision",
            detail: "\(accept ? "Accepted" : "Rejected") \(proposalID.uuidString) from \(response.id.uuidString)"))
        try committing {
            if let updated, let stored = try row(id: updated.id) { try stored.apply(updated) }
            try writeWorkspace(workspace)
        }
    }

    public func saveKnowledge(_ rules: [KnowledgeRule]) throws {
        guard rules.count <= 1_000, Set(rules.map(\.id)).count == rules.count,
              rules.allSatisfy({ !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count <= 10_000 }) else {
            throw ExchangeError.invalid("Use up to 1,000 nonempty rules, each at most 10,000 characters.")
        }
        var workspace = try self.workspace()
        guard workspace.knowledge != rules else { return }
        workspace.knowledge = rules; workspace.knowledgeVersion = UUID()
        workspace.knowledgeResponseID = nil
        workspace.pending.append(FeedbackEvent(kind: "knowledge-edit", detail: "User updated classification guidance."))
        try committing { try writeWorkspace(workspace) }
    }

    public func replyToDiscussion(recordID: UUID, expectedRevision: Int64, text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 10_000 else {
            throw ExchangeError.invalid("Enter a reply of up to 10,000 characters.")
        }
        var workspace = try self.workspace()
        guard workspace.drafts[recordID.uuidString] == nil else { throw LedgerError.unfinishedDraft }
        guard let stored = try row(id: recordID) else { throw LedgerError.recordNotFound }
        let before = try stored.value()
        var draft = before.draft; draft.answer = text
        var saved = try before.revising(with: draft, expectedRevision: expectedRevision)
        if !saved.draft.treatment.excludedFromReview {
            saved = try saved.applying(ReviewRequest(transactionID: recordID, expectedRevision: saved.revision,
                action: .discuss), catalog: catalog)
        }
        let reply = UserDiscussionReply(recordID: recordID, sentRevision: String(saved.revision), text: text,
            respondingTo: workspace.discussion(for: before)?.answers.last?.id)
        if workspace.discussionReplies == nil { workspace.discussionReplies = [] }
        workspace.discussionReplies?.append(reply)
        workspace.discussionDrafts?.removeValue(forKey: recordID.uuidString)
        workspace.recordUserChange(before: before, after: saved, kind: "discussion-reply")
        try committing { try stored.apply(saved); try writeWorkspace(workspace) }
    }

    public func resolveDiscussion(recordID: UUID, expectedRevision: Int64) throws {
        var workspace = try self.workspace()
        guard workspace.drafts[recordID.uuidString] == nil else { throw LedgerError.unfinishedDraft }
        guard workspace.discussionDrafts?[recordID.uuidString] == nil else { throw LedgerError.unfinishedDraft }
        guard let stored = try row(id: recordID) else { throw LedgerError.recordNotFound }
        let before = try stored.value()
        guard before.revision == expectedRevision else { throw LedgerError.staleRevision }
        guard workspace.discussion(for: before) != nil else { throw ExchangeError.invalid("This transaction has no discussion to resolve.") }
        if workspace.discussion(for: before)?.isResolved == true { return }
        let saved = try before.applying(ReviewRequest(transactionID: recordID, expectedRevision: expectedRevision,
            action: .resolveDiscussion), catalog: catalog)
        workspace.resolveDiscussion(for: saved)
        workspace.recordUserChange(before: before, after: saved, kind: "resolveDiscussion")
        try committing { try stored.apply(saved); try writeWorkspace(workspace) }
    }

    public func saveDiscussionDraft(recordID: UUID, expectedRevision: Int64, text: String) throws {
        guard text.count <= 10_000, expectedRevision > 0 else {
            throw ExchangeError.invalid("Use a reply of up to 10,000 characters.")
        }
        guard let stored = try row(id: recordID) else { throw LedgerError.recordNotFound }
        guard expectedRevision <= (try stored.value().revision) else { throw LedgerError.staleRevision }
        var workspace = try self.workspace()
        let value = text.isEmpty ? nil : DiscussionDraft(recordID: recordID, expectedRevision: String(expectedRevision), text: text)
        guard workspace.discussionDrafts?[recordID.uuidString] != value else { return }
        if workspace.discussionDrafts == nil { workspace.discussionDrafts = [:] }
        workspace.discussionDrafts?[recordID.uuidString] = value
        try committing { try writeWorkspace(workspace) }
    }

    private func response(_ id: UUID, workspace: ReviewWorkspace) throws -> ReviewResponse {
        guard let file = workspace.staged.first(where: { $0.id == id && $0.purpose == "fintrack-review-response" }) else {
            throw ExchangeError.invalid("Review response not found.")
        }
        return try ExchangeJSON.decode(ReviewResponse.self, from: file.data)
    }

    /// Accept a source row, or explicitly reconcile it to a current record revision.
    /// The original source evidence is retained; user annotations are never replaced.
    public func acceptWeekly(fileID: UUID, identity: BankIdentity, matchingRecordID: UUID? = nil,
                             expectedRevision: Int64? = nil, allowSeparate: Bool = false) throws {
        var workspace = try self.workspace()
        if workspace.importReceipts?.contains(where: { $0.id == fileID && $0.purpose == "fintrack-weekly-intake" && $0.disposition == "processed" }) == true,
           workspace.sourceLinks.contains(where: { $0.identity == identity }) { return }
        guard let file = workspace.staged.first(where: { $0.id == fileID && $0.purpose == "fintrack-weekly-intake" }) else {
            throw ExchangeError.invalid("Weekly batch not found.")
        }
        let batch = try ExchangeJSON.decode(WeeklyBatch.self, from: file.data)
        guard let source = batch.transactions.first(where: { $0.identity == identity }) else { throw LedgerError.recordNotFound }
        let linkIndex = workspace.sourceLinks.firstIndex { $0.identity == identity }
        if let linkIndex, workspace.sourceLinks[linkIndex].latest == source { return }
        if let linkIndex {
            let link = workspace.sourceLinks[linkIndex]
            let digest = ContentDigest.sha256(try ExchangeJSON.encode(source))
            guard link.supersededBy == nil, !(link.supersededDigests ?? []).contains(digest) else {
                throw ExchangeError.invalid("This source version has been superseded. It cannot replace newer reconciled facts.")
            }
        }
        let existingID = linkIndex.map { workspace.sourceLinks[$0].recordID } ?? matchingRecordID
        let all = try fetchAll()
        let saved: LedgerTransaction
        if let existingID {
            guard workspace.drafts[existingID.uuidString] == nil else { throw LedgerError.unfinishedDraft }
            guard let old = all.first(where: { $0.id == existingID }), let expectedRevision else { throw LedgerError.staleRevision }
            var draft = old.draft
            let facts = try source.draft(sourceID: old.draft.source?.id ?? UUID())
            draft.date = facts.date; draft.activityDate = facts.activityDate; draft.payee = facts.payee
            draft.amount = facts.amount; draft.postingStatus = facts.postingStatus; draft.treatment = facts.treatment
            draft.source = facts.source
            saved = try old.revising(with: draft, expectedRevision: expectedRevision)
        } else {
            // Unlinked manual/history rows can be the same purchase. Require explicit
            // reconciliation rather than silently duplicating them.
            let facts = try source.draft(sourceID: all.first(where: { $0.draft.source?.label == identity.sourceAlias })?.draft.source?.id ?? UUID())
            let ambiguous = try !IntakeMatching.candidates(for: source, in: all).isEmpty
            guard !ambiguous || allowSeparate else { throw ExchangeError.invalid("Possible existing transaction, including a linked pending charge. Choose Reconcile and the matching record, or explicitly add a separate purchase.") }
            if let category = facts.categoryID, catalog.category(id: category) == nil { throw ReviewError.unresolvedCategory }
            let origins = Dictionary(uniqueKeysWithValues: facts.tags.map { ($0, ValueOrigin.assistant) })
            saved = try LedgerTransaction(draft: facts, classificationProvenance: .init(
                category: facts.categoryID == nil ? .unknown : .assistant, tags: origins))
        }
        try saved.validateReviewState(catalog: catalog)
        try RefundAccounting.validate(records: all.filter { $0.id != saved.id } + [saved])
        if let linkIndex {
            if workspace.sourceLinks[linkIndex].supersededDigests == nil { workspace.sourceLinks[linkIndex].supersededDigests = [] }
            let oldDigest = ContentDigest.sha256(try ExchangeJSON.encode(workspace.sourceLinks[linkIndex].latest))
            workspace.sourceLinks[linkIndex].supersededDigests?.insert(oldDigest)
            workspace.sourceLinks[linkIndex].latest = source
        }
        else { workspace.sourceLinks.append(SourceLink(identity: identity, recordID: saved.id, original: source)) }
        if source.postingStatus == .posted {
            for index in workspace.sourceLinks.indices where workspace.sourceLinks[index].recordID == saved.id
                && workspace.sourceLinks[index].identity != identity && workspace.sourceLinks[index].latest.postingStatus == .pending {
                workspace.sourceLinks[index].supersededBy = identity
            }
        }
        try committing {
            if let stored = try row(id: saved.id) { try stored.apply(saved) }
            else { context.insert(try Row(saved)) }
            try writeWorkspace(workspace)
        }
    }

    public func backup() throws -> FullBackup {
        FullBackup(records: try fetchAll(), workspace: try workspace())
    }

    /// New source identities only; existing-source changes stay for explicit
    /// reconciliation. Any ambiguous row or failure rolls the whole addition back.
    @discardableResult
    public func acceptNewWeeklyBatch(fileID: UUID) throws -> Int {
        var workspace = try self.workspace()
        if workspace.importReceipts?.contains(where: { $0.id == fileID && $0.purpose == "fintrack-weekly-intake" && $0.disposition == "processed" }) == true { return 0 }
        guard let file = workspace.staged.first(where: { $0.id == fileID && $0.purpose == "fintrack-weekly-intake" }) else {
            throw ExchangeError.invalid("Weekly batch not found.")
        }
        let batch = try ExchangeJSON.decode(WeeklyBatch.self, from: file.data)
        let existing = try fetchAll()
        let identities = Set(workspace.sourceLinks.map(\.identity))
        var additions: [LedgerTransaction] = []
        var candidates = IntakeMatching.Index(records: existing)
        var sources: [String: UUID] = [:]
        for record in existing { if let source = record.draft.source { sources[source.label] = source.id } }
        for source in batch.transactions where !identities.contains(source.identity) {
            let sourceID = sources[source.identity.sourceAlias] ?? UUID()
            sources[source.identity.sourceAlias] = sourceID
            let facts = try source.draft(sourceID: sourceID)
            guard try candidates.candidates(for: source).isEmpty else {
                throw ExchangeError.invalid("Possible existing transaction for \(source.merchant), including a linked pending purchase or another row in this file. Reconcile it first; no batch additions were saved.")
            }
            if let category = facts.categoryID, catalog.category(id: category) == nil { throw ReviewError.unresolvedCategory }
            let record = try LedgerTransaction(draft: facts, classificationProvenance: .init(
                category: facts.categoryID == nil ? .unknown : .assistant,
                tags: Dictionary(uniqueKeysWithValues: facts.tags.map { ($0, ValueOrigin.assistant) })))
            try record.validateReviewState(catalog: catalog)
            additions.append(record)
            candidates.add(record)
            workspace.sourceLinks.append(SourceLink(identity: source.identity, recordID: record.id, original: source))
        }
        guard !additions.isEmpty else { return 0 }
        workspace.establishBaseline(records: existing)
        try committing {
            for record in additions { context.insert(try Row(record)) }
            try writeWorkspace(workspace)
        }
        return additions.count
    }

    /// Caller validates app-specific raw drafts before this atomic replacement.
    public func restore(_ backup: FullBackup) throws {
        try backup.validate(catalog: fallbackCatalog)
        let previousCatalog = catalog
        catalog = try backup.workspace.effectiveCatalog(fallback: fallbackCatalog)
        do {
        try committing {
            let wanted = Set(backup.records.map(\.id))
            let existing = try context.fetch(FetchDescriptor<Row>())
            let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.recordID, $0) })
            for stored in existing where !wanted.contains(stored.recordID) { context.delete(stored) }
            for record in backup.records {
                if let stored = byID[record.id] {
                    stored.createdAt = record.createdAt
                    try stored.apply(record)
                } else { context.insert(try Row(record)) }
            }
            var workspace = backup.workspace
            workspace.legacyDraftsMigrated = true
            try writeWorkspace(workspace)
        }
        } catch { catalog = previousCatalog; throw error }
    }
}

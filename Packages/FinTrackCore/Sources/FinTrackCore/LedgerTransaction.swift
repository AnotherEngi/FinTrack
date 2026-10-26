import Foundation

public struct TransactionDraft: Codable, Equatable, Sendable {
    public var date: TransactionDate
    public var payee: String
    public var amount: Money
    public var notes: String
    public var answer: String
    public var postingStatus: PostingStatus
    public var treatment: TransactionTreatment
    public var categoryID: String?
    public var tags: [String]
    public var exceptionalEvent: Bool?
    public var reportedExceptional: SourceValue
    public var activityDate: TransactionDate?
    public var source: TransactionSource?
    public var refundAllocations: [RefundAllocation]?
    public var primarySubcategoryID: String?
    public var allocations: [ExpenseAllocation]
    public var sourceVersions: [SourceVersion]
    public var historicalDecisions: [HistoricalDecision]
    public var sourceNotes: [SourceText]
    public var archivalFields: [String: ArchivalField]
    public var reportedVisibility: SourceValue
    public var questionState: QuestionState
    public var sourceReportDate: TransactionDate?

    public init(date: TransactionDate, payee: String, amount: Money,
                notes: String = "", answer: String = "", postingStatus: PostingStatus = .posted,
                treatment: TransactionTreatment = .unresolved, categoryID: String? = nil,
                tags: [String] = [], exceptionalEvent: Bool? = nil, reportedExceptional: SourceValue = .unknown,
                activityDate: TransactionDate? = nil,
                source: TransactionSource? = nil, refundAllocations: [RefundAllocation]? = nil,
                primarySubcategoryID: String? = nil, allocations: [ExpenseAllocation] = [], sourceVersions: [SourceVersion] = [],
                historicalDecisions: [HistoricalDecision] = [], sourceNotes: [SourceText] = [], archivalFields: [String: ArchivalField] = [:],
                reportedVisibility: SourceValue = .unknown, questionState: QuestionState = .none, sourceReportDate: TransactionDate? = nil) {
        self.date = date
        self.payee = payee
        self.amount = amount
        self.notes = notes
        self.answer = answer
        self.postingStatus = postingStatus
        self.treatment = treatment
        self.categoryID = categoryID
        self.tags = tags
        self.exceptionalEvent = exceptionalEvent
        self.reportedExceptional = reportedExceptional
        self.activityDate = activityDate
        self.primarySubcategoryID = primarySubcategoryID; self.allocations = allocations; self.sourceVersions = sourceVersions
        self.historicalDecisions = historicalDecisions; self.sourceNotes = sourceNotes; self.archivalFields = archivalFields
        self.reportedVisibility = reportedVisibility; self.questionState = questionState; self.sourceReportDate = sourceReportDate
        self.source = source
        self.refundAllocations = refundAllocations
    }

    public func validate() throws {
        let links = refundAllocations ?? []
        guard links.count <= 100, Set(links.map { $0.purchaseID.uuidString + ($0.allocationID?.uuidString ?? "primary") }).count == links.count else {
            throw ExchangeError.invalid("Duplicate refund targets or more than 100 allocations.")
        }
        var allocated: Int64 = 0
        for link in links {
            let (sum, overflow) = allocated.addingReportingOverflow(link.amount.minorUnits)
            guard treatment == .refund, postingStatus == .posted,
                  link.amount.minorUnits > 0, link.amount.currency == amount.currency, !overflow,
                  UInt64(sum) <= amount.minorUnits.magnitude else {
                throw ExchangeError.invalid("Enter positive allocations within the posted refund amount, in the same currency.")
            }
            allocated = sum
        }
        if let source {
            guard !source.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  source.label.count <= 120 else { throw ReviewError.invalidSource }
        }
        guard !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError.missingPayee
        }
        if treatment == .spending && amount.minorUnits < 0 { throw ReviewError.invalidAmountSign }
        if (treatment == .refund || treatment == .income || treatment == .reimbursementReceipt) && amount.minorUnits > 0 {
            throw ReviewError.invalidAmountSign
        }
        guard tags.count <= 20, Set(tags).count == tags.count,
              tags.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 }) else {
            throw ReviewError.invalidTags
        }
    }

    func changesApproval(comparedTo old: Self) -> Bool {
        date != old.date || activityDate != old.activityDate || payee != old.payee
            || amount != old.amount || postingStatus != old.postingStatus || treatment != old.treatment
            || categoryID != old.categoryID || Set(tags) != Set(old.tags)
            || exceptionalEvent != old.exceptionalEvent || source != old.source
            || (refundAllocations ?? []) != (old.refundAllocations ?? [])
            || primarySubcategoryID != old.primarySubcategoryID || allocations != old.allocations
    }

}

public enum QuestionState: String, Codable, CaseIterable, Sendable { case none, open, unknown, resolved }

extension TransactionDraft {
    public var components: [ExpenseAllocation] {
        allocations.isEmpty ? [.init(id: Self.primaryAllocationID, categoryID: categoryID ?? "", subcategoryID: primarySubcategoryID, amount: amount)] : allocations
    }
    public static let primaryAllocationID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    public func validateAllocations(catalog: ReviewCatalog) throws {
        try requireFinance(allocations.count <= 100 && Set(allocations.map(\.id)).count == allocations.count, "Duplicate or excessive expense allocations.")
        if let categoryID { try requireFinance(catalog.category(id: categoryID) != nil, "Unknown primary category.") }
        if let sub = primarySubcategoryID { try requireFinance(catalog.category(id: categoryID)?.subcategories.contains { $0.id == sub } == true, "Unknown primary subcategory.") }
        if !allocations.isEmpty {
            try requireFinance(treatment == .spending && amount.minorUnits >= 0, "Only purchases have category allocations.")
            var total: Int64 = 0
            for part in allocations {
                guard let category = catalog.category(id: part.categoryID) else { throw ReviewError.unresolvedCategory }
                try requireFinance(part.amount.minorUnits > 0 && part.amount.currency == amount.currency, "Split amounts must be positive and in the parent currency.")
                if let sub = part.subcategoryID { try requireFinance(category.subcategories.contains { $0.id == sub }, "Unknown split subcategory.") }
                total = try addCents(total, part.amount.minorUnits)
            }
            try requireFinance(total == amount.minorUnits, "Split allocations must balance exactly to the parent purchase.")
        }
    }
    public func validateEvidence() throws {
        try requireFinance(sourceVersions.count <= 1_000 && sourceNotes.count <= 1_000 && historicalDecisions.count <= 10_000 && archivalFields.count <= 1_000, "Financial evidence exceeds per-record limits.")
        try reportedVisibility.validate()
        try reportedExceptional.validate()
        for field in archivalFields.values { try field.value.validate() }
        try requireFinance(Set(sourceVersions.map(\.id)).count == sourceVersions.count, "Duplicate source version IDs.")
        let versions = Dictionary(uniqueKeysWithValues: sourceVersions.map { ($0.id, $0) })
        let successors = sourceVersions.compactMap(\.successorID)
        try requireFinance(Set(successors).count == successors.count, "Source lifecycle must be a single chain, not a fork.")
        for version in sourceVersions {
            try requireFinance(!version.merchant.isEmpty, "Source versions retain their original observed posting state and merchant.")
            try requireFinance(version.merchant.count <= 500 && version.notes.count <= 1_000 && version.decisions.count <= 10_000, "Oversized source version.")
            try requireFinance(version.notes.allSatisfy { ![TextOwnership.assistantQuestion, .assistantReason].contains($0.ownership) }, "Transient assistant text cannot be archived in financial versions.")
            var next = version.successorID; var seen: Set<UUID> = [version.id]
            while let id = next { guard let target = versions[id], seen.insert(id).inserted else { throw ExchangeError.invalid("Missing or cyclic source successor.") }; next = target.successorID }
        }
        try requireFinance(sourceVersions.filter { $0.successorID == nil }.count <= 1, "A transaction may have only one active source version.")
        for decision in historicalDecisions + sourceVersions.flatMap(\.decisions) { try requireFinance(!decision.evidence.isEmpty, "Historical decisions require evidence; unknown decision time remains unknown.") }
    }
    public func clearingResolvedAssistantText() -> Self {
        var value = self; value.questionState = .resolved
        value.sourceNotes.removeAll { [.assistantQuestion, .assistantReason].contains($0.ownership) }
        value.archivalFields = value.archivalFields.filter { ![TextOwnership.assistantQuestion, .assistantReason].contains($0.value.ownership) }
        return value
    }
}

public struct LedgerTransaction: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let revision: Int64
    public let createdAt: Date
    public let updatedAt: Date
    public let draft: TransactionDraft
    public let approval: ApprovalStatus
    public let discussionRequested: Bool
    public let assistantContext: AssistantContext
    public let reviewHistory: [ReviewDecision]
    public let classificationProvenance: ClassificationProvenance
    public let discussionProgress: DiscussionProgress?

    public init(id: UUID = UUID(), revision: Int64 = 1, createdAt: Date = .now,
                updatedAt: Date? = nil, draft: TransactionDraft, approval: ApprovalStatus? = nil,
                discussionRequested: Bool = false, assistantContext: AssistantContext = .init(),
                reviewHistory: [ReviewDecision] = [],
                classificationProvenance: ClassificationProvenance = .init(),
                discussionProgress: DiscussionProgress? = nil) throws {
        try draft.validate()
        guard revision > 0 else { throw LedgerError.invalidRevision }
        let updated = updatedAt ?? createdAt
        guard updated >= createdAt else { throw LedgerError.invalidTimestamp }
        self.id = id
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updated
        let resolved = draft.questionState == .resolved && !discussionRequested
        let savedDraft = resolved ? draft.clearingResolvedAssistantText() : draft
        let savedContext = resolved ? AssistantContext(ledgerNotes: assistantContext.ledgerNotes) : assistantContext
        self.draft = savedDraft
        self.approval = approval ?? (savedDraft.treatment.excludedFromReview && !discussionRequested && ![.open, .unknown].contains(savedDraft.questionState)
            && savedContext.question.isEmpty ? .notApplicable : .unreviewed)
        self.discussionRequested = discussionRequested
        self.assistantContext = savedContext
        self.reviewHistory = reviewHistory
        self.classificationProvenance = classificationProvenance
        guard discussionRequested || discussionProgress == nil else { throw ReviewError.discussionNotRequested }
        self.discussionProgress = discussionRequested ? discussionProgress ?? .awaitingExport : nil
        try validateReviewState()
    }

    public func revising(with draft: TransactionDraft, expectedRevision: Int64,
                         at timestamp: Date = .now) throws -> Self {
        guard revision == expectedRevision else { throw LedgerError.staleRevision }
        try draft.validate()
        if draft == self.draft { return self }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw LedgerError.invalidRevision }
        let open = discussionRequested || [.open, .unknown].contains(draft.questionState) || !assistantContext.question.isEmpty
        let nextApproval: ApprovalStatus = open ? .unreviewed : draft.treatment.excludedFromReview ? .notApplicable
            : (draft.changesApproval(comparedTo: self.draft) || approval == .notApplicable ? .unreviewed : approval)
        return try Self(id: id, revision: next, createdAt: createdAt,
            updatedAt: max(timestamp, updatedAt), draft: draft, approval: nextApproval,
            discussionRequested: discussionRequested,
            assistantContext: assistantContext, reviewHistory: reviewHistory,
            classificationProvenance: classificationProvenance.afterManualEdit(from: self.draft, to: draft),
            discussionProgress: discussionProgress)
    }

    public func reviewBlockReason(for action: ReviewAction, catalog: ReviewCatalog) -> String? {
        do { try checkReviewAction(action, catalog: catalog); return nil }
        catch { return error.localizedDescription }
    }

    public func applying(_ request: ReviewRequest, catalog: ReviewCatalog,
                         at timestamp: Date = .now) throws -> Self {
        guard request.transactionID == id else { throw ReviewError.wrongTransaction }
        if let previous = reviewHistory.first(where: { $0.id == request.id }) {
            guard previous.request == request else { throw ReviewError.operationIDReused }
            return self
        }
        guard request.expectedRevision == revision else { throw LedgerError.staleRevision }
        try checkReviewAction(request.action, catalog: catalog)
        if request.action == .skip { return self }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw LedgerError.invalidRevision }
        let appliedAt = max(timestamp, updatedAt)
        let decision = ReviewDecision(request: request, appliedRevision: next, createdAt: appliedAt)
        let nextApproval: ApprovalStatus = [.discuss, .markDiscussionInProgress].contains(request.action) ? .unreviewed : request.action == .approve ? .confirmed
            : request.action == .reopen ? .unreviewed : approval
        let discusses = request.action == .discuss || request.action == .markDiscussionInProgress
        let context = request.action == .approve || request.action == .resolveDiscussion
            ? AssistantContext(ledgerNotes: assistantContext.ledgerNotes) : assistantContext
        var nextDraft = draft
        if request.action == .approve || request.action == .resolveDiscussion { nextDraft = draft.clearingResolvedAssistantText() }
        if discusses { nextDraft.questionState = .open }
        return try Self(id: id, revision: next, createdAt: createdAt, updatedAt: appliedAt,
            draft: nextDraft, approval: nextApproval, discussionRequested: discusses,
            assistantContext: context, reviewHistory: reviewHistory + [decision],
            classificationProvenance: classificationProvenance,
            discussionProgress: discusses ? (request.action == .discuss ? .awaitingExport : .reviewingInChatGPT) : nil)
    }

    public func validateReviewState(catalog: ReviewCatalog? = nil) throws {
        try classificationProvenance.validate(for: draft)
        if discussionRequested || [.open, .unknown].contains(draft.questionState) || !assistantContext.question.isEmpty
            || draft.sourceNotes.contains(where: { $0.ownership == .assistantQuestion && !$0.text.isEmpty }) {
            try requireFinance(approval == .unreviewed, "An unresolved question must be currently unapproved, including excluded and pending records.")
        }
        guard discussionRequested == (discussionProgress != nil) else { throw ReviewError.invalidApproval }
        if approval == .confirmed {
            try requireFinance(!discussionRequested && ![.open, .unknown].contains(draft.questionState) && assistantContext.question.isEmpty, "An unresolved question means currently unapproved; retain earlier approvals as historical evidence.")
            guard draft.postingStatus == .posted, draft.treatment.contributesToSpending,
                  let categoryID = draft.categoryID, !categoryID.isEmpty else { throw ReviewError.invalidApproval }
            if let catalog { try checkReviewAction(.approve, catalog: catalog) }
        }
        guard approval != .notApplicable || draft.treatment.excludedFromReview else { throw ReviewError.invalidApproval }
        try draft.validateEvidence()
        if let catalog { try draft.validateAllocations(catalog: catalog) }
        guard Set(reviewHistory.map(\.id)).count == reviewHistory.count else { throw ReviewError.invalidHistory }
        var previousRevision: Int64 = 0
        for entry in reviewHistory {
            let (next, overflow) = entry.request.expectedRevision.addingReportingOverflow(1)
            guard !overflow, entry.request.expectedRevision > 0,
                  entry.request.transactionID == id, entry.request.action != .skip,
                  entry.appliedRevision == next, entry.appliedRevision <= revision,
                  entry.appliedRevision > previousRevision, entry.createdAt >= createdAt,
                  entry.createdAt <= updatedAt else { throw ReviewError.invalidHistory }
            previousRevision = entry.appliedRevision
        }
    }

    private func checkReviewAction(_ action: ReviewAction, catalog: ReviewCatalog) throws {
        if action == .skip || action == .resolveDiscussion { return }
        if action == .markDiscussionInProgress && !discussionRequested { throw ReviewError.discussionNotRequested }
        if action == .approve {
            guard !draft.treatment.excludedFromReview else { throw ReviewError.excludedTreatment }
            if draft.postingStatus == .pending { throw ReviewError.pendingApproval }
            guard draft.postingStatus == .posted else { throw ReviewError.unresolvedPosting }
            guard draft.treatment.contributesToSpending else { throw ReviewError.unresolvedTreatment }
            guard let category = catalog.category(id: draft.categoryID), !category.unresolved,
                  !category.excluded else { throw ReviewError.unresolvedCategory }
            try draft.validateAllocations(catalog: catalog)
            if let id = draft.primarySubcategoryID {
                guard let sub = category.subcategories.first(where: { $0.id == id }), !sub.unresolved, !sub.excluded else { throw ReviewError.unresolvedCategory }
            }
            for part in draft.allocations {
                guard let category = catalog.category(id: part.categoryID), !category.unresolved, !category.excluded else { throw ReviewError.unresolvedCategory }
                if let id = part.subcategoryID { guard let sub = category.subcategories.first(where: { $0.id == id }), !sub.unresolved, !sub.excluded else { throw ReviewError.unresolvedCategory } }
            }
        }
        if action == .discuss {
            guard !draft.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ReviewError.discussionNeedsContext
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, revision, createdAt, updatedAt, draft, approval, discussionRequested, assistantContext, reviewHistory
        case classificationProvenance, discussionProgress
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let revisionText = try values.decode(String.self, forKey: .revision)
        guard let revision = Int64(revisionText), String(revision) == revisionText else { throw LedgerError.invalidRevision }
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            revision: revision,
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt),
            draft: values.decode(TransactionDraft.self, forKey: .draft),
            approval: values.decode(ApprovalStatus.self, forKey: .approval),
            discussionRequested: values.decode(Bool.self, forKey: .discussionRequested),
            assistantContext: values.decode(AssistantContext.self, forKey: .assistantContext),
            reviewHistory: values.decode([ReviewDecision].self, forKey: .reviewHistory),
            classificationProvenance: values.decode(ClassificationProvenance.self, forKey: .classificationProvenance),
            discussionProgress: values.decodeIfPresent(DiscussionProgress.self, forKey: .discussionProgress)
        )
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(String(revision), forKey: .revision)
        try values.encode(createdAt, forKey: .createdAt); try values.encode(updatedAt, forKey: .updatedAt)
        try values.encode(draft, forKey: .draft); try values.encode(approval, forKey: .approval)
        try values.encode(discussionRequested, forKey: .discussionRequested); try values.encode(assistantContext, forKey: .assistantContext)
        try values.encode(reviewHistory, forKey: .reviewHistory); try values.encode(classificationProvenance, forKey: .classificationProvenance)
        try values.encodeIfPresent(discussionProgress, forKey: .discussionProgress)
    }
}

public enum LedgerError: Error, Equatable, LocalizedError {
    case invalidDate, missingPayee, invalidRevision, invalidTimestamp
    case staleRevision, duplicateID, recordNotFound, demoRequiresEmptyStore
    case unfinishedDraft

    public var errorDescription: String? {
        switch self {
        case .unfinishedDraft: "Finish or discard the unsaved draft for this transaction before applying a review action."
        case .invalidDate: "Enter a valid date as YYYY-MM-DD."
        case .missingPayee: "Enter a payee or description."
        case .invalidRevision: "This record has an invalid revision."
        case .invalidTimestamp: "This record has invalid timestamps."
        case .staleRevision: "This record changed after you opened it. Your draft is preserved; reopen the latest record before applying changes."
        case .duplicateID: "A record with this identifier already exists."
        case .recordNotFound: "This record could not be found."
        case .demoRequiresEmptyStore: "Synthetic samples can only be loaded into an empty store."
        }
    }
}

@MainActor
public protocol TransactionRepository {
    func fetchAll() throws -> [LedgerTransaction]
    func insert(_ transaction: LedgerTransaction) throws
    @discardableResult
    func update(id: UUID, expectedRevision: Int64, draft: TransactionDraft) throws -> LedgerTransaction
    func perform(_ request: ReviewRequest) throws -> LedgerTransaction
}

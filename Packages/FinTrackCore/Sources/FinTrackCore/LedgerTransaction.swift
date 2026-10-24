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
    public var exceptionalEvent: Bool
    public var activityDate: TransactionDate?
    public let legacyReviewStatus: LegacyReviewStatus?

    public init(date: TransactionDate, payee: String, amount: Money,
                notes: String = "", answer: String = "", postingStatus: PostingStatus = .posted,
                treatment: TransactionTreatment = .unresolved, categoryID: String? = nil,
                tags: [String] = [], exceptionalEvent: Bool = false,
                activityDate: TransactionDate? = nil, legacyReviewStatus: LegacyReviewStatus? = nil) {
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
        self.activityDate = activityDate
        self.legacyReviewStatus = legacyReviewStatus
    }

    public func validate() throws {
        guard !payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError.missingPayee
        }
        if treatment == .spending && amount.minorUnits < 0 { throw ReviewError.invalidAmountSign }
        if (treatment == .refund || treatment == .income) && amount.minorUnits > 0 {
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
            || exceptionalEvent != old.exceptionalEvent
    }

    private enum CodingKeys: String, CodingKey {
        case date, payee, amount, notes, answer, postingStatus, treatment, categoryID
        case tags, exceptionalEvent, activityDate, legacyReviewStatus, reviewStatus
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(date: values.decode(TransactionDate.self, forKey: .date),
            payee: values.decode(String.self, forKey: .payee),
            amount: values.decode(Money.self, forKey: .amount),
            notes: values.decodeIfPresent(String.self, forKey: .notes) ?? "",
            answer: values.decodeIfPresent(String.self, forKey: .answer) ?? "",
            postingStatus: values.decodeIfPresent(PostingStatus.self, forKey: .postingStatus) ?? .unresolved,
            treatment: values.decodeIfPresent(TransactionTreatment.self, forKey: .treatment) ?? .unresolved,
            categoryID: values.decodeIfPresent(String.self, forKey: .categoryID),
            tags: values.decodeIfPresent([String].self, forKey: .tags) ?? [],
            exceptionalEvent: values.decodeIfPresent(Bool.self, forKey: .exceptionalEvent) ?? false,
            activityDate: values.decodeIfPresent(TransactionDate.self, forKey: .activityDate),
            legacyReviewStatus: values.decodeIfPresent(LegacyReviewStatus.self, forKey: .legacyReviewStatus)
                ?? values.decodeIfPresent(LegacyReviewStatus.self, forKey: .reviewStatus))
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(date, forKey: .date)
        try values.encode(payee, forKey: .payee)
        try values.encode(amount, forKey: .amount)
        try values.encode(notes, forKey: .notes)
        try values.encode(answer, forKey: .answer)
        try values.encode(postingStatus, forKey: .postingStatus)
        try values.encode(treatment, forKey: .treatment)
        try values.encodeIfPresent(categoryID, forKey: .categoryID)
        try values.encode(tags, forKey: .tags)
        try values.encode(exceptionalEvent, forKey: .exceptionalEvent)
        try values.encodeIfPresent(activityDate, forKey: .activityDate)
        try values.encodeIfPresent(legacyReviewStatus, forKey: .legacyReviewStatus)
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

    public init(id: UUID = UUID(), revision: Int64 = 1, createdAt: Date = .now,
                updatedAt: Date? = nil, draft: TransactionDraft, approval: ApprovalStatus? = nil,
                discussionRequested: Bool = false, assistantContext: AssistantContext = .init(),
                reviewHistory: [ReviewDecision] = []) throws {
        try draft.validate()
        guard revision > 0 else { throw LedgerError.invalidRevision }
        let updated = updatedAt ?? createdAt
        guard updated >= createdAt else { throw LedgerError.invalidTimestamp }
        self.id = id
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updated
        self.draft = draft
        self.approval = approval ?? (draft.treatment.excludedFromReview ? .notApplicable : .unreviewed)
        self.discussionRequested = discussionRequested
        self.assistantContext = assistantContext
        self.reviewHistory = reviewHistory
        try validateReviewState()
    }

    public func revising(with draft: TransactionDraft, expectedRevision: Int64,
                         at timestamp: Date = .now) throws -> Self {
        guard revision == expectedRevision else { throw LedgerError.staleRevision }
        try draft.validate()
        if draft == self.draft { return self }
        let (next, overflow) = revision.addingReportingOverflow(1)
        guard !overflow else { throw LedgerError.invalidRevision }
        let nextApproval: ApprovalStatus = draft.treatment.excludedFromReview ? .notApplicable
            : (draft.changesApproval(comparedTo: self.draft) || approval == .notApplicable ? .unreviewed : approval)
        return try Self(id: id, revision: next, createdAt: createdAt,
            updatedAt: max(timestamp, updatedAt), draft: draft, approval: nextApproval,
            discussionRequested: draft.treatment.excludedFromReview ? false : discussionRequested,
            assistantContext: assistantContext, reviewHistory: reviewHistory)
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
        let nextApproval: ApprovalStatus = request.action == .approve ? .confirmed
            : request.action == .reopen ? .unreviewed : approval
        return try Self(id: id, revision: next, createdAt: createdAt, updatedAt: appliedAt,
            draft: draft, approval: nextApproval, discussionRequested: request.action == .discuss,
            assistantContext: assistantContext, reviewHistory: reviewHistory + [decision])
    }

    public func validateReviewState(catalog: ReviewCatalog? = nil) throws {
        if approval == .confirmed {
            guard draft.postingStatus == .posted, draft.treatment.contributesToSpending,
                  let categoryID = draft.categoryID, !categoryID.isEmpty else { throw ReviewError.invalidApproval }
            if let catalog { try checkReviewAction(.approve, catalog: catalog) }
        }
        guard (approval == .notApplicable) == draft.treatment.excludedFromReview,
              !discussionRequested || !draft.treatment.excludedFromReview else { throw ReviewError.invalidApproval }
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
        if action == .skip { return }
        guard !draft.treatment.excludedFromReview else { throw ReviewError.excludedTreatment }
        if action == .approve {
            if draft.postingStatus == .pending { throw ReviewError.pendingApproval }
            guard draft.postingStatus == .posted else { throw ReviewError.unresolvedPosting }
            guard draft.treatment.contributesToSpending else { throw ReviewError.unresolvedTreatment }
            guard let category = catalog.category(id: draft.categoryID), !category.unresolved,
                  !category.excluded else { throw ReviewError.unresolvedCategory }
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
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            revision: values.decode(Int64.self, forKey: .revision),
            createdAt: values.decode(Date.self, forKey: .createdAt),
            updatedAt: values.decode(Date.self, forKey: .updatedAt),
            draft: values.decode(TransactionDraft.self, forKey: .draft),
            approval: values.decodeIfPresent(ApprovalStatus.self, forKey: .approval),
            discussionRequested: values.decodeIfPresent(Bool.self, forKey: .discussionRequested) ?? false,
            assistantContext: values.decodeIfPresent(AssistantContext.self, forKey: .assistantContext) ?? .init(),
            reviewHistory: values.decodeIfPresent([ReviewDecision].self, forKey: .reviewHistory) ?? []
        )
    }
}

public enum LedgerError: Error, Equatable, LocalizedError {
    case invalidDate, missingPayee, invalidRevision, invalidTimestamp
    case staleRevision, duplicateID, recordNotFound, demoRequiresEmptyStore

    public var errorDescription: String? {
        switch self {
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

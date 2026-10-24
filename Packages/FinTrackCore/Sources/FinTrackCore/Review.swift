import Foundation

public enum PostingStatus: String, Codable, CaseIterable, Sendable {
    case posted, pending, unresolved
}

public enum TransactionTreatment: String, Codable, CaseIterable, Sendable {
    case spending, refund, income, payment, statementCredit, transfer, unresolved

    public var contributesToSpending: Bool { self == .spending || self == .refund }
    public var excludedFromReview: Bool {
        switch self {
        case .income, .payment, .statementCredit, .transfer: true
        case .spending, .refund, .unresolved: false
        }
    }
}

public enum ApprovalStatus: String, Codable, Sendable {
    case unreviewed, confirmed, notApplicable
}

/// Preserved prototype metadata; this is never promoted to classification approval.
public enum LegacyReviewStatus: String, Codable, Sendable {
    case needsReview, reviewed
}

public struct AssistantContext: Codable, Equatable, Sendable {
    public let question: String
    public let reason: String
    public let ledgerNotes: String

    public init(question: String = "", reason: String = "", ledgerNotes: String = "") {
        self.question = question
        self.reason = reason
        self.ledgerNotes = ledgerNotes
    }
}

public struct ReviewCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let unresolved: Bool
    public let excluded: Bool

    public init(id: String, label: String, unresolved: Bool = false, excluded: Bool = false) {
        self.id = id
        self.label = label
        self.unresolved = unresolved
        self.excluded = excluded
    }
}

public struct ReviewCatalog: Sendable {
    public let categories: [ReviewCategory]

    public init(categories: [ReviewCategory]) throws {
        guard Set(categories.map(\.id)).count == categories.count,
              categories.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ReviewError.invalidCatalog
        }
        self.categories = categories
    }

    public func category(id: String?) -> ReviewCategory? {
        categories.first { $0.id == id }
    }

    /// Fictional starting choices; this does not claim to be the user's taxonomy.
    public static let prototype = try! ReviewCatalog(categories: [
        ReviewCategory(id: "sample-groceries", label: "Sample groceries"),
        ReviewCategory(id: "sample-transit", label: "Sample transit"),
        ReviewCategory(id: "sample-household", label: "Sample household"),
        ReviewCategory(id: "sample-unresolved", label: "Needs classification", unresolved: true),
        ReviewCategory(id: "sample-excluded", label: "Excluded payment", excluded: true)
    ])
}

public enum ReviewAction: String, Codable, CaseIterable, Sendable {
    case approve, discuss, reopen, skip
}

public struct ReviewRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let transactionID: UUID
    public let expectedRevision: Int64
    public let action: ReviewAction

    public init(id: UUID = UUID(), transactionID: UUID, expectedRevision: Int64, action: ReviewAction) {
        self.id = id
        self.transactionID = transactionID
        self.expectedRevision = expectedRevision
        self.action = action
    }
}

public struct ReviewDecision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { request.id }
    public let request: ReviewRequest
    public let appliedRevision: Int64
    public let createdAt: Date

    public init(request: ReviewRequest, appliedRevision: Int64, createdAt: Date) {
        self.request = request
        self.appliedRevision = appliedRevision
        self.createdAt = createdAt
    }
}

public enum ReviewError: Error, Equatable, LocalizedError {
    case pendingApproval, unresolvedPosting, excludedTreatment, unresolvedTreatment, unresolvedCategory
    case discussionNeedsContext, invalidApproval, invalidHistory, wrongTransaction
    case operationIDReused, invalidCatalog, invalidAmountSign, invalidTags

    public var errorDescription: String? {
        switch self {
        case .pendingApproval: "Pending transactions can be annotated or discussed, then approved after posting."
        case .unresolvedPosting: "Choose the posting status before approving."
        case .excludedTreatment: "Income, payments, statement credits, and transfers are outside spending review."
        case .unresolvedTreatment: "Choose the accounting treatment before approving."
        case .unresolvedCategory: "Choose a resolved spending category before approving."
        case .discussionNeedsContext: "Add your own note or answer about what you want checked."
        case .invalidApproval: "This approval does not match the transaction's posting or classification state."
        case .invalidHistory: "This record has an invalid review history."
        case .wrongTransaction: "This action belongs to a different transaction."
        case .operationIDReused: "This operation ID was already used for different content."
        case .invalidCatalog: "Category identifiers and labels must be nonblank and identifiers must be unique."
        case .invalidAmountSign: "Expenses must be positive; refunds and income must be negative."
        case .invalidTags: "Use at most 20 distinct tags, each with 1 to 80 characters."
        }
    }
}

public struct SpendingTotals: Equatable, Sendable {
    public let posted: Money
    public let pending: Money

    public init(records: [LedgerTransaction]) throws {
        var posted: Int64 = 0
        var pending: Int64 = 0
        for record in records where record.draft.treatment.contributesToSpending {
            let amount = record.draft.amount.minorUnits
            if record.draft.postingStatus == .posted {
                let (next, overflow) = posted.addingReportingOverflow(amount)
                guard !overflow else { throw MoneyError.outOfRange }
                posted = next
            } else if record.draft.postingStatus == .pending {
                let (next, overflow) = pending.addingReportingOverflow(amount)
                guard !overflow else { throw MoneyError.outOfRange }
                pending = next
            }
        }
        self.posted = Money(minorUnits: posted)
        self.pending = Money(minorUnits: pending)
    }
}

import Foundation

public enum PostingStatus: String, Codable, CaseIterable, Sendable {
    case posted, pending, unresolved, superseded
}

public enum TransactionTreatment: String, Codable, CaseIterable, Sendable {
    case spending, refund, reimbursementReceipt, income, payment, statementCredit, transfer, unresolved

    public var contributesToSpending: Bool { self == .spending || self == .refund }
    public var excludedFromReview: Bool {
        switch self {
        case .income, .payment, .statementCredit, .transfer, .reimbursementReceipt: true
        case .spending, .refund, .unresolved: false
        }
    }
}

public enum ApprovalStatus: String, Codable, Sendable {
    case unreviewed, confirmed, notApplicable
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
    public var id: String
    public var label: String
    public var unresolved: Bool
    public var excluded: Bool
    public var storedLabel: String
    public var definition: SourceValue
    public var origin: ValueOrigin
    public var subcategories: [ReviewSubcategory]

    public init(id: String, label: String, unresolved: Bool = false, excluded: Bool = false,
                storedLabel: String? = nil, definition: SourceValue = .unknown, origin: ValueOrigin = .unknown,
                subcategories: [ReviewSubcategory] = []) {
        self.id = id
        self.label = label
        self.unresolved = unresolved
        self.excluded = excluded
        self.storedLabel = storedLabel ?? label; self.definition = definition; self.origin = origin; self.subcategories = subcategories
    }
}

public struct ReviewCatalog: Sendable {
    public let categories: [ReviewCategory]

    public init(categories: [ReviewCategory]) throws {
        guard !categories.isEmpty, categories.count <= 1_000, Set(categories.map(\.id)).count == categories.count,
              categories.allSatisfy({ !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ReviewError.invalidCatalog
        }
        self.categories = categories
        for category in categories {
            try category.definition.validate()
            try requireFinance(category.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "mixed", "Use a primary category and explicit dollar allocations; do not create a Mixed category.")
            try requireFinance(category.id.count <= 120 && category.label.count <= 200 && category.subcategories.count <= 1_000
                && Set(category.subcategories.map(\.id)).count == category.subcategories.count, "Invalid category/subcategory catalog.")
            for subcategory in category.subcategories {
                try requireFinance(!subcategory.id.isEmpty && subcategory.id.count <= 120 && !subcategory.label.isEmpty, "Invalid subcategory.")
                try subcategory.definition.validate()
            }
        }
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
    case approve, discuss, reopen, skip, markDiscussionInProgress, resolveDiscussion
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
    private enum CodingKeys: String, CodingKey { case id, transactionID, expectedRevision, action }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decode(String.self, forKey: .expectedRevision)
        guard let revision = Int64(text), revision > 0, String(revision) == text else { throw LedgerError.invalidRevision }
        self.init(id: try c.decode(UUID.self, forKey: .id), transactionID: try c.decode(UUID.self, forKey: .transactionID), expectedRevision: revision, action: try c.decode(ReviewAction.self, forKey: .action))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(transactionID, forKey: .transactionID)
        try c.encode(String(expectedRevision), forKey: .expectedRevision); try c.encode(action, forKey: .action)
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
    private enum CodingKeys: String, CodingKey { case request, appliedRevision, createdAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let text = try c.decode(String.self, forKey: .appliedRevision)
        guard let revision = Int64(text), revision > 0, String(revision) == text else { throw LedgerError.invalidRevision }
        self.init(request: try c.decode(ReviewRequest.self, forKey: .request), appliedRevision: revision, createdAt: try c.decode(Date.self, forKey: .createdAt))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(request, forKey: .request); try c.encode(String(appliedRevision), forKey: .appliedRevision); try c.encode(createdAt, forKey: .createdAt)
    }
}

public enum ReviewError: Error, Equatable, LocalizedError {
    case pendingApproval, unresolvedPosting, excludedTreatment, unresolvedTreatment, unresolvedCategory
    case discussionNeedsContext, invalidApproval, invalidHistory, wrongTransaction
    case operationIDReused, invalidCatalog, invalidAmountSign, invalidTags
    case invalidSource, invalidProvenance, discussionNotRequested

    public var errorDescription: String? {
        switch self {
        case .invalidSource: "Enter a source label of at most 120 characters, without account numbers or credentials."
        case .invalidProvenance: "Classification provenance does not match this record."
        case .discussionNotRequested: "Request discussion before marking it as being reviewed in ChatGPT."
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

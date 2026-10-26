import Foundation

/// Current raw editor format; incomplete text is durable without becoming money.
public struct TransactionInput: Codable, Equatable, Sendable {
    public var dateText: String
    public var activityDateText: String
    public var payee: String
    public var amountText: String
    public var notes: String
    public var answer: String
    public var postingStatus: PostingStatus
    public var treatment: TransactionTreatment
    public var categoryID: String?
    public var primarySubcategoryID: String?
    public var tagsText: String
    public var exceptionalEvent: Bool?
    public var sourceLabel: String
    public let sourceID: UUID
    public var refundAllocations: [RefundAllocationInput]?
    public var allocations: [ExpenseAllocationInput]
    public var sourceNotes: [SourceText]
    private var base: TransactionDraft?
    public init(dateText: String, activityDateText: String = "", payee: String = "", amountText: String = "", notes: String = "", answer: String = "",
                postingStatus: PostingStatus = .posted, treatment: TransactionTreatment = .unresolved, categoryID: String? = nil,
                tagsText: String = "", exceptionalEvent: Bool? = nil, sourceLabel: String = "", sourceID: UUID = UUID()) {
        self.dateText = dateText; self.activityDateText = activityDateText; self.payee = payee; self.amountText = amountText
        self.notes = notes; self.answer = answer; self.postingStatus = postingStatus; self.treatment = treatment; self.categoryID = categoryID
        self.tagsText = tagsText; self.exceptionalEvent = exceptionalEvent; self.sourceLabel = sourceLabel; self.sourceID = sourceID
        primarySubcategoryID = nil; allocations = []; sourceNotes = []; base = nil
    }
    public init(draft: TransactionDraft) {
        self.init(dateText: draft.date.iso8601, activityDateText: draft.activityDate?.iso8601 ?? "", payee: draft.payee,
            amountText: draft.amount.decimalText, notes: draft.notes, answer: draft.answer, postingStatus: draft.postingStatus,
            treatment: draft.treatment, categoryID: draft.categoryID, tagsText: draft.tags.joined(separator: "; "), exceptionalEvent: draft.exceptionalEvent,
            sourceLabel: draft.source?.label ?? "", sourceID: draft.source?.id ?? UUID())
        base = draft; primarySubcategoryID = draft.primarySubcategoryID; sourceNotes = draft.sourceNotes
        let primary = draft.allocations.first { $0.categoryID == draft.categoryID && $0.subcategoryID == draft.primarySubcategoryID }?.id
        allocations = draft.allocations.map { ExpenseAllocationInput(id: $0.id, categoryID: $0.categoryID, subcategoryID: $0.subcategoryID, amountText: $0.amount.decimalText, isPrimary: $0.id == primary) }
        refundAllocations = draft.refundAllocations?.map { .init(purchaseID: $0.purchaseID, allocationID: $0.allocationID, amountText: $0.amount.decimalText) }
    }
    public func value() throws -> TransactionDraft {
        let money = try Money(decimalText: amountText)
        let date = try TransactionDate(dateText)
        var draft = base ?? TransactionDraft(date: date, payee: payee, amount: money)
        draft.date = date; draft.activityDate = activityDateText.isEmpty ? nil : try TransactionDate(activityDateText)
        draft.payee = payee; draft.amount = money; draft.notes = notes; draft.answer = answer
        draft.postingStatus = postingStatus; draft.treatment = treatment; draft.categoryID = categoryID; draft.primarySubcategoryID = primarySubcategoryID
        let unchangedTags = base.flatMap { tagsText == $0.tags.joined(separator: "; ") ? $0.tags : nil }
        draft.tags = unchangedTags ?? tagsText.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        draft.exceptionalEvent = exceptionalEvent; draft.sourceNotes = sourceNotes
        draft.source = sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .init(id: sourceID, label: sourceLabel)
        draft.refundAllocations = try refundAllocations?.map { .init(purchaseID: $0.purchaseID, amount: try Money(decimalText: $0.amountText), allocationID: $0.allocationID) }
        var parts: [ExpenseAllocation] = []; var secondary: Int64 = 0
        for input in allocations where !input.isPrimary {
            let amount = try Money(decimalText: input.amountText)
            secondary = try addCents(secondary, amount.minorUnits)
            let before = base?.allocations.first { $0.id == input.id }
            parts.append(.init(id: input.id, categoryID: input.categoryID, subcategoryID: input.subcategoryID, amount: amount,
                origin: before?.categoryID == input.categoryID && before?.subcategoryID == input.subcategoryID && before?.amount == amount ? before!.origin : .user))
        }
        if !allocations.isEmpty {
            try requireFinance(secondary >= 0 && secondary <= money.minorUnits, "Secondary split amounts exceed the purchase.")
            let remaining = money.minorUnits - secondary
            if remaining > 0 {
                guard let categoryID else { throw ReviewError.unresolvedCategory }
                let id = allocations.first { $0.isPrimary }?.id ?? TransactionDraft.primaryAllocationID
                let before = base?.allocations.first { $0.id == id }
                let amount = Money(minorUnits: remaining)
                parts.insert(.init(id: id, categoryID: categoryID, subcategoryID: primarySubcategoryID, amount: amount,
                    origin: before?.categoryID == categoryID && before?.subcategoryID == primarySubcategoryID && before?.amount == amount ? before!.origin : .user), at: 0)
            }
        }
        draft.allocations = parts; try draft.validate(); return draft
    }
    /// Advance read-only base evidence after a successful autosave without
    /// replacing the user's in-progress decimal/date text or generating new IDs.
    public mutating func rebase(on saved: TransactionDraft) { base = saved }
}
public struct ExpenseAllocationInput: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var categoryID: String
    public var subcategoryID: String?
    public var amountText: String
    public var isPrimary: Bool
    public init(id: UUID = UUID(), categoryID: String, subcategoryID: String? = nil, amountText: String = "", isPrimary: Bool = false) {
        self.id = id; self.categoryID = categoryID; self.subcategoryID = subcategoryID; self.amountText = amountText; self.isPrimary = isPrimary
    }
}
public struct RefundAllocationInput: Codable, Equatable, Identifiable, Sendable {
    public var id: String { purchaseID.uuidString + (allocationID?.uuidString ?? "primary") }
    public var purchaseID: UUID
    public var allocationID: UUID?
    public var amountText: String
    public init(purchaseID: UUID, allocationID: UUID? = nil, amountText: String = "") { self.purchaseID = purchaseID; self.allocationID = allocationID; self.amountText = amountText }
}

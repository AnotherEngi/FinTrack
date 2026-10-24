import Foundation

public enum LedgerReviewFilter: String, CaseIterable, Sendable {
    case all, unreviewed, discussion, approved, pending, excluded, questions

    public func matches(_ record: LedgerTransaction) -> Bool {
        switch self {
        case .all: true
        case .unreviewed: record.approval == .unreviewed
        case .discussion: record.discussionRequested
        case .approved: record.approval == .confirmed
        case .pending: record.draft.postingStatus == .pending
        case .excluded: record.approval == .notApplicable
        case .questions: record.discussionRequested || (
            !record.assistantContext.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && record.draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

/// The same inclusive date/search/review rules are used for display and export.
public struct LedgerSelection: Sendable {
    public var from: TransactionDate?
    public var through: TransactionDate?
    public var search: String
    public var reviewFilter: LedgerReviewFilter
    public var excludedTags: Set<String>
    public var excludeExceptionalEvents: Bool
    public var categoryLabels: [String: String]

    public init(from: TransactionDate? = nil, through: TransactionDate? = nil,
                search: String = "", reviewFilter: LedgerReviewFilter = .all,
                excludedTags: Set<String> = [], excludeExceptionalEvents: Bool = false,
                categoryLabels: [String: String] = [:]) {
        self.from = from
        self.through = through
        self.search = search
        self.reviewFilter = reviewFilter
        self.excludedTags = excludedTags
        self.excludeExceptionalEvents = excludeExceptionalEvents
        self.categoryLabels = categoryLabels
    }

    public func records(in records: [LedgerTransaction]) -> [LedgerTransaction] {
        records.filter { record in
            let draft = record.draft
            guard from.map({ draft.date >= $0 }) ?? true,
                  through.map({ draft.date <= $0 }) ?? true,
                  reviewFilter.matches(record),
                  !excludeExceptionalEvents || !draft.exceptionalEvent,
                  excludedTags.isDisjoint(with: draft.tags) else { return false }
            let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return query.isEmpty || ([draft.payee, draft.notes, draft.answer, draft.date.iso8601,
                draft.source?.label ?? "", categoryLabels[draft.categoryID ?? ""] ?? draft.categoryID ?? "",
                record.assistantContext.question] + draft.tags).contains {
                    $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                }
        }.sorted {
            $0.draft.date == $1.draft.date ? $0.id.uuidString < $1.id.uuidString
                : $0.draft.date > $1.draft.date
        }
    }
}

public struct SpendingBucket: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let recordIDs: [UUID]
    public let totals: SpendingTotals
}

/// Summarizes only stored, selected records. No missing periods are zero-filled.
public struct LedgerOverview: Sendable {
    public let totals: SpendingTotals
    public let categories: [SpendingBucket]
    public let months: [SpendingBucket]
    public let recordCount: Int
    public let approvedCount: Int
    public let unreviewedCount: Int
    public let discussionCount: Int
    public let questionsCount: Int
    public let omittedFromSpendingCount: Int

    public init(records: [LedgerTransaction], catalog: ReviewCatalog) throws {
        totals = try SpendingTotals(records: records)
        recordCount = records.count
        approvedCount = records.filter { $0.approval == .confirmed }.count
        unreviewedCount = records.filter { $0.approval == .unreviewed }.count
        discussionCount = records.filter { $0.discussionRequested }.count
        questionsCount = records.filter { LedgerReviewFilter.questions.matches($0) }.count
        let spending = records.filter {
            $0.draft.treatment.contributesToSpending && $0.draft.postingStatus != .unresolved
        }
        omittedFromSpendingCount = records.count - spending.count
        let categoryGroups: [String: [LedgerTransaction]] = Dictionary(grouping: spending) { record in
            record.draft.categoryID ?? ""
        }
        var categoryBuckets: [SpendingBucket] = []
        for (key, group) in categoryGroups {
            let label: String
            if let category = catalog.category(id: key) {
                label = category.label
            } else {
                label = key.isEmpty ? "No category" : "Unavailable category: " + key
            }
            let ids = Self.sortedRecordIDs(group)
            let groupTotals = try SpendingTotals(records: group)
            let bucket = SpendingBucket(id: "category:" + key, label: label,
                recordIDs: ids, totals: groupTotals)
            categoryBuckets.append(bucket)
        }
        categoryBuckets.sort { left, right in
            if left.label == right.label { return left.id < right.id }
            return left.label < right.label
        }
        categories = categoryBuckets

        let monthGroups: [String: [LedgerTransaction]] = Dictionary(grouping: spending) { record in
            String(record.draft.date.iso8601.prefix(7))
        }
        var monthBuckets: [SpendingBucket] = []
        for (key, group) in monthGroups {
            let ids = Self.sortedRecordIDs(group)
            let groupTotals = try SpendingTotals(records: group)
            let bucket = SpendingBucket(id: key, label: key, recordIDs: ids, totals: groupTotals)
            monthBuckets.append(bucket)
        }
        monthBuckets.sort { left, right in left.id > right.id }
        months = monthBuckets
    }

    private static func sortedRecordIDs(_ records: [LedgerTransaction]) -> [UUID] {
        var ids: [UUID] = records.map { record in record.id }
        ids.sort { left, right in left.uuidString < right.uuidString }
        return ids
    }
}

public struct LedgerHistoryEntry: Identifiable, Sendable {
    public var id: String { transactionID.uuidString + ":" + decision.id.uuidString }
    public let transactionID: UUID
    public let currentPayee: String
    public let decision: ReviewDecision

    public static func entries(in records: [LedgerTransaction]) -> [Self] {
        var entries: [LedgerHistoryEntry] = []
        for record in records {
            for decision in record.reviewHistory {
                let entry = LedgerHistoryEntry(transactionID: record.id,
                    currentPayee: record.draft.payee, decision: decision)
                entries.append(entry)
            }
        }
        entries.sort { left, right in
            if left.decision.createdAt == right.decision.createdAt { return left.id < right.id }
            return left.decision.createdAt > right.decision.createdAt
        }
        return entries
    }
}

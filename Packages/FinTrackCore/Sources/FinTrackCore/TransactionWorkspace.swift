import Foundation

public struct TransactionDateRange: Equatable, Sendable {
    public let from: TransactionDate
    public let through: TransactionDate

    public init(from: TransactionDate, through: TransactionDate) throws {
        guard from <= through else { throw LedgerError.invalidDate }
        self.from = from
        self.through = through
    }
}

public enum WorkspacePeriod: String, CaseIterable, Sendable {
    case oneMonth, threeMonths, sixMonths, yearToDate, pastYear, custom

    public func range(through: TransactionDate, customFrom: TransactionDate? = nil,
                      customThrough: TransactionDate? = nil) throws -> TransactionDateRange {
        if self == .custom {
            guard let customFrom, let customThrough else { throw LedgerError.invalidDate }
            return try TransactionDateRange(from: customFrom, through: customThrough)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = through.iso8601.split(separator: "-").map { Int($0)! }
        let end = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
        let start: Date
        switch self {
        case .oneMonth: start = calendar.date(byAdding: .month, value: -1, to: end)!
        case .threeMonths: start = calendar.date(byAdding: .month, value: -3, to: end)!
        case .sixMonths: start = calendar.date(byAdding: .month, value: -6, to: end)!
        case .yearToDate: start = calendar.date(from: DateComponents(year: parts[0], month: 1, day: 1))!
        case .pastYear: start = calendar.date(byAdding: .year, value: -1, to: end)!
        case .custom: throw LedgerError.invalidDate
        }
        let components = calendar.dateComponents([.era, .year, .month, .day], from: start)
        guard components.era == 1 else { throw LedgerError.invalidDate }
        // Date-only values must remain inside the supported Gregorian year range.
        let from = try TransactionDate(String(format: "%04d-%02d-%02d",
            components.year!, components.month!, components.day!))
        return try TransactionDateRange(from: from, through: through)
    }
}

public enum TransactionSortColumn: String, CaseIterable, Sendable {
    case activity, question, date, amount, merchant, source, category, tags, review
}

public struct TransactionTableSort: Sendable {
    public var column: TransactionSortColumn
    public var ascending: Bool

    public init(column: TransactionSortColumn = .date, ascending: Bool = false) {
        self.column = column
        self.ascending = ascending
    }

    public func records(_ records: [LedgerTransaction], catalog: ReviewCatalog,
                        changedIDs: Set<UUID> = [], questionIDs: Set<UUID> = []) -> [LedgerTransaction] {
        records.sorted { a, b in
            let order: ComparisonResult
            switch column {
            case .date: order = Self.compare(a.draft.date, b.draft.date)
            case .amount: order = Self.compare(a.draft.amount.minorUnits, b.draft.amount.minorUnits)
            case .merchant: order = Self.text(a.draft.payee, b.draft.payee)
            case .source: order = Self.text(a.draft.source?.label ?? "", b.draft.source?.label ?? "")
            case .category: order = Self.text(catalog.category(id: a.draft.categoryID)?.label ?? a.draft.categoryID ?? "",
                catalog.category(id: b.draft.categoryID)?.label ?? b.draft.categoryID ?? "")
            case .tags: order = Self.text(a.draft.tags.sorted().joined(separator: ";"), b.draft.tags.sorted().joined(separator: ";"))
            case .review: order = Self.compare(Self.reviewScore(a), Self.reviewScore(b))
            case .activity: order = Self.compare(Self.activityScore(a, changedIDs), Self.activityScore(b, changedIDs))
            case .question: order = Self.compare(questionIDs.contains(a.id) ? 1 : 0, questionIDs.contains(b.id) ? 1 : 0)
            }
            if order == .orderedSame { return a.id.uuidString < b.id.uuidString }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ a: T, _ b: T) -> ComparisonResult {
        a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
    }

    private static func text(_ a: String, _ b: String) -> ComparisonResult {
        let locale = Locale(identifier: "en_US_POSIX")
        let left = a.folding(options: .diacriticInsensitive, locale: locale).lowercased()
        let right = b.folding(options: .diacriticInsensitive, locale: locale).lowercased()
        return compare(left, right)
    }

    private static func reviewScore(_ record: LedgerTransaction) -> Int {
        record.approval == .notApplicable ? 0 : record.approval == .unreviewed ? 1 : 2
    }

    private static func activityScore(_ record: LedgerTransaction, _ changed: Set<UUID>) -> Int {
        (record.discussionProgress == .reviewingInChatGPT ? 4 : record.discussionRequested ? 2 : 0)
            + (changed.contains(record.id) ? 1 : 0)
    }
}

/// Owned by the app's long-lived ledger model. Reloading/backgrounding does not
/// change it. Only a successful distinct save/action registers a change.
public struct SessionChanges: Sendable {
    public private(set) var recordIDs: Set<UUID> = []

    public init() {}

    public mutating func register(before: LedgerTransaction?, after: LedgerTransaction) {
        if before != after { recordIDs.insert(after.id) }
    }
}

import Foundation

/// App-owned display preferences. These never remove records or filter exchange files.
public struct SummaryVisibility: Codable, Equatable, Sendable {
    public var recordIDs: Set<UUID>
    public var categoryIDs: Set<String>
    public var tags: Set<String>
    public init(recordIDs: Set<UUID> = [], categoryIDs: Set<String> = [], tags: Set<String> = []) {
        self.recordIDs = recordIDs; self.categoryIDs = categoryIDs; self.tags = tags
    }
    public func hides(_ record: LedgerTransaction) -> Bool {
        recordIDs.contains(record.id) || categoryIDs.contains(record.draft.categoryID ?? "")
            || !tags.isDisjoint(with: record.draft.tags)
    }
    public func validate(recordIDs available: Set<UUID>) throws {
        guard recordIDs.isSubset(of: available), categoryIDs.count <= 1_000, tags.count <= 10_000,
              categoryIDs.allSatisfy({ $0.count <= 120 }),
              tags.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else {
            throw ExchangeError.invalid("Invalid summary visibility settings.")
        }
    }
}

/// Positive amount of a refund assigned to an original purchase. The refund's
/// actual bank date and amount are preserved; reporting uses the purchase date.
public struct RefundAllocation: Codable, Equatable, Sendable {
    public let purchaseID: UUID
    public let amount: Money
    public init(purchaseID: UUID, amount: Money) { self.purchaseID = purchaseID; self.amount = amount }
    private enum CodingKeys: String, CodingKey { case purchaseID, amountMinorUnits, currency }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let text = try values.decode(String.self, forKey: .amountMinorUnits)
        guard let cents = Int64(text), String(cents) == text else {
            throw ExchangeError.invalid("Refund allocation amount must be an exact integer string.")
        }
        purchaseID = try values.decode(UUID.self, forKey: .purchaseID)
        amount = try Money(minorUnits: cents, currency: values.decode(Currency.self, forKey: .currency))
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(purchaseID, forKey: .purchaseID)
        try values.encode(String(amount.minorUnits), forKey: .amountMinorUnits)
        try values.encode(amount.currency, forKey: .currency)
    }
}

public enum RefundAccounting {
    public static func validate(records: [LedgerTransaction]) throws {
        guard Set(records.map(\.id)).count == records.count else { throw LedgerError.duplicateID }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var used: [UUID: Int64] = [:]
        for refund in records {
            try refund.draft.validate()
            for allocation in refund.draft.refundAllocations ?? [] {
                guard let purchase = byID[allocation.purchaseID], purchase.id != refund.id,
                      purchase.draft.treatment == .spending, purchase.draft.postingStatus == .posted,
                      purchase.draft.amount.currency == allocation.amount.currency,
                      purchase.draft.date <= refund.draft.date else {
                    throw ExchangeError.invalid("A refund must link to an earlier posted purchase in the same currency.")
                }
                let (total, overflow) = (used[purchase.id] ?? 0).addingReportingOverflow(allocation.amount.minorUnits)
                guard !overflow, total <= purchase.draft.amount.minorUnits else {
                    throw ExchangeError.invalid("Refund allocations exceed the original purchase. Adjust the links before changing its amount or treatment.")
                }
                used[purchase.id] = total
            }
        }
    }
}

public enum SummaryInterval: String, Sendable { case week, month, year }

public struct SummaryPurchase: Identifiable, Sendable {
    public var id: UUID { recordID }
    public let recordID: UUID
    public let refundIDs: [UUID]
    public let date: TransactionDate
    public let categoryID: String
    public let net: Money
    public let periodID: String
}

public struct SummaryCategory: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let amount: Money
}

public struct SummaryBar: Identifiable, Sendable {
    public var id: String { periodID + ":" + categoryID }
    public let periodID: String
    public let categoryID: String
    public let amount: Money
}

public struct SummaryPeriod: Identifiable, Sendable {
    public let id: String
    public let axisLabel: String
    public let label: String
}

/// Purchase-date accounting, independent of UI coordinates. Refunds received
/// outside the selected date range still reduce their linked original purchases.
/// Unlinked refunds never become guessed negative pie slices or current spending.
public struct SummaryReport: Sendable {
    public let interval: SummaryInterval
    public let purchases: [SummaryPurchase]
    public let categories: [SummaryCategory]
    public let bars: [SummaryBar]
    /// Includes empty periods. Absence of purchases is not proof of bank coverage.
    public let periods: [SummaryPeriod]
    public let pending: Money
    public let total: Money
    public let unallocatedRefundIDs: [UUID]
    public let unallocatedRefundAmount: Money

    public init(records: [LedgerTransaction], catalog: ReviewCatalog,
                from: TransactionDate? = nil, through: TransactionDate? = nil,
                visibility: SummaryVisibility = .init(), showHidden: Bool = false,
                excludedCategories: Set<String> = []) throws {
        try RefundAccounting.validate(records: records)
        let available = records.filter { showHidden || !visibility.hides($0) }
        let spending = available.filter { $0.draft.treatment == .spending }
        // Granularity depends on the selected duration, never on toggled categories
        // or visibility filters. All history uses the full saved purchase span.
        let dates = records.filter { $0.draft.treatment == .spending }
            .map { $0.draft.activityDate ?? $0.draft.date }.sorted()
        let first = from ?? dates.first
        let last = through ?? dates.last
        if let from, let through, from > through { throw LedgerError.invalidDate }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        func date(_ value: TransactionDate) throws -> Date {
            let parts = value.iso8601.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let result = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else {
                throw LedgerError.invalidDate
            }
            return result
        }
        let days: Int
        if let first, let last { days = max(0, calendar.dateComponents([.day], from: try date(first), to: try date(last)).day ?? 0) }
        else { days = 0 }
        let chosen: SummaryInterval = days <= 93 ? .week : days <= 1096 ? .month : .year
        interval = chosen
        func period(_ value: TransactionDate) throws -> String {
            switch chosen {
            case .year: return String(value.iso8601.prefix(4))
            case .month: return String(value.iso8601.prefix(7))
            case .week:
                let actual = try date(value)
                let weekday = calendar.component(.weekday, from: actual)
                guard let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: actual) else { throw LedgerError.invalidDate }
                let parts = calendar.dateComponents([.year, .month, .day], from: monday)
                return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            }
        }
        func inRange(_ value: TransactionDate) -> Bool {
            (from.map { value >= $0 } ?? true) && (through.map { value <= $0 } ?? true)
        }
        var timeline: [SummaryPeriod] = []
        if let first, let last, first <= last {
            let initial = try period(first)
            let padded = chosen == .year ? initial + "-01-01" : chosen == .month ? initial + "-01" : initial
            var cursor = try date(TransactionDate(padded))
            let end = try date(last)
            let component: Calendar.Component = chosen == .week ? .day : chosen == .month ? .month : .year
            let step = chosen == .week ? 7 : 1
            while cursor <= end {
                let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
                let day = try TransactionDate(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
                let id = try period(day)
                let axis = chosen == .week ? (timeline.isEmpty ? String(id.suffix(5)) : "wk \(timeline.count + 1)") : id
                timeline.append(SummaryPeriod(id: id, axisLabel: axis, label: chosen == .week ? "Week of " + id : id))
                guard timeline.count <= 10_000, let next = calendar.date(byAdding: component, value: step, to: cursor), next > cursor else {
                    throw ExchangeError.invalid("Unable to build the selected summary timeline.")
                }
                cursor = next
            }
        }
        periods = timeline
        func add(_ a: Int64, _ b: Int64) throws -> Int64 {
            let (result, overflow) = a.addingReportingOverflow(b)
            guard !overflow else { throw ExchangeError.invalid("Summary exceeds the supported amount range.") }
            return result
        }
        var deductions: [UUID: Int64] = [:], refundIDs: [UUID: [UUID]] = [:]
        var unallocated: [UUID] = [], unallocatedCents: Int64 = 0
        for refund in available where refund.draft.treatment == .refund && refund.draft.postingStatus == .posted {
            var allocated: Int64 = 0
            for link in refund.draft.refundAllocations ?? [] {
                deductions[link.purchaseID] = try add(deductions[link.purchaseID] ?? 0, link.amount.minorUnits)
                refundIDs[link.purchaseID, default: []].append(refund.id)
                allocated = try add(allocated, link.amount.minorUnits)
            }
            // Unsigned magnitude preserves legacy Int64.min values without negation.
            let remainder = refund.draft.amount.minorUnits.magnitude - UInt64(allocated)
            if remainder > 0, inRange(refund.draft.date), !excludedCategories.contains(refund.draft.categoryID ?? "") {
                guard let cents = Int64(exactly: remainder) else { throw MoneyError.outOfRange }
                unallocated.append(refund.id); unallocatedCents = try add(unallocatedCents, cents)
            }
        }
        var rows: [SummaryPurchase] = [], categoryAmounts: [String: Int64] = [:]
        var groups: [String: [String: Int64]] = [:]
        var pendingCents: Int64 = 0, totalCents: Int64 = 0
        for purchase in spending {
            let value = purchase.draft
            let day = value.activityDate ?? value.date
            let category = value.categoryID ?? ""
            guard inRange(day), !excludedCategories.contains(category) else { continue }
            if value.postingStatus == .pending { pendingCents = try add(pendingCents, value.amount.minorUnits); continue }
            guard value.postingStatus == .posted else { continue }
            let net = value.amount.minorUnits - (deductions[purchase.id] ?? 0)
            let bucket = try period(day)
            rows.append(SummaryPurchase(recordID: purchase.id, refundIDs: refundIDs[purchase.id] ?? [], date: day,
                categoryID: category, net: Money(minorUnits: net), periodID: bucket))
            categoryAmounts[category] = try add(categoryAmounts[category] ?? 0, net)
            var group = groups[bucket] ?? [:]
            group[category] = try add(group[category] ?? 0, net); groups[bucket] = group
            totalCents = try add(totalCents, net)
        }
        purchases = rows.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        categories = categoryAmounts.keys.sorted().map { key in
            SummaryCategory(id: key, label: catalog.category(id: key)?.label ?? (key.isEmpty ? "No category" : key),
                amount: Money(minorUnits: categoryAmounts[key]!))
        }
        bars = groups.keys.sorted().flatMap { key in
            groups[key]!.keys.sorted().map { category in
                SummaryBar(periodID: key, categoryID: category, amount: Money(minorUnits: groups[key]![category]!))
            }
        }
        pending = Money(minorUnits: pendingCents); total = Money(minorUnits: totalCents)
        unallocatedRefundIDs = unallocated.sorted { $0.uuidString < $1.uuidString }
        unallocatedRefundAmount = Money(minorUnits: unallocatedCents)
    }
}

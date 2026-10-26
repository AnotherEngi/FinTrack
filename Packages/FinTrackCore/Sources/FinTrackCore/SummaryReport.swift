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
            || record.draft.allocations.contains { categoryIDs.contains($0.categoryID) }
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
    public let allocationID: UUID?
    public init(purchaseID: UUID, amount: Money, allocationID: UUID? = nil) { self.purchaseID = purchaseID; self.amount = amount; self.allocationID = allocationID }
    private enum CodingKeys: String, CodingKey { case purchaseID, allocationID, amountMinorUnits, currency }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let text = try values.decode(String.self, forKey: .amountMinorUnits)
        guard let cents = Int64(text), String(cents) == text else {
            throw ExchangeError.invalid("Refund allocation amount must be an exact integer string.")
        }
        purchaseID = try values.decode(UUID.self, forKey: .purchaseID)
        allocationID = try values.decodeIfPresent(UUID.self, forKey: .allocationID)
        amount = try Money(minorUnits: cents, currency: values.decode(Currency.self, forKey: .currency))
    }
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(purchaseID, forKey: .purchaseID)
        try values.encodeIfPresent(allocationID, forKey: .allocationID)
        try values.encode(String(amount.minorUnits), forKey: .amountMinorUnits)
        try values.encode(amount.currency, forKey: .currency)
    }
}

public enum RefundAccounting {
    public static func validate(records: [LedgerTransaction]) throws {
        guard Set(records.map(\.id)).count == records.count else { throw LedgerError.duplicateID }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        var used: [UUID: Int64] = [:]
        var components: [String: Int64] = [:]
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
                if let id = allocation.allocationID {
                    guard let part = purchase.draft.components.first(where: { $0.id == id }) else { throw ExchangeError.invalid("Refund references a missing category allocation.") }
                    let key = purchase.id.uuidString + id.uuidString
                    components[key] = try addCents(components[key] ?? 0, allocation.amount.minorUnits)
                    try requireFinance(components[key]! <= part.amount.minorUnits, "Refunds exceed the category allocation's gross amount.")
                }
            }
        }
    }

    /// Exact full-width integer products and largest-remainder rounding. This is
    /// a proposal only; callers must obtain explicit confirmation before saving.
    public static func proportional(amount: Money, purchase: LedgerTransaction, records: [LedgerTransaction], excludingRefundID: UUID? = nil) throws -> [RefundAllocation] {
        try validate(records: records)
        try requireFinance(purchase.draft.treatment == .spending && purchase.draft.postingStatus == .posted && amount.minorUnits > 0
            && amount.currency == purchase.draft.amount.currency, "Select an eligible posted purchase and positive refund amount.")
        let parts = purchase.draft.components
        var remaining = Dictionary(uniqueKeysWithValues: parts.map { ($0.id, $0.amount.minorUnits) })
        for record in records where record.id != excludingRefundID {
            for allocation in record.draft.refundAllocations ?? [] where allocation.purchaseID == purchase.id {
                guard let id = allocation.allocationID ?? (purchase.draft.allocations.isEmpty ? TransactionDraft.primaryAllocationID : nil) else {
                    throw ExchangeError.invalid("Resolve earlier refund category attribution before proposing another proportional allocation.")
                }
                remaining[id] = try addCents(remaining[id] ?? 0, -allocation.amount.minorUnits)
            }
        }
        let total = try remaining.values.reduce(Int64(0)) { try addCents($0, $1) }
        try requireFinance(total >= amount.minorUnits && total > 0, "Refund exceeds remaining refundable purchase value.")
        var proposals: [(id: UUID, cents: Int64, remainder: UInt64)] = []
        for part in parts {
            let weight = remaining[part.id]!
            if weight <= 0 { continue }
            let product = UInt64(amount.minorUnits).multipliedFullWidth(by: UInt64(weight))
            let division = UInt64(total).dividingFullWidth(product)
            proposals.append((part.id, Int64(division.quotient), division.remainder))
        }
        proposals.sort { $0.remainder == $1.remainder ? $0.id.uuidString < $1.id.uuidString : $0.remainder > $1.remainder }
        let allocated = try proposals.reduce(Int64(0)) { try addCents($0, $1.cents) }
        let residual = Int(amount.minorUnits - allocated)
        for index in 0..<residual { proposals[index].cents += 1 }
        return proposals.filter { $0.cents > 0 }.map { .init(purchaseID: purchase.id, amount: Money(minorUnits: $0.cents), allocationID: purchase.draft.allocations.isEmpty ? nil : $0.id) }
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
    public var categoryAmounts: [String: Money] = [:]
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
    public let grossPurchases: Money
    public let unallocatedRefundIDs: [UUID]
    public let unallocatedRefundAmount: Money
    public let receipts: Money
    public let netCost: Money
    public let limitations: [String]

    public init(records: [LedgerTransaction], catalog: ReviewCatalog,
                from: TransactionDate? = nil, through: TransactionDate? = nil,
                visibility: SummaryVisibility = .init(), showHidden: Bool = false,
                excludedCategories: Set<String> = [], workspace: ReviewWorkspace = .init()) throws {
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
        calendar.firstWeekday = ReportingCalendar.firstWeekday
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
        var deductions: [String: Int64] = [:], refundIDs: [UUID: [UUID]] = [:]
        var unallocated: [UUID] = [], unallocatedCents: Int64 = 0
        for refund in available where refund.draft.treatment == .refund && refund.draft.postingStatus == .posted {
            var allocated: Int64 = 0
            for link in refund.draft.refundAllocations ?? [] {
                guard let purchase = records.first(where: { $0.id == link.purchaseID }),
                      let component = link.allocationID ?? (purchase.draft.allocations.isEmpty ? TransactionDraft.primaryAllocationID : nil) else { continue }
                let key = link.purchaseID.uuidString + component.uuidString
                deductions[key] = try add(deductions[key] ?? 0, link.amount.minorUnits)
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
        var pendingCents: Int64 = 0, totalCents: Int64 = 0, grossCents: Int64 = 0
        for purchase in spending {
            let value = purchase.draft
            let day = value.activityDate ?? value.date
            guard inRange(day) else { continue }
            let parts = value.components.filter { !excludedCategories.contains($0.categoryID) }
            if value.postingStatus == .pending { for part in parts { pendingCents = try add(pendingCents, part.amount.minorUnits) }; continue }
            guard value.postingStatus == .posted else { continue }
            if !workspace.reporting.includePostedUnreviewed && purchase.approval != .confirmed { continue }
            let bucket = try period(day)
            var group = groups[bucket] ?? [:]
            var net: Int64 = 0, portions: [String: Money] = [:]
            for part in parts {
                grossCents = try add(grossCents, part.amount.minorUnits)
                let cents = part.amount.minorUnits - (deductions[purchase.id.uuidString + part.id.uuidString] ?? 0)
                net = try add(net, cents)
                categoryAmounts[part.categoryID] = try add(categoryAmounts[part.categoryID] ?? 0, cents)
                group[part.categoryID] = try add(group[part.categoryID] ?? 0, cents)
                portions[part.categoryID] = Money(minorUnits: try add(portions[part.categoryID]?.minorUnits ?? 0, cents))
            }
            groups[bucket] = group
            var row = SummaryPurchase(recordID: purchase.id, refundIDs: refundIDs[purchase.id] ?? [], date: day,
                categoryID: value.categoryID ?? "", net: Money(minorUnits: net), periodID: bucket)
            row.categoryAmounts = portions; rows.append(row); totalCents = try add(totalCents, net)
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
        grossPurchases = Money(minorUnits: grossCents)
        unallocatedRefundIDs = unallocated.sorted { $0.uuidString < $1.uuidString }
        unallocatedRefundAmount = Money(minorUnits: unallocatedCents)
        var receiptCents: Int64 = 0, repaid: Int64 = 0
        for record in available where record.draft.treatment == .reimbursementReceipt && record.draft.postingStatus == .posted && inRange(record.draft.date) {
            guard let magnitude = Int64(exactly: record.draft.amount.minorUnits.magnitude) else { throw MoneyError.outOfRange }
            receiptCents = try add(receiptCents, magnitude)
        }
        let selected = Set(rows.map(\.recordID))
        for allocation in workspace.repayments {
            if let claim = workspace.claims.first(where: { $0.id == allocation.claimID }), selected.contains(claim.expenseID),
               let expense = records.first(where: { $0.id == claim.expenseID }) {
                if let component = allocation.expenseAllocationID.flatMap({ id in expense.draft.components.first { $0.id == id } }) {
                    if !excludedCategories.contains(component.categoryID) { repaid = try add(repaid, allocation.amount.minorUnits) }
                } else if excludedCategories.isDisjoint(with: expense.draft.components.map(\.categoryID)) {
                    repaid = try add(repaid, allocation.amount.minorUnits)
                }
            }
        }
        receipts = Money(minorUnits: receiptCents); netCost = Money(minorUnits: try add(totalCents, -repaid))
        limitations = workspace.reporting.coverage.filter { $0.status != .complete }.map { $0.source + ": " + $0.status.rawValue + ". " + $0.limitations }
            + (workspace.reporting.coverage.isEmpty ? ["Source coverage has not been supplied. Empty periods are not verified zero spending."] : [])
            + (workspace.historyImport != nil && workspace.refundImports.isEmpty ? ["Deferred refunds are not yet incorporated; purchases remain gross."] : [])
            + (!excludedCategories.isEmpty && workspace.repayments.contains { $0.expenseAllocationID == nil } ? ["Unattributed repayments are excluded from category-filtered net cost when their purchase spans hidden categories. Assign a purchase component to attribute them."] : [])
    }
}

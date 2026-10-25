import Foundation

public struct SpendingMonth: Identifiable, Sendable {
    public let id: String
    public let year: Int
    public let month: Int
    public let posted: Money
    public let pending: Money
    public let recordIDs: [UUID]
    public let segment: String
}

/// Exact accounting values and observed months only. Chart coordinates are
/// derived in the Apple UI; no floating-point finance arithmetic is used here.
public struct SpendingCharts: Sendable {
    public let totals: SpendingTotals
    public let categories: [SpendingBucket]
    public let months: [SpendingMonth]
    public let years: [Int]
    public init(records: [LedgerTransaction], catalog: ReviewCatalog) throws {
        let summary = try LedgerOverview(records: records, catalog: catalog)
        totals = summary.totals
        categories = summary.categories.sorted {
            if $0.totals.posted.minorUnits == $1.totals.posted.minorUnits { return $0.id < $1.id }
            return $0.totals.posted.minorUnits > $1.totals.posted.minorUnits
        }
        var points: [SpendingMonth] = []
        var previousYear = 0, previousMonth = 0, segment = 0
        for bucket in summary.months.reversed() {
            let parts = bucket.id.split(separator: "-")
            guard parts.count == 2, let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else {
                throw LedgerError.invalidDate
            }
            if year != previousYear || month != previousMonth + 1 { segment += 1 }
            points.append(SpendingMonth(id: bucket.id, year: year, month: month, posted: bucket.totals.posted,
                pending: bucket.totals.pending, recordIDs: bucket.recordIDs, segment: "\(year)-\(segment)"))
            previousYear = year; previousMonth = month
        }
        months = points
        years = Array(Set(points.map(\.year))).sorted()
    }
}

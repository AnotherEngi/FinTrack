import Foundation

public enum IntakeMatching {
    /// Conservative review candidates, never an automatic merge. Include linked
    /// and unlinked rows, and let callers include earlier additions in this batch.
    public static func candidates(for incoming: WeeklyTransaction, in records: [LedgerTransaction]) throws -> [UUID] {
        try Index(records: records).candidates(for: incoming)
    }
    /// One ephemeral date index per batch, including its earlier additions. It
    /// avoids a full-history scan/date conversion for every incoming row.
    public struct Index: Sendable {
        private var days: [String: [LedgerTransaction]] = [:]
        public init(records: [LedgerTransaction]) { for record in records { add(record) } }
        public mutating func add(_ record: LedgerTransaction) {
            days[(record.draft.activityDate ?? record.draft.date).iso8601, default: []].append(record)
        }
        public func candidates(for incoming: WeeklyTransaction) throws -> [UUID] {
            let facts = try incoming.draft(), words = IntakeMatching.merchantWords(incoming.merchant)
            var result: [UUID] = []
            for day in IntakeMatching.nearbyDays(facts.activityDate ?? facts.date) {
                for record in days[day] ?? [] {
                    let old = record.draft
                    guard old.amount.currency == facts.amount.currency,
                          (old.amount.minorUnits < 0) == (facts.amount.minorUnits < 0) else { continue }
                    let previous = IntakeMatching.merchantWords(old.payee)
                    if words == previous || (!words.isEmpty && !previous.isEmpty && words.intersection(previous).count >= 2) {
                        result.append(record.id)
                        if result.count == 100 { return result }
                    }
                }
            }
            return result
        }
    }
    private static func merchantWords(_ value: String) -> Set<String> {
        Set(value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            .filter { !$0.isEmpty && !["pos", "purchase", "pending", "posted", "card"].contains($0) })
    }
    private static func nearbyDays(_ value: TransactionDate) -> [String] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = value.iso8601.split(separator: "-").compactMap { Int($0) }
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return [] }
        return (-7...7).compactMap { offset in
            guard let next = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: next)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
    }
}

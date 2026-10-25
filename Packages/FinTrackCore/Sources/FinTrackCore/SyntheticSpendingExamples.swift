import Foundation

public enum SyntheticSpendingExamples {
    /// Fictional seasonal data for the previous/current calendar years. Stable
    /// IDs support opt-in append without replacing edits or inventing coverage.
    public static func make(asOf today: TransactionDate) throws -> [LedgerTransaction] {
        let year = Int(today.iso8601.prefix(4))!
        let currentMonth = Int(today.iso8601.dropFirst(5).prefix(2))!
        let categories = ["sample-groceries", "sample-household", "sample-transit"]
        let names = ["Fictional Monthly Market", "Fictional Home Supplies", "Fictional Transit"]
        let source = TransactionSource(id: UUID(uuidString: "60000000-0000-4000-8000-000000000001")!, label: "Fictional chart card")
        var records: [LedgerTransaction] = []
        for sampleYear in (year - 1)...year {
            for month in 1...(sampleYear == year ? currentMonth : 12) {
                for index in categories.indices {
                    let number = sampleYear * 10_000 + month * 100 + index
                    let id = UUID(uuidString: String(format: "61000000-0000-4000-8000-%012d", number))!
                    let date = try TransactionDate(String(format: "%04d-%02d-01", sampleYear, month))
                    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    let timestamp = calendar.date(from: DateComponents(year: sampleYear, month: month, day: 1, hour: 12))!
                    let cents = Int64((index + 1) * 2_000 + month * 175 + (sampleYear - year + 1) * 400
                        + (month == 12 ? 3_000 : 0))
                    let draft = TransactionDraft(date: date, payee: names[index], amount: Money(minorUnits: cents),
                        notes: "Invented chart fixture; not an account coverage claim.", treatment: .spending,
                        categoryID: categories[index], source: source)
                    records.append(try LedgerTransaction(id: id, createdAt: timestamp, draft: draft,
                        classificationProvenance: .init(category: .assistant)))
                }
            }
        }
        return records
    }
}

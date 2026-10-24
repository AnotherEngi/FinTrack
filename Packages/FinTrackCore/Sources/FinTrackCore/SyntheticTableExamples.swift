import Foundation

public enum SyntheticTableExamples {
    /// Stable IDs in a new namespace. Append missing examples; never rewrite
    /// earlier samples or a user's edits when demonstrating the current table.
    public static func make(asOf today: TransactionDate) throws -> [LedgerTransaction] {
        let sourceIDs = (1...3).map { UUID(uuidString: String(format: "30000000-0000-4000-8000-%012d", $0))! }
        let sources = ["Sample Visa", "Sample debit", "Sample checking"]
        let merchants = ["Maple Market", "Cedar Cafe", "Harbor Inn", "City Transit", "Orchard Foods",
            "Maple Market refund", "Valley Electric", "Sample card payment",
            "Birch Lunchroom", "Spring Supplies", "Winter Market", "Evergreen Supplies"]
        let days = [0, -1, -2, -3, -4, -5, -7, -12, -65, -150, -240, -320]
        let amounts: [Int64] = [8437, 2850, 18600, 750, 4620, -1299, 6740, 20000, 2380, 5920, 1825, 4750]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = today.iso8601.split(separator: "-").map { Int($0)! }
        let reference = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
        return try merchants.indices.map { index in
            let timestamp = calendar.date(byAdding: .day, value: days[index], to: reference)!
            let parts = calendar.dateComponents([.era, .year, .month, .day], from: timestamp)
            guard parts.era == 1 else { throw LedgerError.invalidDate }
            let date = try TransactionDate(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
            let category = index == 7 ? "sample-excluded" : [3, 9].contains(index) ? "sample-transit"
                : [2, 6, 11].contains(index) ? "sample-household" : "sample-groceries"
            let tags = index == 2 ? ["Sample getaway", "Travel"] : [0, 5, 11].contains(index) ? ["Household"] : []
            let draft = TransactionDraft(date: date, payee: merchants[index], amount: Money(minorUnits: amounts[index]),
                notes: [2, 3].contains(index) ? "Invented discussion context for a synthetic test." : "",
                postingStatus: index == 4 ? .pending : .posted,
                treatment: index == 5 ? .refund : index == 7 ? .payment : .spending,
                categoryID: category, tags: tags,
                source: TransactionSource(id: sourceIDs[index % 3], label: sources[index % 3]))
            var record = try LedgerTransaction(
                id: UUID(uuidString: String(format: "20000000-0000-4000-8000-%012d", index + 1))!,
                createdAt: timestamp, draft: draft,
                assistantContext: AssistantContext(question: [0, 2, 3].contains(index)
                    ? "What should we know about this invented purchase?" : "",
                    reason: "Synthetic table demonstration; not a live LLM suggestion."),
                classificationProvenance: ClassificationProvenance(
                    category: index == 7 ? .unknown : [1, 5, 9, 11].contains(index) ? .user : .assistant,
                    tags: Dictionary(uniqueKeysWithValues: tags.map { ($0, $0 == "Sample getaway" ? .user : .assistant) })))
            func apply(_ action: ReviewAction, step: Int) throws {
                let requestID = UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", (index + 1) * 10 + step))!
                record = try record.applying(ReviewRequest(id: requestID, transactionID: record.id,
                    expectedRevision: record.revision, action: action), catalog: .prototype, at: timestamp)
            }
            if [5, 6, 9, 11].contains(index) { try apply(.approve, step: 1) }
            if [2, 3].contains(index) { try apply(.discuss, step: 2) }
            if index == 3 { try apply(.markDiscussionInProgress, step: 3) }
            return record
        }
    }
}

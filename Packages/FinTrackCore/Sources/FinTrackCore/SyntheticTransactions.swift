import Foundation

/// Entirely invented data with stable IDs; never derived from financial files.
public enum SyntheticTransactions {
    public static func make() throws -> [LedgerTransaction] {
        try (0..<8).flatMap { week in
            try (0..<3).map { item in
                let day = 1 + week * 7 + item
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let timestamp = calendar.date(from: DateComponents(
                    year: 2026, month: 8, day: day, hour: 12
                ))!
                let parts = calendar.dateComponents([.year, .month, .day], from: timestamp)
                let date = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
                let index = week * 3 + item + 1
                let id = UUID(uuidString: String(format:
                    "00000000-0000-4000-8000-%012d", index))!
                let names = ["Sample Grocery", "Sample Transit", "Sample Paycheck"]
                let amounts: [Int64] = [4_325 + Int64(week * 100), 750, -125_000]
                let isRefund = week == 7 && item == 2
                let treatment: TransactionTreatment = isRefund ? .refund : item == 2 ? .income : .spending
                let categoryID = item == 0 || isRefund ? "sample-groceries" : item == 1 ? "sample-transit" : nil
                var record = try LedgerTransaction(id: id, createdAt: timestamp, draft:
                    TransactionDraft(date: TransactionDate(date),
                                     payee: isRefund ? "Sample Grocery Refund" : names[item],
                                     amount: Money(minorUnits: isRefund ? -1_299 : amounts[item]),
                                     notes: "Synthetic development example",
                                     postingStatus: week == 7 && item == 0 ? .pending : .posted,
                                     treatment: treatment, categoryID: categoryID),
                    assistantContext: item == 0 ? AssistantContext(
                        question: "Was this for groceries or household supplies?",
                        reason: "A fictional suggestion to exercise review.",
                        ledgerNotes: "Synthetic earlier ledger history") : .init())
                if item == 1 || isRefund {
                    // A fictional explicit approval, not approval inferred from a category.
                    let operationID = UUID(uuidString: String(format:
                        "10000000-0000-4000-8000-%012d", index))!
                    record = try record.applying(ReviewRequest(id: operationID, transactionID: id,
                        expectedRevision: record.revision, action: .approve),
                        catalog: .prototype, at: timestamp)
                }
                return record
            }
        }
    }
}

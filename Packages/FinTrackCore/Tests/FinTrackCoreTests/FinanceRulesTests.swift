import Foundation
import Testing
@testable import FinTrackCore

@Test func exactMoneyAndSignedBoundaries() throws {
    #expect(try Money(decimalText: "0.10").minorUnits == 10)
    #expect(try Money(decimalText: "-12.3").minorUnits == -1_230)
    #expect(try Money(decimalText: "+12").minorUnits == 1_200)
    for amount in [Int64.min, -1, 0, 1, Int64.max] {
        #expect(try Money(decimalText: Money(minorUnits: amount).decimalText).minorUnits == amount)
    }
    #expect(throws: MoneyError.invalidAmount) { try Money(decimalText: "1.001") }
    #expect(throws: MoneyError.invalidAmount) { try Money(decimalText: "1,23") }
    #expect(throws: MoneyError.invalidAmount) { try Money(decimalText: "1e2") }
    #expect(throws: MoneyError.invalidAmount) { try Money(decimalText: "12.") }
    #expect(throws: MoneyError.outOfRange) { try Money(decimalText: "92233720368547758.08") }
}

@Test func calendarDatesDoNotNormalizeInvalidInput() throws {
    _ = try TransactionDate("2024-02-29")
    for date in ["2026-02-29", "2026-04-31", "2026-00-10", "2026-01-00", "2026-1-01"] {
        #expect(throws: LedgerError.invalidDate) { try TransactionDate(date) }
    }
    #expect(try TransactionDate("2026-01-01") < TransactionDate("2026-12-31"))
}

@Test func expensesArePositiveWhileRefundsAndIncomeAreNegative() throws {
    let records = try SyntheticTransactions.make()
    let grocery = try #require(records.first { $0.draft.payee == "Sample Grocery" })
    let transit = try #require(records.first { $0.draft.payee == "Sample Transit" })
    let refund = try #require(records.first { $0.draft.payee == "Sample Grocery Refund" })
    let income = try #require(records.first { $0.draft.payee == "Sample Paycheck" })
    #expect(grocery.draft.amount == Money(minorUnits: 4_325))
    #expect(transit.draft.amount == Money(minorUnits: 750))
    #expect(refund.draft.amount == Money(minorUnits: -1_299))
    #expect(income.draft.amount == Money(minorUnits: -125_000))

    // Signed values must survive entry and serialization without an implicit flip.
    for amount in [grocery, transit, refund, income].map({ $0.draft.amount }) {
        #expect(try Money(decimalText: amount.decimalText) == amount)
        let encoded = try JSONEncoder().encode(amount)
        #expect(try JSONDecoder().decode(Money.self, from: encoded) == amount)
    }
}

@Test func staleChangesCannotReplaceANewerRevision() throws {
    let original = try SyntheticTransactions.make()[0]
    var draft = original.draft
    draft.notes = "My manual edit"
    let edited = try original.revising(with: draft, expectedRevision: 1)
    #expect(edited.revision == 2)
    #expect(edited.id == original.id)
    #expect(edited.createdAt == original.createdAt)
    #expect(throws: LedgerError.staleRevision) {
        try edited.revising(with: original.draft, expectedRevision: 1)
    }
    #expect(edited.draft.notes == "My manual edit")
}

@Test func invalidAndCorruptedRecordsAreRejected() throws {
    var draft = try SyntheticTransactions.make()[0].draft
    draft.payee = " \n "
    #expect(throws: LedgerError.missingPayee) { try LedgerTransaction(draft: draft) }
    draft.payee = "Example"
    #expect(throws: LedgerError.invalidRevision) { try LedgerTransaction(revision: 0, draft: draft) }
    let record = try LedgerTransaction(draft: draft)
    let encoder = JSONEncoder()
    let data = try encoder.encode(record)
    #expect(try JSONDecoder().decode(LedgerTransaction.self, from: data) == record)
    let decodedObject = try JSONSerialization.jsonObject(with: data)
    var object = try #require(decodedObject as? [String: Any])
    object["revision"] = "0"
    let invalid = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: LedgerError.invalidRevision) {
        try JSONDecoder().decode(LedgerTransaction.self, from: invalid)
    }
}

@Test func samplesAreStableAndCoverEightWeeks() throws {
    let records = try SyntheticTransactions.make()
    #expect(records.count == 24)
    #expect(Set(records.map(\.id)).count == 24)
    #expect(try records == SyntheticTransactions.make())
    #expect(records.first?.draft.date.iso8601 == "2026-08-01")
    #expect(records.last?.draft.date.iso8601 == "2026-09-21")
}

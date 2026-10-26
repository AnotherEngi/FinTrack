import Foundation
import Testing
@testable import FinTrackCore

private func displayRecord(date: String = "2026-10-01", amount: Int64 = 1_000,
                           status: PostingStatus = .posted, treatment: TransactionTreatment = .spending,
                           category: String? = "sample-groceries", tags: [String] = [], event: Bool = false,
                           payee: String = "Invented merchant", notes: String = "", answer: String = "",
                           context: AssistantContext = .init()) throws -> LedgerTransaction {
    try LedgerTransaction(createdAt: Date(timeIntervalSince1970: 0), draft:
        TransactionDraft(date: TransactionDate(date), payee: payee, amount: Money(minorUnits: amount),
            notes: notes, answer: answer, postingStatus: status, treatment: treatment,
            categoryID: category, tags: tags, exceptionalEvent: event), assistantContext: context)
}

private func exportObject(_ export: ReviewExport) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: export.json) as? [String: Any])
}

@Test func exportOmitsUnselectedPrivateContextAndHistoryByDefault() throws {
    let record = try displayRecord(notes: "PRIVATE USER NOTE", answer: "PRIVATE ANSWER",
        context: AssistantContext(question: "PRIVATE QUESTION", reason: "PRIVATE REASON", ledgerNotes: "PRIVATE HISTORY"))
    let export = try ReviewExport(records: [record], catalog: .prototype)
    let object = try exportObject(export)
    let rows = try #require(object["transactions"] as? [[String: Any]])
    #expect(rows.count == 1)
    #expect(rows[0]["userNote"] == nil)
    #expect(rows[0]["userAnswer"] == nil)
    #expect(rows[0]["assistantContext"] == nil)
    #expect(rows[0]["reviewHistory"] == nil)
    #expect(!String(decoding: export.json, as: UTF8.self).contains("PRIVATE"))
    #expect(!export.csv.contains("PRIVATE"))
    #expect(!export.csv.contains("user_note"))
    #expect(!export.csv.contains("assistant_question"))
    #expect(object["purpose"] as? String == "fintrack-review-export")
    #expect(object["schemaVersion"] as? Int == FinancialFormat.version)
}

@Test func exportOptionsKeepUserAndAssistantOwnershipSeparate() throws {
    let record = try displayRecord(notes: "User note", answer: "User answer",
        context: AssistantContext(question: "Assistant question", reason: "Assistant reason", ledgerNotes: "Earlier notes"))
    let userOnly = try ReviewExport(records: [record], catalog: .prototype,
        options: .init(includeUserContext: true))
    #expect(userOnly.packet.transactions[0].userNote == "User note")
    #expect(userOnly.packet.transactions[0].userAnswer == "User answer")
    #expect(userOnly.packet.transactions[0].assistantContext == nil)
    let assistantOnly = try ReviewExport(records: [record], catalog: .prototype,
        options: .init(includeAssistantContext: true))
    #expect(assistantOnly.packet.transactions[0].userNote == nil)
    #expect(assistantOnly.packet.transactions[0].assistantContext?.question == "Assistant question")
    #expect(assistantOnly.packet.transactions[0].assistantContext?.ledgerNotes == "Earlier notes")
    #expect(!assistantOnly.csv.contains("user_note"))
    #expect(assistantOnly.csv.contains("assistant_question"))
}

@Test func exportPreservesLargeExactValuesWithoutJavaScriptNumberLoss() throws {
    let base = try displayRecord(amount: .max)
    let record = try LedgerTransaction(id: base.id, revision: .max, createdAt: base.createdAt, draft: base.draft)
    let refund = try displayRecord(amount: .min, treatment: .refund)
    let export = try ReviewExport(records: [record, refund], catalog: .prototype)
    let object = try exportObject(export)
    let rows = try #require(object["transactions"] as? [[String: Any]])
    let row = try #require(rows.first { $0["transactionID"] as? String == record.id.uuidString })
    #expect(row["baseRevision"] as? String == "9223372036854775807")
    #expect(row["amountMinorUnits"] as? String == "9223372036854775807")
    #expect(row["amountDecimal"] as? String == "92233720368547758.07")
    #expect(row["currency"] as? String == "USD")
    #expect(export.csv.contains("\"-92233720368547758.08\""))
    #expect(export.packet.amountSignConvention == Money.amountSignConvention)
}

@Test func csvEscapesMultilineQuotesUnicodeAndSpreadsheetFormulas() throws {
    let record = try displayRecord(tags: ["@tag"], payee: " =HYPERLINK(\"invented\",\"test\")",
        notes: "Fictional café, \"supplies\"\r\nsecond line", answer: "\t+1+1",
        context: AssistantContext(question: "-formula", reason: "Normal reason"))
    let export = try ReviewExport(records: [record], catalog: .prototype,
        options: .init(includeUserContext: true, includeAssistantContext: true))
    #expect(export.csv.contains("\"' =HYPERLINK(\"\"invented\"\",\"\"test\"\")\""))
    #expect(export.csv.contains("\"Fictional café, \"\"supplies\"\"\r\nsecond line\""))
    #expect(export.csv.contains("\"'\t+1+1\""))
    #expect(export.csv.contains("\"'-formula\""))
    let object = try exportObject(export)
    let rows = try #require(object["transactions"] as? [[String: Any]])
    #expect(rows[0]["payee"] as? String == record.draft.payee)
    #expect(rows[0]["userNote"] as? String == record.draft.notes)
    #expect(rows[0]["userAnswer"] as? String == record.draft.answer)
}

@Test func exportIsDeterministicForTheSameSnapshotAndDoesNotChangeRecords() throws {
    let records = try SyntheticTransactions.make()
    let packetID = UUID()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let original = records
    let first = try ReviewExport(records: records, catalog: .prototype, packetID: packetID, exportedAt: now)
    let second = try ReviewExport(records: records.reversed(), catalog: .prototype, packetID: packetID, exportedAt: now)
    #expect(first.json == second.json)
    #expect(first.csv == second.csv)
    #expect(first.prompt == second.prompt)
    #expect(records == original)
    #expect(first.packet.transactions.count == 24)
    #expect(first.packet.earliestDate == "2026-08-01")
    #expect(first.packet.latestDate == "2026-09-21")
    #expect(first.prompt.contains(first.jsonFileName))
    #expect(first.prompt.contains(first.csvFileName))
    #expect(first.prompt.contains("use the returnTemplate in the app's prepared fintrack-review-request envelope"))
}

@Test func exportRejectsEmptyAndDuplicateSelections() throws {
    #expect(throws: ReviewExportError.emptySelection) {
        try ReviewExport(records: [], catalog: .prototype)
    }
    let record = try displayRecord()
    #expect(throws: ReviewExportError.duplicateRecord) {
        try ReviewExport(records: [record, record], catalog: .prototype)
    }
}

@Test func selectionUsesInclusiveDatesAndSearchesTagsNotesAndAnswers() throws {
    let before = try displayRecord(date: "2026-09-30")
    let first = try displayRecord(tags: ["Fictional trip"])
    let last = try displayRecord(date: "2026-10-31", answer: "Household supplies")
    let after = try displayRecord(date: "2026-11-01", notes: "Fictional trip")
    let records = [before, first, last, after]
    let range = LedgerSelection(from: try TransactionDate("2026-10-01"), through: try TransactionDate("2026-10-31"))
    #expect(range.records(in: records).map(\.id) == [last.id, first.id])
    var tags = range
    tags.search = "  FICTIONAL TRIP  "
    #expect(tags.records(in: records).map(\.id) == [first.id])
    tags.search = "supplies"
    #expect(tags.records(in: records).map(\.id) == [last.id])
    tags.search = "unknown"
    #expect(tags.records(in: records).isEmpty)
    #expect(LedgerSelection(from: try TransactionDate("2026-11-01"), through: try TransactionDate("2026-10-01"))
        .records(in: records).isEmpty)
}

@Test func overviewExclusionsOverlapOnceAndNeverChangeTheLedger() throws {
    let both = try displayRecord(tags: ["Sample trip"], event: true)
    let tagOnly = try displayRecord(tags: ["Sample trip"])
    let eventOnly = try displayRecord(event: true)
    let ordinary = try displayRecord(amount: 250)
    let records = [both, tagOnly, eventOnly, ordinary]
    let selected = LedgerSelection(excludedTags: ["Sample trip"], excludeExceptionalEvents: true).records(in: records)
    #expect(selected.map(\.id) == [ordinary.id])
    #expect(try LedgerOverview(records: selected, catalog: .prototype).totals.posted.minorUnits == 250)
    #expect(try LedgerOverview(records: records, catalog: .prototype).totals.posted.minorUnits == 3_250)
    #expect(records[0].draft.exceptionalEvent == true)
    #expect(records[0].draft.tags == ["Sample trip"])
}

@Test func overviewSeparatesPendingRefundsIncomeAndUnknownPostingAndMissingMonths() throws {
    let records = try [displayRecord(date: "2026-08-01", amount: 1_000),
        displayRecord(date: "2026-08-02", amount: -250, treatment: .refund),
        displayRecord(date: "2026-10-03", amount: 500, status: .pending, category: "sample-transit"),
        displayRecord(date: "2026-09-01", amount: -9_000, treatment: .income),
        displayRecord(amount: 7_000, status: .unresolved)]
    let report = try LedgerOverview(records: records, catalog: .prototype)
    #expect(report.totals.posted.minorUnits == 750)
    #expect(report.totals.pending.minorUnits == 500)
    #expect(report.months.map(\.id) == ["2026-10", "2026-08"])
    #expect(report.categories.count == 2)
    #expect(report.categories.reduce(0) { $0 + $1.totals.posted.minorUnits } == 750)
    #expect(report.categories.reduce(0) { $0 + $1.totals.pending.minorUnits } == 500)
    #expect(report.omittedFromSpendingCount == 2)
    #expect(report.recordCount == 5)
}

@Test func questionsIncludeUnansweredAssistantQuestionsAndExplicitDiscussion() throws {
    let unanswered = try displayRecord(context: AssistantContext(question: "Which category?"))
    let answered = try displayRecord(answer: "Groceries", context: AssistantContext(question: "Which category?"))
    let ordinary = try displayRecord()
    let discussed = try ordinary.revising(with: TransactionDraft(date: ordinary.draft.date,
        payee: ordinary.draft.payee, amount: ordinary.draft.amount, notes: "Please check",
        treatment: .spending, categoryID: "sample-groceries"), expectedRevision: ordinary.revision)
        .applying(ReviewRequest(transactionID: ordinary.id, expectedRevision: 2, action: .discuss), catalog: .prototype)
    let records = [unanswered, answered, discussed]
    let questions = LedgerSelection(reviewFilter: .questions).records(in: records)
    #expect(Set(questions.map(\.id)) == [unanswered.id, discussed.id])
    #expect(LedgerSelection(reviewFilter: .discussion).records(in: records).map(\.id) == [discussed.id])
    #expect(try LedgerOverview(records: records, catalog: .prototype).questionsCount == 2)
    #expect(discussed.approval == .unreviewed)
}

@Test func overviewReportsOverflowInsteadOfWrapping() throws {
    let records = try [displayRecord(amount: .max), displayRecord(amount: 1)]
    #expect(throws: MoneyError.outOfRange) { try LedgerOverview(records: records, catalog: .prototype) }
}

@Test func historyRetainsActionsAcrossReopeningAndUsesUniqueCrossRecordRowIDs() throws {
    let first = try displayRecord()
    let second = try displayRecord()
    let operationID = UUID()
    let firstApproval = try first.applying(ReviewRequest(id: operationID, transactionID: first.id,
        expectedRevision: 1, action: .approve), catalog: .prototype, at: Date(timeIntervalSince1970: 10))
    let secondApproval = try second.applying(ReviewRequest(id: operationID, transactionID: second.id,
        expectedRevision: 1, action: .approve), catalog: .prototype, at: Date(timeIntervalSince1970: 10))
    let reopened = try firstApproval.applying(ReviewRequest(transactionID: first.id,
        expectedRevision: 2, action: .reopen), catalog: .prototype, at: Date(timeIntervalSince1970: 20))
    let entries = LedgerHistoryEntry.entries(in: [reopened, secondApproval])
    #expect(entries.count == 3)
    #expect(Set(entries.map(\.id)).count == 3)
    #expect(entries[0].decision.request.action == .reopen)
    #expect(entries[0].decision.appliedRevision == 3)
    #expect(reopened.approval == .unreviewed)
    let skipped = try reopened.applying(ReviewRequest(transactionID: first.id,
        expectedRevision: 3, action: .skip), catalog: .prototype)
    #expect(LedgerHistoryEntry.entries(in: [skipped]).count == 2)
}

import Foundation
import Testing
@testable import FinTrackCore

private func workspaceRecord() throws -> LedgerTransaction {
    let draft = try TransactionDraft(date: TransactionDate("2026-10-24"), payee: "Invented merchant",
        amount: Money(minorUnits: 2500), notes: "User's invented context", treatment: .spending,
        categoryID: "sample-groceries", tags: ["Original tag"],
        source: TransactionSource(label: "Sample Visa"))
    return try LedgerTransaction(createdAt: Date(timeIntervalSince1970: 0), draft: draft,
        classificationProvenance: .init(category: .assistant, tags: ["Original tag": .assistant]))
}

private func workspaceAction(_ action: ReviewAction, _ record: LedgerTransaction) throws -> LedgerTransaction {
    try record.applying(ReviewRequest(transactionID: record.id, expectedRevision: record.revision, action: action), catalog: .prototype)
}

@Test func sourceIdentitySurvivesRawDraftAndLabelCorrections() throws {
    let record = try workspaceRecord()
    var input = TransactionInput(draft: record.draft)
    input.sourceLabel = "Corrected sample label"
    input.amountText = "12."
    let restored = try JSONDecoder().decode(TransactionInput.self, from: JSONEncoder().encode(input))
    #expect(restored == input)
    #expect(restored.sourceID == record.draft.source?.id)
    #expect(throws: MoneyError.invalidAmount) { try restored.value() }
    input.amountText = "12.34"
    let valid = try input.value()
    #expect(valid.source?.id == record.draft.source?.id)
    #expect(valid.source?.label == "Corrected sample label")
    #expect(valid.amount.minorUnits == 1234)
}

@Test func manualClassificationChangesPreserveOtherFieldOrigins() throws {
    let record = try workspaceRecord()
    var draft = record.draft
    draft.categoryID = "sample-household"
    draft.tags += ["New tag"]
    let edited = try record.revising(with: draft, expectedRevision: record.revision)
    #expect(edited.classificationProvenance.category == .user)
    #expect(edited.classificationProvenance.tags == ["Original tag": .assistant, "New tag": .user])
    draft.tags = ["New tag"]
    let removed = try edited.revising(with: draft, expectedRevision: edited.revision)
    #expect(removed.classificationProvenance.tags == ["New tag": .user])
}

@Test func approvalAndReopenRetainActualCategoryAndTagAuthorship() throws {
    let record = try workspaceRecord()
    let approved = try workspaceAction(.approve, record)
    #expect(approved.approval == .confirmed)
    #expect(approved.classificationProvenance == record.classificationProvenance)
    let reopened = try workspaceAction(.reopen, approved)
    #expect(reopened.approval == .unreviewed)
    #expect(reopened.classificationProvenance.category == .assistant)
    #expect(reopened.classificationProvenance.tags["Original tag"] == .assistant)
}

@Test func sourceChangesReopenApprovalButNotesDoNot() throws {
    let approved = try workspaceAction(.approve, workspaceRecord())
    var draft = approved.draft
    draft.notes = "A revised invented note"
    let note = try approved.revising(with: draft, expectedRevision: approved.revision)
    #expect(note.approval == .confirmed)
    draft.source = TransactionSource(label: "Another fictional source")
    let reassigned = try note.revising(with: draft, expectedRevision: note.revision)
    #expect(reassigned.approval == .unreviewed)
    #expect(reassigned.classificationProvenance == approved.classificationProvenance)
}

@Test func invalidSourceAndOrphanedProvenanceAreRejected() throws {
    let record = try workspaceRecord()
    var draft = record.draft
    draft.source = TransactionSource(label: "  ")
    #expect(throws: ReviewError.invalidSource) { try LedgerTransaction(draft: draft) }
    draft.source = TransactionSource(label: String(repeating: "x", count: 121))
    #expect(throws: ReviewError.invalidSource) { try LedgerTransaction(draft: draft) }
    #expect(throws: ReviewError.invalidProvenance) {
        try LedgerTransaction(draft: record.draft,
            classificationProvenance: .init(tags: ["Tag that is not assigned": .assistant]))
    }
    draft = record.draft
    draft.categoryID = nil
    #expect(throws: ReviewError.invalidProvenance) {
        try LedgerTransaction(draft: draft, classificationProvenance: .init(category: .user))
    }
}

@Test func discussionProgressRequiresExplicitUserActionAndRevokesCurrentApproval() throws {
    let record = try workspaceAction(.approve, workspaceRecord())
    #expect(throws: ReviewError.discussionNotRequested) { try workspaceAction(.markDiscussionInProgress, record) }
    let discussed = try workspaceAction(.discuss, record)
    #expect(discussed.discussionProgress == .awaitingExport)
    let request = ReviewRequest(transactionID: record.id, expectedRevision: discussed.revision, action: .markDiscussionInProgress)
    let reviewing = try discussed.applying(request, catalog: .prototype)
    #expect(reviewing.discussionProgress == .reviewingInChatGPT)
    #expect(reviewing.approval == .unreviewed)
    #expect(try reviewing.applying(request, catalog: .prototype) == reviewing)
    let reopened = try workspaceAction(.reopen, reviewing)
    #expect(reopened.discussionProgress == nil)
    #expect(try reopened.applying(request, catalog: .prototype) == reopened)
    #expect(try workspaceAction(.discuss, reviewing).discussionProgress == .awaitingExport)
}

@Test func inconsistentDiscussionProgressCannotBeDecodedOrCreated() throws {
    let record = try workspaceRecord()
    #expect(throws: ReviewError.discussionNotRequested) {
        try LedgerTransaction(draft: record.draft, discussionProgress: .reviewingInChatGPT)
    }
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
    json["discussionProgress"] = "notAWorkflowState"
    #expect(throws: (any Error).self) {
        try JSONDecoder().decode(LedgerTransaction.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

@Test func sessionMarkersOnlyRegisterSuccessfulDistinctResults() throws {
    let record = try workspaceRecord()
    var session = SessionChanges()
    session.register(before: record, after: record)
    #expect(session.recordIDs.isEmpty)
    var draft = record.draft
    draft.notes = "Changed"
    let edited = try record.revising(with: draft, expectedRevision: record.revision)
    session.register(before: record, after: edited)
    #expect(session.recordIDs == [record.id])
    session.register(before: edited, after: edited)
    #expect(session.recordIDs.count == 1)
    #expect(SessionChanges().recordIDs.isEmpty)
}

@Test func calendarPresetsClampMonthEndsAndLeapDays() throws {
    #expect(try WorkspacePeriod.oneMonth.range(through: TransactionDate("2026-03-31")).from.iso8601 == "2026-02-28")
    #expect(try WorkspacePeriod.oneMonth.range(through: TransactionDate("2024-03-31")).from.iso8601 == "2024-02-29")
    #expect(try WorkspacePeriod.threeMonths.range(through: TransactionDate("2026-10-24")).from.iso8601 == "2026-07-24")
    #expect(try WorkspacePeriod.sixMonths.range(through: TransactionDate("2026-10-24")).from.iso8601 == "2026-05-01")
    #expect(try WorkspacePeriod.yearToDate.range(through: TransactionDate("2026-10-24")).from.iso8601 == "2026-01-01")
    #expect(try WorkspacePeriod.pastYear.range(through: TransactionDate("2024-02-29")).from.iso8601 == "2023-02-28")
}

@Test func sixMonthPresetIncludesExactlySixCalendarMonthsAcrossYearAndLeapBoundaries() throws {
    let cases = [("2026-10-25", "2026-05-01"), ("2026-10-01", "2026-05-01"),
                 ("2024-02-29", "2023-09-01"), ("2026-01-31", "2025-08-01")]
    for (end, expectedStart) in cases {
        let range = try WorkspacePeriod.sixMonths.range(through: TransactionDate(end))
        #expect(range.from.iso8601 == expectedStart && range.through.iso8601 == end)
        let report = try SummaryReport(records: [], catalog: .prototype, from: range.from, through: range.through)
        #expect(report.periods.count == 6)
        #expect(report.periods.first?.id == String(expectedStart.prefix(7)))
        #expect(report.periods.last?.id == String(end.prefix(7)))
    }
    #expect(throws: LedgerError.invalidDate) { try WorkspacePeriod.sixMonths.range(through: TransactionDate("0001-01-01")) }
}

@Test func reportingTodayUsesNewYorkAcrossWinterAndSummerMidnightBoundaries() throws {
    let formatter = ISO8601DateFormatter()
    let samples = [("2026-01-01T04:30:00Z", "2025-12-31"), ("2026-01-01T05:30:00Z", "2026-01-01"),
                   ("2026-07-01T03:30:00Z", "2026-06-30"), ("2026-07-01T04:30:00Z", "2026-07-01")]
    for (timestamp, expectedDay) in samples {
        let instant = try #require(formatter.date(from: timestamp))
        #expect(ReportingCalendar.dayText(at: instant) == expectedDay)
    }
    #expect(ReportingCalendar.calendar.timeZone.identifier == "America/New_York")
    #expect(ReportingCalendar.calendar.firstWeekday == 2)
}

@Test func customRangesAreInclusiveAndRejectMissingOrReversedBounds() throws {
    let day = try TransactionDate("2026-10-24")
    let range = try WorkspacePeriod.custom.range(through: day, customFrom: day, customThrough: day)
    #expect(range.from == range.through)
    #expect(LedgerSelection(from: range.from, through: range.through).records(in: [try workspaceRecord()]).count == 1)
    #expect(throws: LedgerError.invalidDate) { try WorkspacePeriod.custom.range(through: day) }
    #expect(throws: LedgerError.invalidDate) {
        try WorkspacePeriod.custom.range(through: day, customFrom: day, customThrough: TransactionDate("2026-10-01"))
    }
    #expect(throws: LedgerError.invalidDate) { try WorkspacePeriod.pastYear.range(through: TransactionDate("0001-03-01")) }
}

@Test func everyColumnSortsDeterministicallyWithoutMonetarySubtractionOverflow() throws {
    let records = try SyntheticTableExamples.make(asOf: TransactionDate("2026-10-24"))
    for column in TransactionSortColumn.allCases {
        let sorting = TransactionTableSort(column: column, ascending: true)
        #expect(sorting.records(records, catalog: .prototype) == sorting.records(records.reversed(), catalog: .prototype))
    }
    let sorted = TransactionTableSort(column: .amount, ascending: true).records(records, catalog: .prototype)
    #expect(sorted.map { $0.draft.amount.minorUnits } == records.map { $0.draft.amount.minorUnits }.sorted())
    #expect(TransactionTableSort(column: .merchant, ascending: true).records(records, catalog: .prototype).first?.draft.payee == "Birch Lunchroom")
    #expect(TransactionTableSort(column: .source, ascending: true).records(records, catalog: .prototype).first?.draft.source?.label == "Sample checking")
    #expect(TransactionTableSort(column: .category, ascending: true).records(records, catalog: .prototype).first?.draft.categoryID == "sample-excluded")
    #expect(TransactionTableSort(column: .review, ascending: true).records(records, catalog: .prototype).first?.approval == .notApplicable)
    #expect(TransactionTableSort(column: .activity, ascending: false).records(records, catalog: .prototype).first?.discussionProgress == .reviewingInChatGPT)
    #expect(TransactionTableSort(column: .date, ascending: true).records(records, catalog: .prototype).first?.draft.payee == "Evergreen Supplies")
    #expect(TransactionTableSort(column: .tags, ascending: true).records(records, catalog: .prototype).first?.draft.tags.isEmpty == true)
    var draft = try workspaceRecord().draft
    draft.amount = Money(minorUnits: .max)
    let largest = try LedgerTransaction(draft: draft)
    draft.amount = Money(minorUnits: .min)
    draft.treatment = .refund
    let smallest = try LedgerTransaction(draft: draft)
    #expect(TransactionTableSort(column: .amount, ascending: true).records([largest,smallest], catalog: .prototype).first == smallest)
}

@Test func sourceAndCategorySearchCombineWithDatesAndAccentInsensitiveText() throws {
    let record = try workspaceRecord()
    #expect(LedgerSelection(search: "sample visa").records(in: [record]).count == 1)
    #expect(LedgerSelection(search: "groceries", categoryLabels: ["sample-groceries": "Groceries"]).records(in: [record]).count == 1)
    var draft = record.draft
    draft.payee = "Invented Café"
    let cafe = try record.revising(with: draft, expectedRevision: record.revision)
    #expect(LedgerSelection(search: "cafe").records(in: [cafe]).count == 1)
    #expect(LedgerSelection(from: try TransactionDate("2026-11-01"), search: "cafe").records(in: [cafe]).isEmpty)
}

@Test func exportRetainsSourceOriginsAndUserTrackedDiscussionWithoutLeakingNotes() throws {
    let record = try workspaceAction(.markDiscussionInProgress, workspaceAction(.discuss, workspaceRecord()))
    let export = try ReviewExport(records: [record], catalog: .prototype)
    let row = try #require(export.packet.transactions.first)
    #expect(row.source == record.draft.source)
    #expect(row.classificationProvenance == record.classificationProvenance)
    #expect(row.discussionProgress == .reviewingInChatGPT)
    #expect(row.userNote == nil)
    #expect(export.csv.contains("Sample Visa"))
    #expect(export.csv.contains("reviewingInChatGPT"))
    #expect(!export.csv.contains("User's invented context"))
    #expect(export.prompt.contains("not a receipt" ) || export.prompt.contains("not a\nreceipt"))
}

@Test func tableExamplesHaveStableIDsRealisticRangesAndExplicitProvenance() throws {
    let records = try SyntheticTableExamples.make(asOf: TransactionDate("2026-10-24"))
    let nextDay = try SyntheticTableExamples.make(asOf: TransactionDate("2026-10-25"))
    #expect(records.count == 12)
    #expect(Set(records.map(\.id)).count == 12)
    #expect(records.map(\.id) == nextDay.map(\.id))
    #expect(records.map { $0.draft.source?.id } == nextDay.map { $0.draft.source?.id })
    for record in records { try record.validateReviewState(catalog: .prototype) }
    #expect(records.contains { $0.classificationProvenance.category == .assistant })
    #expect(records.contains { $0.classificationProvenance.category == .user })
    #expect(records.contains { $0.discussionProgress == .reviewingInChatGPT })
    let range = try WorkspacePeriod.oneMonth.range(through: TransactionDate("2026-10-24"))
    #expect(LedgerSelection(from: range.from, through: range.through).records(in: records).count == 8)
}

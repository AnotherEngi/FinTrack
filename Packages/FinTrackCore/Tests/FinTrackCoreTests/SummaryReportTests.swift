import Foundation
import Testing
@testable import FinTrackCore

private func summaryRecord(_ date: String, _ cents: Int64, category: String = "sample-household",
                           treatment: TransactionTreatment = .spending, posting: PostingStatus = .posted,
                           tags: [String] = [], links: [RefundAllocation]? = nil) throws -> LedgerTransaction {
    try LedgerTransaction(draft: TransactionDraft(date: TransactionDate(date), payee: "Fictional summary purchase",
        amount: Money(minorUnits: cents), postingStatus: posting, treatment: treatment, categoryID: category,
        tags: tags, refundAllocations: links))
}

@Test func delayedRefundReducesOriginalMarchPurchaseEvenWhenJuneIsOutsideSelectedDates() throws {
    let purchase = try summaryRecord("2026-03-01", 10000)
    let refund = try summaryRecord("2026-06-12", -2500, category: "sample-transit", treatment: .refund,
        links: [.init(purchaseID: purchase.id, amount: Money(minorUnits: 2500))])
    let data = try SummaryReport(records: [purchase, refund], catalog: .prototype,
        from: TransactionDate("2026-03-01"), through: TransactionDate("2026-03-31"))
    #expect(data.total.minorUnits == 7500)
    #expect(data.purchases.first?.date.iso8601 == "2026-03-01")
    #expect(data.purchases.first?.refundIDs == [refund.id])
    #expect(data.categories.first?.id == "sample-household")
    #expect(refund.draft.date.iso8601 == "2026-06-12" && refund.draft.amount.minorUnits == -2500)
    let june = try SummaryReport(records: [purchase, refund], catalog: .prototype,
        from: TransactionDate("2026-06-01"), through: TransactionDate("2026-06-30"))
    #expect(june.total.minorUnits == 0 && june.purchases.isEmpty)
}

@Test func splitRefundReducesEachPurchaseAndLeavesUnallocatedRemainderForLinking() throws {
    let first = try summaryRecord("2026-03-01", 1000)
    let second = try summaryRecord("2026-04-01", 1000, category: "sample-groceries")
    let refund = try summaryRecord("2026-06-12", -1500, treatment: .refund, links: [
        .init(purchaseID: first.id, amount: Money(minorUnits: 700)),
        .init(purchaseID: second.id, amount: Money(minorUnits: 500))])
    let data = try SummaryReport(records: [first, second, refund], catalog: .prototype)
    #expect(data.total.minorUnits == 800)
    #expect(data.unallocatedRefundIDs == [refund.id])
    #expect(data.unallocatedRefundAmount.minorUnits == 300)
    #expect(data.purchases.first { $0.id == first.id }?.net.minorUnits == 300)
    #expect(data.purchases.first { $0.id == second.id }?.net.minorUnits == 500)
}

@Test func excessDuplicateMissingAndNonPurchaseRefundLinksAreRejected() throws {
    let purchase = try summaryRecord("2026-03-01", 1000)
    let link = RefundAllocation(purchaseID: purchase.id, amount: Money(minorUnits: 600))
    let first = try summaryRecord("2026-06-01", -600, treatment: .refund, links: [link])
    let second = try summaryRecord("2026-06-02", -600, treatment: .refund, links: [link])
    #expect(throws: (any Error).self) { try RefundAccounting.validate(records: [purchase, first, second]) }
    #expect(throws: (any Error).self) { try RefundAccounting.validate(records: [first]) }
    #expect(throws: (any Error).self) { try summaryRecord("2026-06-01", -1200, treatment: .refund, links: [link, link]) }
    #expect(throws: (any Error).self) { try summaryRecord("2026-06-01", -500, treatment: .refund, links: [link]) }
    #expect(throws: (any Error).self) { try summaryRecord("2026-06-01", 600, links: [link]) }
    var pending = purchase.draft; pending.postingStatus = .pending
    let pendingPurchase = try purchase.revising(with: pending, expectedRevision: 1)
    #expect(throws: (any Error).self) { try RefundAccounting.validate(records: [pendingPurchase, first]) }
}

@Test func fullRefundLeavesZeroNetPurchaseWhileUnlinkedRefundNeverBecomesANegativeSlice() throws {
    let purchase = try summaryRecord("2026-03-01", 1000)
    let linked = try summaryRecord("2026-06-01", -1000, treatment: .refund,
        links: [.init(purchaseID: purchase.id, amount: Money(minorUnits: 1000))])
    let unlinked = try summaryRecord("2026-06-02", -2000, treatment: .refund)
    let data = try SummaryReport(records: [purchase, linked, unlinked], catalog: .prototype)
    #expect(data.total.minorUnits == 0)
    #expect(data.purchases.count == 1 && data.purchases.first?.net.minorUnits == 0)
    #expect(data.categories.allSatisfy { $0.amount.minorUnits >= 0 })
    #expect(data.unallocatedRefundIDs == [unlinked.id] && data.unallocatedRefundAmount.minorUnits == 2000)
}

@Test func visibilityUsesIndividualCategoryAndTagUnionAndShowHiddenDoesNotBypassTemporaryFilters() throws {
    let first = try summaryRecord("2026-03-01", 100, category: "sample-household")
    let second = try summaryRecord("2026-03-02", 200, category: "sample-transit")
    let third = try summaryRecord("2026-03-03", 300, category: "sample-groceries", tags: ["Fictional travel"])
    let future = try summaryRecord("2026-03-04", 400, category: "sample-transit")
    let all = [first, second, third, future]
    let settings = SummaryVisibility(recordIDs: [first.id], categoryIDs: ["sample-transit"], tags: ["Fictional travel"])
    #expect(all.allSatisfy { settings.hides($0) })
    #expect(try SummaryReport(records: all, catalog: .prototype, visibility: settings).total.minorUnits == 0)
    #expect(try SummaryReport(records: all, catalog: .prototype, visibility: settings, showHidden: true).total.minorUnits == 1000)
    #expect(try SummaryReport(records: all, catalog: .prototype, visibility: settings, showHidden: true,
        excludedCategories: ["sample-transit"]).total.minorUnits == 400)
    #expect(try ReviewExport(records: all, catalog: .prototype).packet.transactions.count == 4)
}

@Test func visibilityAndRefundAllocationsSurviveBackupAndOldPayloadsRemainReadable() throws {
    let purchase = try summaryRecord("2026-03-01", 1000)
    let refund = try summaryRecord("2026-06-01", -100, treatment: .refund,
        links: [.init(purchaseID: purchase.id, amount: Money(minorUnits: 100))])
    var workspace = ReviewWorkspace()
    workspace.summaryVisibility = SummaryVisibility(recordIDs: [purchase.id], categoryIDs: ["sample-transit"], tags: ["Fictional"])
    let archive = try ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(FullBackup(records: [purchase, refund], workspace: workspace)))
    try archive.validate(catalog: .prototype)
    #expect(archive.workspace.summaryVisibility == workspace.summaryVisibility)
    #expect(archive.records == [purchase, refund])
    var object = try #require(JSONSerialization.jsonObject(with: ExchangeJSON.encode(workspace)) as? [String: Any])
    object.removeValue(forKey: "summaryVisibility")
    let old = try ExchangeJSON.decode(ReviewWorkspace.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(old.summaryVisibility == nil)
    let draft = try ExchangeJSON.decode(TransactionDraft.self, from: ExchangeJSON.encode(purchase.draft))
    #expect(draft.refundAllocations == nil)
    #expect(try TransactionInput(draft: refund.draft).value() == refund.draft)
    workspace.summaryVisibility = .init(recordIDs: [UUID()])
    #expect(throws: (any Error).self) { try FullBackup(records: [purchase, refund], workspace: workspace).validate(catalog: .prototype) }
}

@Test func bucketIntervalUsesSelectedDurationAndMondayWeeksAcrossYears() throws {
    let record = try summaryRecord("2026-01-01", 100)
    let week = try SummaryReport(records: [record], catalog: .prototype)
    #expect(week.interval == .week && week.bars.first?.periodID == "2025-12-29")
    let month = try SummaryReport(records: [record], catalog: .prototype,
        from: TransactionDate("2026-01-01"), through: TransactionDate("2026-12-31"))
    #expect(month.interval == .month && month.bars.first?.periodID == "2026-01")
    let year = try SummaryReport(records: [record], catalog: .prototype,
        from: TransactionDate("2020-01-01"), through: TransactionDate("2026-12-31"))
    #expect(year.interval == .year && year.bars.first?.periodID == "2026")
    let distant = try summaryRecord("2020-01-01", 100)
    let filtered = try SummaryReport(records: [distant, record], catalog: .prototype,
        visibility: .init(recordIDs: [distant.id]))
    #expect(filtered.interval == .year)
}

@Test func summaryKeepsPendingSeparateIgnoresIncomeAndChecksOverflowAndReversedDates() throws {
    let posted = try summaryRecord("2026-03-01", 100)
    let pending = try summaryRecord("2026-03-01", 200, posting: .pending)
    let income = try summaryRecord("2026-03-01", -300, treatment: .income)
    let data = try SummaryReport(records: [posted, pending, income], catalog: .prototype)
    #expect(data.total.minorUnits == 100 && data.pending.minorUnits == 200 && data.purchases.count == 1)
    let huge = try summaryRecord("2026-03-01", Int64.max)
    #expect(throws: (any Error).self) { try SummaryReport(records: [posted, huge], catalog: .prototype) }
    #expect(throws: (any Error).self) { try SummaryReport(records: [posted], catalog: .prototype,
        from: TransactionDate("2026-04-01"), through: TransactionDate("2026-03-01")) }
    #expect(try SummaryReport(records: [posted], catalog: .prototype,
        from: TransactionDate("2026-04-01")).purchases.isEmpty)
}

@Test func refundFeedbackIncludesRelatedPurchasesAndExactReadOnlyAllocationsInReviewPacket() throws {
    let purchase = try summaryRecord("2026-03-01", Int64.max)
    let old = try summaryRecord("2026-06-12", -9_007_199_254_740_993, treatment: .refund)
    var draft = old.draft
    draft.refundAllocations = [.init(purchaseID: purchase.id, amount: Money(minorUnits: 9_007_199_254_740_993))]
    let refund = try old.revising(with: draft, expectedRevision: 1)
    var workspace = ReviewWorkspace(); workspace.establishBaseline(records: [])
    workspace.recordUserChange(before: old, after: refund)
    let packet = try workspace.prepare(records: [purchase, refund], catalog: .prototype, mode: .pending)
    #expect(packet.snapshot?.transactions.count == 2)
    #expect(workspace.pending.first?.savedValues["refundAllocations"]?.contains("9007199254740993") == true)
    let value = try #require(packet.snapshot?.transactions.first { $0.transactionID == refund.id })
    #expect(value.refundAllocations == draft.refundAllocations)
    let data = try ExchangeJSON.encode(draft.refundAllocations)
    #expect(String(decoding: data, as: UTF8.self).contains("\"9007199254740993\""))
}

@Test func hidingRefundSuppressesItsAdjustmentUntilShowHiddenIsEnabled() throws {
    let purchase = try summaryRecord("2026-03-01", 1000)
    let refund = try summaryRecord("2026-06-12", -200, treatment: .refund,
        links: [.init(purchaseID: purchase.id, amount: Money(minorUnits: 200))])
    let settings = SummaryVisibility(recordIDs: [refund.id])
    #expect(try SummaryReport(records: [purchase, refund], catalog: .prototype, visibility: settings).total.minorUnits == 1000)
    #expect(try SummaryReport(records: [purchase, refund], catalog: .prototype, visibility: settings, showHidden: true).total.minorUnits == 800)
}

@Test func extremeLegacyRefundRemainsExportableWhileUnsupportedSummaryMagnitudeFailsSafely() throws {
    let refund = try summaryRecord("2026-06-12", Int64.min, treatment: .refund)
    try FullBackup(records: [refund], workspace: .init()).validate(catalog: .prototype)
    #expect(try ReviewExport(records: [refund], catalog: .prototype).packet.transactions.first?.amountMinorUnits == "-9223372036854775808")
    #expect(throws: (any Error).self) { try SummaryReport(records: [refund], catalog: .prototype) }
}

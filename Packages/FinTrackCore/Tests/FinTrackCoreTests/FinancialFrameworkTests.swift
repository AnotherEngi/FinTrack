import Foundation
import Testing
@testable import FinTrackCore

let frameworkRefundID = UUID(uuidString: "50000000-0000-4000-8000-000000000005")!
func frameworkImport() throws -> HistoryImport {
    let categories = [ReviewCategory(id: "food", label: "Food", storedLabel: "Food source", definition: .string("Meals and groceries"), origin: .user,
        subcategories: [.init(id: "pantry", label: "Pantry", definition: .string("Shelf stable food"), origin: .user)]),
        ReviewCategory(id: "supplies", label: "Supplies"), ReviewCategory(id: "unused", label: "Unused definition", definition: .string("Retain me"))]
    let oldID = UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
    let newID = UUID(uuidString: "30000000-0000-4000-8000-000000000003")!
    let earlier = HistoricalDecision(approved: true, evidence: "Source explicitly approved; decision timestamp not supplied")
    let old = SourceVersion(id: oldID, identity: .init(sourceAlias: "Fictional Card", transactionID: "pending-synthetic"),
        date: try .init("2026-02-28"), merchant: "Fictional pending shop", amount: .init(minorUnits: 9000), observedStatus: .pending,
        successorID: newID, notes: [.init(ownership: .ledgerFact, text: "Original pending amount")], decisions: [earlier])
    let current = SourceVersion(id: newID, identity: .init(sourceAlias: "Fictional Card", transactionID: "posted-synthetic"),
        date: try .init("2026-03-02"), activityDate: try .init("2026-03-01"), timestamp: .init(original: "2026-03-01T23:45:00-05:00", timeZone: "America/New_York", precision: "second"),
        merchant: "Fictional shop", amount: .init(minorUnits: 10000), observedStatus: .posted)
    var draft = try TransactionDraft(date: .init("2026-03-02"), payee: "Fictional shop", amount: .init(minorUnits: 10000),
        notes: "User durable note", treatment: .spending, categoryID: "food", tags: ["Travel"], activityDate: .init("2026-03-01"),
        source: .init(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, label: "Fictional Card"))
    draft.primarySubcategoryID = "pantry"
    draft.allocations = [.init(id: TransactionDraft.primaryAllocationID, categoryID: "food", subcategoryID: "pantry", amount: .init(minorUnits: 6000), origin: .user),
        .init(id: UUID(uuidString: "40000000-0000-4000-8000-000000000004")!, categoryID: "supplies", amount: .init(minorUnits: 4000), origin: .assistant)]
    draft.sourceVersions = [old, current]; draft.historicalDecisions = [earlier]; draft.questionState = .open
    draft.sourceNotes = [.init(ownership: .mixed, text: "Uncertain ownership; retain"), .init(ownership: .assistantReason, text: "Temporary rationale")]
    draft.archivalFields = ["Ledger!Other": .init(.init(kind: .null)), "Ledger!Empty": .init(.string(""))]
    draft.reportedVisibility = .unknown
    let purchase = try LedgerTransaction(id: UUID(uuidString: "60000000-0000-4000-8000-000000000006")!, draft: draft,
        assistantContext: .init(question: "Food or supplies?"), classificationProvenance: .init(category: .assistant, tags: ["Travel": .unknown]))
    var receiptDraft = try TransactionDraft(date: .init("2026-04-01"), payee: "Fictional repayment", amount: .init(minorUnits: -3000), treatment: .reimbursementReceipt)
    receiptDraft.archivalFields = ["Ledger!Other": .init(.absent)]
    let receipt = try LedgerTransaction(id: UUID(uuidString: "70000000-0000-4000-8000-000000000007")!, draft: receiptDraft)
    var reporting = ReportingConfiguration(); reporting.asOf = try .init("2026-06-12")
    reporting.coverage = [.init(source: "Fictional Card", from: try .init("2026-02-01"), through: try .init("2026-06-12"), status: .partial, limitations: "Synthetic coverage only")]
    let program = BenefitProgram(label: "Fictional benefit")
    let claim = ReimbursementClaim(expenseID: purchase.id, programID: program.id, eligibility: .unknown, expected: .init(minorUnits: 3000), status: .partial)
    let rows = [MigrationRow(locator: "Ledger!2", disposition: .historical, recordID: purchase.id, versionID: oldID, source: "Fictional Card", tab: "Ledger", treatment: .spending, amount: old.amount),
        MigrationRow(locator: "Ledger!3", disposition: .active, recordID: purchase.id, versionID: newID, source: "Fictional Card", tab: "Ledger", treatment: .spending, amount: current.amount),
        MigrationRow(locator: "Ledger!4", disposition: .active, recordID: receipt.id, source: "Fictional Card", tab: "Ledger", treatment: .reimbursementReceipt, amount: receipt.draft.amount),
        MigrationRow(locator: "Ledger!5", disposition: .deferredRefund, recordID: frameworkRefundID, source: "Fictional Card", tab: "Ledger", treatment: .refund, amount: .init(minorUnits: -1000))]
    let records = [purchase, receipt]
    let controls = try HistoryAudit.calculate(rows: rows, records: records)
    let audit = HistoryAudit(columns: [.init(name: "Ledger!Amount", handling: "mapped", target: .amount, explanation: "Exact cents"),
        .init(name: "Ledger!Other", handling: "preserved", target: .archival, explanation: "Null is distinct from empty")], rows: rows, controls: controls)
    return HistoryImport(id: UUID(uuidString: "80000000-0000-4000-8000-000000000008")!, sourceName: "Fictional workbook", records: records, categories: categories, audit: audit,
        accounts: [.init(id: draft.source!.id, alias: "Fictional Card")], programs: [program], claims: [claim],
        repayments: [.init(receiptID: receipt.id, claimID: claim.id, amount: .init(minorUnits: 2000), expenseAllocationID: TransactionDraft.primaryAllocationID)],
        reporting: reporting, sourceBaselines: [.init(label: "Original source gross basis", basis: ["refunds": .string("Deferred")], controls: controls)])
}
func frameworkRefund(_ history: HistoryImport) throws -> RefundImport {
    let purchase = history.records[0]
    let links = try RefundAccounting.proportional(amount: .init(minorUnits: 1000), purchase: purchase, records: history.records)
    let record = try LedgerTransaction(id: frameworkRefundID, draft: .init(date: .init("2026-06-12"), payee: "Fictional refund", amount: .init(minorUnits: -1000),
        treatment: .refund, categoryID: "food", refundAllocations: links))
    return RefundImport(migrationID: history.id, records: [record], locators: ["Ledger!5"], purchaseRevisions: [purchase.id.uuidString: "1"])
}

@Test func currentFrameworkMigrationPreservesFinancialMeaningAndUnknownEvidence() throws {
    let history = try HistoryImport.decode(ExchangeJSON.encode(frameworkImport()))
    let backup = try history.snapshot(); let purchase = history.records[0]
    #expect(backup.records.count == 2 && purchase.draft.allocations.count == 2)
    #expect(purchase.approval == .unreviewed && purchase.draft.historicalDecisions[0].approved == true)
    #expect(purchase.draft.historicalDecisions[0].decidedAt == nil)
    #expect(purchase.draft.exceptionalEvent == nil && purchase.draft.reportedVisibility.kind == .unknown)
    #expect(purchase.draft.sourceVersions[0].amount.minorUnits == 9000 && purchase.draft.sourceVersions[0].lifecycle == .superseded)
    #expect(backup.workspace.sourceLinks.count == 2)
    #expect(history.categories.last?.definition.text == "Retain me")
    #expect(history.programs[0].limit == nil && history.programs[0].period.basis == .unknown)
    let all = try #require(history.audit.controls.first { $0.group == "all" })
    #expect(all.debitMinorUnits == "19000" && all.creditMinorUnits == "4000" && all.netMinorUnits == "15000" && all.spendingMinorUnits == "10000")
}
@Test func splitsAndActualReceiptsReportOnceWithoutExpectedDoubleCounting() throws {
    let history = try frameworkImport(); let backup = try history.snapshot()
    let report = try SummaryReport(records: backup.records, catalog: .init(categories: history.categories), workspace: backup.workspace)
    #expect(report.total.minorUnits == 10000 && report.netCost.minorUnits == 8000 && report.receipts.minorUnits == 3000)
    #expect(report.purchases.count == 1 && report.categories.count == 2)
    #expect(report.categories.first { $0.id == "food" }?.amount.minorUnits == 6000)
    #expect(try FinancialAccounting.outstanding(claim: history.claims[0], workspace: backup.workspace)?.minorUnits == 1000)
}
@Test func deferredRefundStageUsesConfirmedExactAllocationAndPurchaseDate() throws {
    let history = try frameworkImport(); let initial = try history.snapshot(); let value = try frameworkRefund(history)
    #expect(value.records[0].draft.refundAllocations?.map(\.amount.minorUnits) == [600, 400])
    let final = try value.applying(to: initial)
    let report = try SummaryReport(records: final.records, catalog: .init(categories: history.categories), from: .init("2026-03-01"), through: .init("2026-03-31"), workspace: final.workspace)
    #expect(report.total.minorUnits == 9000 && report.netCost.minorUnits == 7000)
    #expect(report.receipts.minorUnits == 0 && report.purchases[0].date.iso8601 == "2026-03-01")
    #expect(try value.applying(to: final).records == final.records)
    var changed = value; changed.locators = []
    #expect(throws: (any Error).self) { try changed.applying(to: final) }
}
@Test func sourceControlOffsetsCannotHideMissingDebitAndCreditRows() throws {
    var value = try frameworkImport()
    value.audit.controls[0].debitMinorUnits = "20000"; value.audit.controls[0].creditMinorUnits = "5000"
    #expect(value.audit.controls[0].netMinorUnits == "15000")
    #expect(throws: (any Error).self) { try value.snapshot() }
}
@Test func invalidFinancialGraphsFailBeforeImport() throws {
    let original = try frameworkImport()
    let mutations: [(inout HistoryImport) throws -> Void] = [
        { $0.records.append($0.records[0]) },
        { $0.claims[0].expenseID = UUID() },
        { $0.claims[0].programID = UUID() },
        { $0.repayments[0].amount = .init(minorUnits: 3001) },
        { $0.repayments[0].receiptID = $0.records[0].id },
        { $0.repayments[0].expenseAllocationID = UUID() },
        { $0.audit.rows[0].versionID = UUID() },
        { $0.audit.rows[0].recordID = UUID() },
        { $0.audit.rows[3].recordID = $0.records[0].id },
        { $0.audit.sourceRowCount += 1 },
        { $0.audit.columns[0].handling = "unrecognized" },
        { $0.reporting.timeZone = "UTC" },
        { $0.reporting.firstWeekday = 1 },
        { $0.relationships = [.init(kind: .paymentCounterpart, from: $0.records[0].id, to: $0.records[1].id, evidence: "Wrong type")] }
    ]
    for mutate in mutations { var value = original; try mutate(&value); #expect(throws: (any Error).self) { try value.snapshot() } }
}
@Test func nestedUnknownFieldsAndNumericMoneyAreRejected() throws {
    let original = try ExchangeJSON.encode(frameworkImport())
    for path in ["root", "allocation", "money"] {
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        if path == "root" { object["unexpected"] = true }
        else {
            var records = object["records"] as! [[String: Any]]; var draft = records[0]["draft"] as! [String: Any]
            if path == "money" { draft["amount"] = ["minorUnits": 10000, "currency": "USD"] }
            else { var parts = draft["allocations"] as! [[String: Any]]; parts[0]["invented"] = true; draft["allocations"] = parts }
            records[0]["draft"] = draft; object["records"] = records
        }
        #expect(throws: (any Error).self) { try HistoryImport.decode(JSONSerialization.data(withJSONObject: object)) }
    }
}
@Test func splitEditsRequireExactBalanceAndPrimaryCategory() throws {
    let history = try frameworkImport(); let record = history.records[0]; let catalog = try ReviewCatalog(categories: history.categories)
    var input = TransactionInput(draft: record.draft)
    input.allocations[1].amountText = "25.25"
    let saved = try input.value(); try saved.validateAllocations(catalog: catalog)
    #expect(saved.allocations[0].amount.minorUnits == 7475 && saved.allocations[1].amount.minorUnits == 2525)
    #expect(saved.sourceVersions == record.draft.sourceVersions && saved.sourceNotes == record.draft.sourceNotes)
    input.allocations[1].amountText = "100.01"
    #expect(throws: (any Error).self) { try input.value() }
    var bad = saved; bad.allocations[0].amount = .init(minorUnits: 7474)
    #expect(throws: (any Error).self) { try bad.validateAllocations(catalog: catalog) }
}
@Test func unknownNullEmptyZeroAndFalseSurviveTypedRoundTrip() throws {
    let values: [SourceValue] = [.absent, .unknown, .init(kind: .null), .string(""), .init(kind: .number, text: "0"), .init(kind: .boolean, boolean: false)]
    for value in values { try value.validate(); #expect(try StrictJSON.decode(SourceValue.self, from: ExchangeJSON.encode(value)) == value) }
    #expect(Set(values.map(\.display)).count == 6)
}
@Test func approvalClearsKnownAssistantTextButRetainsMixedAndUserEvidence() throws {
    let history = try frameworkImport(); let record = history.records[0]
    let approved = try record.applying(.init(transactionID: record.id, expectedRevision: 1, action: .approve), catalog: .init(categories: history.categories))
    #expect(approved.approval == .confirmed && approved.draft.questionState == .resolved)
    #expect(approved.assistantContext.question.isEmpty && approved.draft.sourceNotes.count == 1)
    #expect(approved.draft.sourceNotes[0].ownership == .mixed && approved.draft.notes == "User durable note")
    #expect(approved.draft.sourceVersions == record.draft.sourceVersions && approved.draft.historicalDecisions == record.draft.historicalDecisions)
}
@Test func fullArchiveAndReviewCarryCompleteCurrentFramework() throws {
    let history = try frameworkImport(); let backup = try frameworkRefund(history).applying(to: history.snapshot())
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("synthetic.fintrack"); try BackupArchive.write(backup, to: url)
    let restored = try BackupArchive.read(from: url)
    #expect(restored.records == backup.records)
    #expect(try ExchangeJSON.encode(FinancialContext(workspace: restored.workspace)) == ExchangeJSON.encode(FinancialContext(workspace: backup.workspace)))
    var workspace = restored.workspace
    let packet = try workspace.prepare(records: restored.records, catalog: .init(categories: history.categories), mode: .fullHistory)
    #expect(packet.snapshot?.transactions[0].allocations.count ?? 0 > 0)
    #expect(packet.financialContext.programs.count == 1 && packet.financialContext.migrationAudit != nil)
    #expect(packet.financialContext.refundReceipts.count == 1)
}
@Test func refundCapAndStaleTargetProtectionRejectBeforeMutation() throws {
    let history = try frameworkImport(); let backup = try history.snapshot()
    var stale = try frameworkRefund(history); stale.purchaseRevisions[history.records[0].id.uuidString] = "2"
    #expect(throws: (any Error).self) { try stale.applying(to: backup) }
    #expect(throws: (any Error).self) { try RefundAccounting.proportional(amount: .init(minorUnits: 10001), purchase: history.records[0], records: history.records) }
    var draft = history.records[0].draft; draft.sourceVersions[0].successorID = draft.sourceVersions[0].id
    #expect(throws: (any Error).self) { try draft.validateEvidence() }
}
@Test func proportionalAllocationUsesRemainingBalancesAndExactLargestRemainders() throws {
    let history = try frameworkImport(); let purchase = history.records[0]
    let penny = try RefundAccounting.proportional(amount: .init(minorUnits: 1), purchase: purchase, records: history.records)
    #expect(penny.count == 1 && penny[0].amount.minorUnits == 1 && penny[0].allocationID == TransactionDraft.primaryAllocationID)
    let first = try frameworkRefund(history).records[0]
    let rest = try RefundAccounting.proportional(amount: .init(minorUnits: 9000), purchase: purchase, records: history.records + [first])
    #expect(rest.reduce(Int64(0)) { $0 + $1.amount.minorUnits } == 9000)
}
@Test func retiredPrototypeJSONAndWrongContractVersionsAreNotMigrated() throws {
    let bytes = Data("{\"schemaVersion\":1,\"purpose\":\"fintrack-history-import\"}".utf8)
    #expect(throws: (any Error).self) { try HistoryImport.decode(bytes) }
    #expect(throws: (any Error).self) { try ClipboardExchange.incoming(String(decoding: bytes, as: UTF8.self)) }
}

@Test func combinedRepaymentsAllocateActualCashAcrossClaimsWithoutInventingEligibility() throws {
    let history = try frameworkImport(); var workspace = try history.snapshot().workspace
    let second = try LedgerTransaction(draft: .init(date: .init("2026-03-10"), payee: "Fictional second purchase", amount: .init(minorUnits: 2000), treatment: .spending, categoryID: "food"))
    let claim = ReimbursementClaim(expenseID: second.id, expected: .init(minorUnits: 1500))
    workspace.claims.append(claim)
    workspace.repayments.append(.init(receiptID: history.records[1].id, claimID: claim.id, amount: .init(minorUnits: 1000)))
    let records = history.records + [second]; let catalog = try ReviewCatalog(categories: history.categories)
    try FinancialAccounting.validate(records: records, workspace: workspace, catalog: catalog)
    #expect(try FinancialAccounting.received(claimID: claim.id, workspace: workspace).minorUnits == 1000)
    #expect(try FinancialAccounting.outstanding(claim: claim, workspace: workspace)?.minorUnits == 500)
    let report = try SummaryReport(records: records, catalog: catalog, workspace: workspace)
    #expect(report.total.minorUnits == 12000 && report.netCost.minorUnits == 9000 && report.receipts.minorUnits == 3000)
    #expect(workspace.claims.allSatisfy { $0.eligibility == .unknown })
    workspace.repayments.append(.init(receiptID: history.records[1].id, claimID: claim.id, amount: .init(minorUnits: 1)))
    #expect(throws: (any Error).self) { try FinancialAccounting.validate(records: records, workspace: workspace, catalog: catalog) }
}
@Test func acceptedUnsplitPrimaryPurchaseDoesNotInventAMixedCategory() throws {
    let category = ReviewCategory(id: "primary", label: "Primary")
    let purchase = try LedgerTransaction(draft: .init(date: .init("2026-03-01"), payee: "Fictional combined goods", amount: .init(minorUnits: 1000), treatment: .spending, categoryID: category.id), approval: .confirmed)
    let report = try SummaryReport(records: [purchase], catalog: .init(categories: [category]))
    #expect(purchase.draft.allocations.isEmpty && report.total.minorUnits == 1000 && report.purchases.count == 1 && report.categories.count == 1)
    #expect(throws: (any Error).self) { try ReviewCatalog(categories: [.init(id: "mixed", label: "Mixed")]) }
    #expect(throws: (any Error).self) { try ReviewCatalog(categories: []) }
}
@Test func sourceReportingBaselineRemainsEvidenceWhenApprovalFilterChanges() throws {
    let history = try frameworkImport(); let snapshot = try history.snapshot()
    var workspace = snapshot.workspace
    let oldBaseline = snapshot.workspace.sourceBaselines
    workspace.reporting.includePostedUnreviewed = false
    let report = try SummaryReport(records: snapshot.records, catalog: .init(categories: history.categories), workspace: workspace)
    #expect(report.total.minorUnits == 0 && report.purchases.isEmpty)
    #expect(snapshot.workspace.sourceBaselines == oldBaseline && snapshot.workspace.sourceBaselines[0].controls.first?.spendingMinorUnits == "10000")
    #expect(!report.limitations.isEmpty)
}
@Test func sourceIdentityCanRetainMultipleVersionsUnderTheSameGenuineProviderID() throws {
    var history = try frameworkImport(); let record = history.records[0]
    var draft = record.draft; draft.sourceVersions[1].identity = draft.sourceVersions[0].identity
    history.records[0] = try LedgerTransaction(id: record.id, draft: draft, assistantContext: record.assistantContext, classificationProvenance: record.classificationProvenance)
    let snapshot = try history.snapshot()
    #expect(snapshot.workspace.sourceLinks.count == 1)
    #expect(snapshot.workspace.sourceLinks[0].original.amountMinorUnits == "9000" && snapshot.workspace.sourceLinks[0].latest.amountMinorUnits == "10000")
    #expect(snapshot.workspace.sourceLinks[0].supersededDigests?.count == 1)
}
@Test func omittedEssentialMeaningAndMissingPreservedCellsBlockTheWholeHistory() throws {
    var history = try frameworkImport(); history.audit.blockers = ["Unsupported essential formula behavior"]
    #expect(throws: (any Error).self) { try history.snapshot() }
    history = try frameworkImport(); history.audit.columns.append(.init(name: "Ledger!Required", handling: "omitted", target: nil, explanation: "Cannot represent this", essential: true))
    #expect(throws: (any Error).self) { try history.snapshot() }
    history = try frameworkImport(); history.audit.columns.append(.init(name: "Ledger!Missing", handling: "preserved", target: .archival, explanation: "Must actually preserve it"))
    #expect(throws: (any Error).self) { try history.snapshot() }
}
@Test func sourceNotesDoNotBecomePermanentCopiesOfKnownResolvedAssistantText() throws {
    var history = try frameworkImport(); let record = history.records[0]
    var draft = record.draft; draft.questionState = .resolved
    draft.archivalFields["Known resolved reason"] = .init(.string("TEMPORARY_ASSISTANT_REASON"), ownership: .assistantReason)
    history.records[0] = try LedgerTransaction(id: record.id, draft: draft, assistantContext: .init(question: "KNOWN_RESOLVED_QUESTION", reason: "TEMPORARY_ASSISTANT_REASON"), classificationProvenance: record.classificationProvenance)
    let snapshot = try history.snapshot()
    #expect(!String(decoding: try ExchangeJSON.encode(snapshot), as: UTF8.self).contains("TEMPORARY_ASSISTANT_REASON"))
    #expect(!String(decoding: try ExchangeJSON.encode(snapshot), as: UTF8.self).contains("KNOWN_RESOLVED_QUESTION"))
    #expect(snapshot.records[0].draft.sourceNotes.contains { $0.ownership == .mixed })
}
@Test func filteredNetCostUsesAttributedRepaymentsAndSplitSelection() throws {
    let history = try frameworkImport(); let snapshot = try history.snapshot()
    let report = try SummaryReport(records: snapshot.records, catalog: .init(categories: history.categories), excludedCategories: ["supplies"], workspace: snapshot.workspace)
    #expect(report.total.minorUnits == 6000 && report.netCost.minorUnits == 4000 && report.purchases[0].categoryAmounts["supplies"] == nil)
}
@Test func sourceBaselinesAndArchivalContextDoNotLeakThroughAnExcludedTextExport() throws {
    let history = try frameworkImport(); let packet = try ReviewExport(records: history.records, catalog: .init(categories: history.categories))
    let bytes = String(decoding: packet.json, as: UTF8.self)
    #expect(!bytes.contains("User durable note") && !bytes.contains("Uncertain ownership; retain") && !bytes.contains("Temporary rationale"))
    #expect(packet.csv.contains("structured_record_json"))
}

@Test func publishedCurrentContractExamplesPassTheActualDecoders() throws {
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 { repository.deleteLastPathComponent() }
    let directory = repository.appendingPathComponent("docs/contracts/examples", isDirectory: true)
    if ProcessInfo.processInfo.environment["FINTRACK_WRITE_SYNTHETIC_EXAMPLES"] == "1" {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let history = try frameworkImport()
        var workspace = try history.snapshot().workspace
        let request = try workspace.prepare(records: history.records, catalog: .init(categories: history.categories), mode: .fullHistory)
        let response = ReviewResponse(packetID: request.manifest.id, knowledgeVersion: request.manifest.knowledgeVersion,
            proposals: [.init(recordID: history.records[0].id, expectedRevision: "1", tags: ["Travel", "Synthetic"], rationale: "Fictional tag refinement for explicit review")],
            summary: "Synthetic response only", answers: [.init(recordID: history.records[0].id, expectedRevision: "1", text: "This fictional purchase has a balanced Food/Supplies split.")])
        let weekly = WeeklyBatch(coverage: "Fictional Card · 2026-06-13 through 2026-06-19 · partial synthetic coverage", transactions: [
            WeeklyTransaction(identity: .init(sourceAlias: "Fictional Card", transactionID: "weekly-synthetic-0001"), date: "2026-06-19", merchant: "Fictional weekly merchant", amountMinorUnits: "1234", categoryID: "food")])
        try ExchangeJSON.encode(history).write(to: directory.appendingPathComponent("history.synthetic.json"), options: .atomic)
        try ExchangeJSON.encode(frameworkRefund(history)).write(to: directory.appendingPathComponent("refunds.synthetic.json"), options: .atomic)
        try ExchangeJSON.encode(request).write(to: directory.appendingPathComponent("review-request.synthetic.json"), options: .atomic)
        try ExchangeJSON.encode(response).write(to: directory.appendingPathComponent("review-response.synthetic.json"), options: .atomic)
        try ExchangeJSON.encode(weekly).write(to: directory.appendingPathComponent("weekly.synthetic.json"), options: .atomic)
    }
    func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name + ".synthetic.json")) }
    let history = try HistoryImport.decode(read("history"))
    let refunds = try StrictJSON.decode(RefundImport.self, from: read("refunds"))
    #expect(try refunds.applying(to: history.snapshot()).records.count == 3)
    var incoming = ReviewWorkspace(); try incoming.stage(read("weekly"))
    #expect(incoming.staged.count == 1)
    let request = try StrictJSON.decode(ReviewEnvelope.self, from: read("review-request"))
    var context = ReviewWorkspace(); context.manifests = [request.manifest]
    context.knowledgeVersion = request.manifest.knowledgeVersion
    try context.receive(read("review-response"))
    #expect(context.staged.count == 1)
}

@Test func successfulAutosaveRebasesEvidenceWithoutReformattingInputOrChangingSourceIDs() throws {
    var input = TransactionInput(dateText: "2026-03-01", payee: "Fictional typing", amountText: "1", treatment: .spending, categoryID: "food")
    let sourceID = input.sourceID
    let value = try input.value(); input.rebase(on: value)
    #expect(input.amountText == "1" && input.sourceID == sourceID)
    let first = input; input.rebase(on: try input.value())
    #expect(input == first)
    input.amountText = "1.2"; input.rebase(on: try input.value())
    #expect(input.amountText == "1.2" && input.sourceID == sourceID)
}
@Test func pendingReviewIncludesConnectedReceiptPurchaseAndRefundContext() throws {
    let history = try frameworkImport(); let full = try frameworkRefund(history).applying(to: history.snapshot())
    var workspace = full.workspace
    workspace.pending = []; workspace.baselineEstablished = true
    workspace.pending.append(FeedbackEvent(before: full.records[1], after: full.records[1], kind: "synthetic-receipt-question"))
    let packet = try workspace.prepare(records: full.records, catalog: .init(categories: history.categories), mode: .pending)
    #expect(packet.snapshot?.transactions.count == 3 && packet.financialContext.claims.count == 1 && packet.financialContext.repayments.count == 1)
}

@Test func duplicateDeferredIdentitiesCannotCollapseTwoSourceRefundsIntoOneImport() throws {
    var history = try frameworkImport()
    var copy = history.audit.rows[3]; copy.locator = "Ledger!6"
    history.audit.rows.append(copy); history.audit.sourceRowCount += 1
    history.audit.controls = try HistoryAudit.calculate(rows: history.audit.rows, records: history.records)
    #expect(throws: (any Error).self) { try history.snapshot() }
}

@Test func standaloneSupersededApprovalEvidenceDoesNotInventAnActiveSuccessorOrSpending() throws {
    let version = try SourceVersion(identity: .init(sourceAlias: "Fictional Card", transactionID: "superseded-only"), date: .init("2026-01-01"), merchant: "Fictional superseded purchase",
        amount: .init(minorUnits: 500), observedStatus: .superseded, decisions: [.init(approved: true, evidence: "Source approved an earlier now-superseded classification")], treatment: .spending, categoryID: "food")
    let record = try LedgerTransaction(draft: .init(date: .init("2026-01-01"), payee: version.merchant, amount: version.amount, postingStatus: .superseded,
        treatment: .spending, categoryID: "food", sourceVersions: [version]))
    let rows = [MigrationRow(locator: "Old!2", disposition: .historical, recordID: record.id, versionID: version.id, source: "Fictional Card", tab: "Old", treatment: .spending, amount: version.amount)]
    let history = HistoryImport(sourceName: "Fictional supersession evidence", records: [record], categories: [.init(id: "food", label: "Food")],
        audit: .init(columns: [.init(name: "Old!Amount", handling: "mapped", target: .amount, explanation: "Earlier financial observation")], rows: rows, controls: try HistoryAudit.calculate(rows: rows, records: [record])))
    let snapshot = try history.snapshot()
    #expect(snapshot.records[0].draft.sourceVersions[0].successorID == nil && snapshot.records[0].draft.sourceVersions[0].decisions[0].approved == true)
    #expect(snapshot.records[0].approval == .unreviewed)
    #expect(try SummaryReport(records: snapshot.records, catalog: .init(categories: history.categories)).total.minorUnits == 0)
}

@Test func categoryAndSubcategorySearchIncludesSecondaryAllocationsByDisplayLabel() throws {
    let history = try frameworkImport()
    let selection = LedgerSelection(search: "Shelf goods", subcategoryLabels: ["food": ["pantry": "Shelf goods"]])
    #expect(selection.records(in: history.records).map(\.id) == [history.records[0].id])
    let secondary = LedgerSelection(search: "Office goods", categoryLabels: ["supplies": "Office goods"])
    #expect(secondary.records(in: history.records).count == 1)
}

@Test func aNewExplicitAssistantQuestionAfterClosureIsVisibleWithoutRevivingOldReplies() throws {
    let history = try frameworkImport(); let original = history.records[0]; let catalog = try ReviewCatalog(categories: history.categories)
    let closed = try original.applying(.init(transactionID: original.id, expectedRevision: original.revision, action: .approve), catalog: catalog)
    var workspace = ReviewWorkspace(); workspace.closeDiscussion(for: closed)
    let proposed = ClassificationProposal(recordID: closed.id, expectedRevision: String(closed.revision), tags: ["New tag"], question: "New classification question?", rationale: "New category/tag context")
    let updated = try closed.applyingSuggestion(proposed, catalog: catalog)
    #expect(updated.approval == .unreviewed && !workspace.isDiscussionClosed(for: updated))
    #expect(workspace.discussion(for: updated)?.originalQuestion == "New classification question?")
    #expect(workspace.discussion(for: updated)?.answers.isEmpty == true)
}

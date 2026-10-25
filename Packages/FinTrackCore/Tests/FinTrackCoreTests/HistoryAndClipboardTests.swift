import Foundation
import Testing
@testable import FinTrackCore

private func historyFixture(_ mutate: (inout [String: Any]) -> Void = { _ in }) throws -> Data {
    let text = """
    {"schemaVersion":1,"purpose":"fintrack-history-import","id":"11111111-1111-4111-8111-111111111111","amountSignConvention":"outflow-positive-v1","sourceName":"Fictional Sheet",
     "categories":[{"id":"food","label":"Fictional Food","unresolved":false,"excluded":false}],
     "rows":[{"id":"22222222-2222-4222-8222-222222222222","sourceRow":"Ledger!2","date":"2026-05-01","activityDate":null,"merchant":"Fictional Market","amountMinorUnits":"1234","currency":"USD","sourceLabel":"Fictional Card","sourceTransactionID":"genuine-fictional-bank-id","postingStatus":"posted","treatment":"spending","categoryID":"food","tags":["Fictional tag"],"notes":"User note","answer":"User answer","approval":"confirmed","approvalEvidence":"Explicit source Approved=true","discussionRequested":false,"assistantContext":{"question":"Old question","reason":"Old explanation","ledgerNotes":"Earlier ledger note"},"classificationProvenance":{"category":"user","tags":{"Fictional tag":"unknown"}},"exceptionalEvent":false,"hiddenFromSummary":true,"refundAllocations":null,"preservedFields":{"Subcategory":"Fictional pantry"}}],
     "audit":{"sourceRowCount":1,"netAmountMinorUnits":"1234","columns":[{"name":"Amount","handling":"mapped","target":"amountMinorUnits","explanation":"Exact positive outflow cents"},{"name":"Subcategory","handling":"preserved","target":"preservedFields","explanation":"Retained read-only; no live subcategory behavior"}],"excludedRows":[],"warnings":["Synthetic fixture only"]}}
    """
    var object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    mutate(&object)
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@Test func historyMigrationPreservesFinancialContextTaxonomyEvidenceAndSourceIdentity() throws {
    let value = try HistoryImport.decode(historyFixture())
    let backup = try value.snapshot()
    let record = try #require(backup.records.first)
    #expect(record.draft.notes == "User note" && record.draft.answer == "User answer")
    #expect(record.approval == .confirmed && record.assistantContext.question.isEmpty && record.assistantContext.reason.isEmpty)
    #expect(record.assistantContext.ledgerNotes == "Earlier ledger note")
    #expect(record.classificationProvenance.category == .user && record.draft.amount.minorUnits == 1234)
    #expect(backup.workspace.historyDetails?[record.id.uuidString]?["Subcategory"] == "Fictional pantry")
    #expect(backup.workspace.sourceLinks.first?.identity.transactionID == "genuine-fictional-bank-id")
    #expect(backup.workspace.summaryVisibility?.hides(record) == true)
    #expect(try backup.workspace.effectiveCatalog(fallback: .prototype).categories.first?.label == "Fictional Food")
    #expect(backup.workspace.pending.isEmpty && backup.workspace.baselineEstablished)
    try backup.validate(catalog: .prototype)
}

@Test func malformedHistoryCannotSilentlyDropUnsupportedFieldsRowsOrApprovals() throws {
    let mutations: [(inout [String: Any]) -> Void] = [
        { $0["unexpectedField"] = "Never silently drop this" },
        { var audit = $0["audit"] as! [String: Any]; audit["sourceRowCount"] = 2; $0["audit"] = audit },
        { var audit = $0["audit"] as! [String: Any]; audit["netAmountMinorUnits"] = "999"; $0["audit"] = audit },
        { var rows = $0["rows"] as! [[String: Any]]; rows[0]["approvalEvidence"] = ""; $0["rows"] = rows },
        { var rows = $0["rows"] as! [[String: Any]]; rows[0]["categoryID"] = "invented-missing-category"; $0["rows"] = rows },
        { var rows = $0["rows"] as! [[String: Any]]; rows[0]["preservedFields"] = [:]; $0["rows"] = rows },
        { var rows = $0["rows"] as! [[String: Any]]; rows[0]["amountMinorUnits"] = "12.34"; $0["rows"] = rows },
        { var rows = $0["rows"] as! [[String: Any]]; rows[0]["subCategory"] = "Unmapped value"; $0["rows"] = rows },
        { var rows = $0["rows"] as! [[String: Any]]; rows.append(rows[0]); $0["rows"] = rows }
    ]
    for mutate in mutations { #expect(throws: (any Error).self) { try HistoryImport.decode(historyFixture(mutate)) } }
}

@Test func missingBankIDsAreFlaggedAndNeverSynthesizedFromSheetRowNumbers() throws {
    let value = try HistoryImport.decode(historyFixture { object in
        var rows = object["rows"] as! [[String: Any]]; rows[0]["sourceTransactionID"] = NSNull(); object["rows"] = rows
    })
    #expect(try value.snapshot().workspace.sourceLinks.isEmpty)
    #expect(value.reviewWarnings.contains { $0.contains("no genuine bank transaction ID") })
}

@Test func historyImportPreservesActualGuidanceAndAuditsExplicitRowExclusions() throws {
    let value = try HistoryImport.decode(historyFixture { object in
        object["knowledge"] = [["id": UUID().uuidString, "text": "Fictional accepted category guidance", "origin": "user"]]
        var audit = object["audit"] as! [String: Any]
        audit["sourceRowCount"] = 2
        audit["excludedRows"] = [["sourceRow": "Ledger!3", "reason": "Synthetic subtotal; not another transaction"]]
        object["audit"] = audit
    })
    #expect(try value.snapshot().workspace.knowledge.first?.text == "Fictional accepted category guidance")
    #expect(value.reviewWarnings.contains { $0.contains("Excluded Ledger!3") })
    #expect(throws: (any Error).self) {
        try HistoryImport.decode(historyFixture { object in
            var audit = object["audit"] as! [String: Any]
            var columns = audit["columns"] as! [[String: Any]]
            columns[0]["target"] = "nonexistentField"; audit["columns"] = columns; object["audit"] = audit
        })
    }
}

@Test func publishedMigrationExamplesAreAcceptedByTheirActualImportContracts() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<4 { root.deleteLastPathComponent() }
    let text = try String(contentsOf: root.appendingPathComponent("docs/chatgpt-history-migration.md"), encoding: .utf8)
        .replacingOccurrences(of: "\r\n", with: "\n")
    let examples = text.components(separatedBy: "```json\n").dropFirst().map { String($0.components(separatedBy: "```")[0]) }
    #expect(examples.count == 2)
    let migration = try HistoryImport.decode(Data(try #require(examples.first).utf8))
    #expect(try migration.snapshot().records.count == 1)
    var workspace = ReviewWorkspace()
    try workspace.stage(Data(try #require(examples.last).utf8))
    #expect(workspace.staged.first?.purpose == "fintrack-weekly-intake")
}

@Test func historyTaxonomyAndDetailsSurviveArchiveAndAreAvailableToFullReview() throws {
    let initial = try HistoryImport.decode(historyFixture()).snapshot()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.fintrack")
    try BackupArchive.write(initial, to: url)
    let result = try BackupArchive.read(from: url)
    #expect(result.records == initial.records)
    #expect(result.workspace.importedCategories == initial.workspace.importedCategories)
    #expect(result.workspace.historyDetails == initial.workspace.historyDetails)
    #expect(result.workspace.historyImport?.digest == initial.workspace.historyImport?.digest)
    var workspace = result.workspace
    let catalog = try workspace.effectiveCatalog(fallback: .prototype)
    let packet = try workspace.prepare(records: result.records, catalog: catalog, mode: .fullHistory)
    #expect(packet.historyContext == initial.workspace.historyDetails)
    #expect(packet.snapshot?.categories.first?.id == "food")
}

@Test func historyBackupsRejectDanglingDetailsAndInvalidCatalogs() throws {
    let original = try HistoryImport.decode(historyFixture()).snapshot()
    var workspace = original.workspace
    workspace.historyDetails?[UUID().uuidString] = ["Other": "Orphaned detail"]
    #expect(throws: (any Error).self) { try FullBackup(records: original.records, workspace: workspace).validate(catalog: .prototype) }
    workspace = original.workspace
    workspace.importedCategories = []
    #expect(throws: (any Error).self) { try FullBackup(records: original.records, workspace: workspace).validate(catalog: .prototype) }
}

@Test func clipboardAcceptsOnlyCompleteBoundedReplyJSONAndAnOptionalSingleFence() throws {
    let record = try SyntheticTransactions.make()[0]
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        answers: [.init(recordID: record.id, expectedRevision: "1", text: "Fictional café answer")])
    let json = String(decoding: try ExchangeJSON.encode(response), as: UTF8.self)
    let raw = try ClipboardExchange.incoming(json)
    #expect(try ClipboardExchange.incoming("\u{feff}\n```json\n" + json + "\n```\n") == raw)
    try workspace.receive(raw)
    #expect(workspace.discussion(for: record)?.answers.first?.text == "Fictional café answer")
    for invalid in ["https://example.invalid/reply.json", "Here is your JSON:\n" + json, "```json\n" + json,
                    json + "{}", "{}", String(repeating: "x", count: ClipboardExchange.maximumBytes + 1),
                    "{\"schemaVersion\":1,\"purpose\":\"fintrack-full-backup\"}"] {
        #expect(throws: (any Error).self) { try ClipboardExchange.incoming(invalid) }
    }
}

@Test func clipboardReviewIncludesTheEntirePacketOrFailsWithoutTruncation() throws {
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: SyntheticTransactions.make(), catalog: .prototype, mode: .fullHistory)
    let bytes = try ExchangeJSON.encode(packet)
    let text = try ClipboardExchange.reviewText(bytes)
    #expect(text.hasSuffix(String(decoding: bytes, as: UTF8.self)) && text.contains(packet.manifest.id.uuidString))
    #expect(throws: (any Error).self) { try ClipboardExchange.reviewText(Data(repeating: 120, count: ClipboardExchange.maximumBytes)) }
}

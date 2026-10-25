import Foundation

public struct HistoryColumn: Codable, Equatable, Sendable {
    public let name: String
    public let handling: String
    public let target: String
    public let explanation: String
}
public struct HistoryExcludedRow: Codable, Equatable, Sendable {
    public let sourceRow: String
    public let reason: String
}
public struct HistoryAudit: Codable, Equatable, Sendable {
    public let sourceRowCount: Int
    public let netAmountMinorUnits: String
    public let columns: [HistoryColumn]
    public let excludedRows: [HistoryExcludedRow]
    public let warnings: [String]
}
public struct HistoryImportReceipt: Codable, Equatable, Sendable {
    public let id: UUID
    public let digest: String
    public let sourceName: String
    public let recordIDs: [UUID]
    public let audit: HistoryAudit
    public let importedAt: Date
}
public struct HistoryRow: Codable, Sendable {
    public let id: UUID
    public let sourceRow: String
    public let date: String
    public let activityDate: String?
    public let merchant: String
    public let amountMinorUnits: String
    public let currency: String
    public let sourceLabel: String?
    public let sourceTransactionID: String?
    public let postingStatus: PostingStatus
    public let treatment: TransactionTreatment
    public let categoryID: String?
    public let tags: [String]
    public let notes: String
    public let answer: String
    public let approval: ApprovalStatus
    public let approvalEvidence: String
    public let discussionRequested: Bool
    public let assistantContext: AssistantContext
    public let classificationProvenance: ClassificationProvenance
    public let exceptionalEvent: Bool
    public let hiddenFromSummary: Bool
    public let refundAllocations: [RefundAllocation]?
    public let preservedFields: [String: String]
}

/// One-time, explicitly reviewed history migration. It is never an AI proposal,
/// weekly merge, or silent replacement of the current ledger.
public struct HistoryImport: Codable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let purpose: String
    public let id: UUID
    public let amountSignConvention: String
    public let sourceName: String
    public let categories: [ReviewCategory]
    public let rows: [HistoryRow]
    public let audit: HistoryAudit
    public var knowledge: [KnowledgeRule]? = nil

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= ExchangeJSON.maximumBytes else { throw ExchangeError.invalid("History imports are limited to 50 MiB. No rows were imported.") }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExchangeError.invalid("Expected one history JSON object.") }
        func keys(_ value: [String: Any], _ allowed: Set<String>) throws {
            let extra = Set(value.keys).subtracting(allowed)
            guard extra.isEmpty else { throw ExchangeError.invalid("Unsupported history fields: " + extra.sorted().joined(separator: ", ") + ". Move unmapped details into preservedFields and document them in the audit.") }
        }
        try keys(object, ["schemaVersion", "purpose", "id", "amountSignConvention", "sourceName", "categories", "rows", "audit", "knowledge"])
        for rule in object["knowledge"] as? [[String: Any]] ?? [] { try keys(rule, ["id", "text", "origin"]) }
        for row in object["rows"] as? [[String: Any]] ?? [] {
            try keys(row, ["id", "sourceRow", "date", "activityDate", "merchant", "amountMinorUnits", "currency", "sourceLabel", "sourceTransactionID", "postingStatus", "treatment", "categoryID", "tags", "notes", "answer", "approval", "approvalEvidence", "discussionRequested", "assistantContext", "classificationProvenance", "exceptionalEvent", "hiddenFromSummary", "refundAllocations", "preservedFields"])
            if let context = row["assistantContext"] as? [String: Any] { try keys(context, ["question", "reason", "ledgerNotes"]) }
            if let origins = row["classificationProvenance"] as? [String: Any] { try keys(origins, ["category", "tags"]) }
            for link in row["refundAllocations"] as? [[String: Any]] ?? [] { try keys(link, ["purchaseID", "amountMinorUnits", "currency"]) }
        }
        for category in object["categories"] as? [[String: Any]] ?? [] { try keys(category, ["id", "label", "unresolved", "excluded"]) }
        if let audit = object["audit"] as? [String: Any] {
            try keys(audit, ["sourceRowCount", "netAmountMinorUnits", "columns", "excludedRows", "warnings"])
            for column in audit["columns"] as? [[String: Any]] ?? [] { try keys(column, ["name", "handling", "target", "explanation"]) }
            for row in audit["excludedRows"] as? [[String: Any]] ?? [] { try keys(row, ["sourceRow", "reason"]) }
        }
        let result = try ExchangeJSON.decode(Self.self, from: data)
        _ = try result.snapshot()
        return result
    }
    public var reviewWarnings: [String] {
        var result = audit.warnings
        for column in audit.columns where column.handling != "mapped" {
            result.append(column.name + ": " + column.handling + ". " + column.explanation)
        }
        for row in audit.excludedRows { result.append("Excluded " + row.sourceRow + ": " + row.reason) }
        let missing = rows.filter { $0.sourceTransactionID == nil }.count
        if missing > 0 { result.append("\(missing) rows have no genuine bank transaction ID. New weekly rows may need manual reconciliation; row numbers are not bank IDs.") }
        result.append("Sheet audit assertions come from the supplied file. FinTrack cannot independently prove that ChatGPT examined every source sheet or cell. Compare counts and totals with the original.")
        return result
    }
    public func snapshot(at: Date = .now) throws -> FullBackup {
        let targets: Set<String> = ["id", "sourceRow", "date", "activityDate", "merchant", "amountMinorUnits", "currency", "sourceLabel", "sourceTransactionID", "postingStatus", "treatment", "categoryID", "tags", "notes", "answer", "approval", "approvalEvidence", "discussionRequested", "assistantContext.question", "assistantContext.reason", "assistantContext.ledgerNotes", "classificationProvenance.category", "classificationProvenance.tags", "exceptionalEvent", "hiddenFromSummary", "refundAllocations"]
        guard schemaVersion == 1, purpose == "fintrack-history-import", amountSignConvention == Money.amountSignConvention,
              !sourceName.isEmpty, sourceName.count <= 500, !rows.isEmpty, rows.count <= BackupCapacity.maximumRecords,
              Set(rows.map(\.id)).count == rows.count, Set(rows.map(\.sourceRow)).count == rows.count,
              audit.sourceRowCount == rows.count + audit.excludedRows.count,
              Set(audit.excludedRows.map(\.sourceRow)).count == audit.excludedRows.count,
              Set(audit.excludedRows.map(\.sourceRow)).isDisjoint(with: rows.map(\.sourceRow)),
              audit.excludedRows.allSatisfy({ !$0.sourceRow.isEmpty && !$0.reason.isEmpty }),
              !audit.columns.isEmpty, audit.columns.count <= 500,
              Set(audit.columns.map(\.name)).count == audit.columns.count,
              audit.columns.allSatisfy({ !$0.name.isEmpty && !$0.name.hasPrefix("FinTrack:") && ["mapped", "preserved", "omitted"].contains($0.handling) && !$0.explanation.isEmpty
                  && ($0.handling != "mapped" || targets.contains($0.target)) }) else {
            throw ExchangeError.invalid("History counts, identities, column audit, or amount convention are invalid. Nothing was imported.")
        }
        var workspace = ReviewWorkspace()
        workspace.importedCategories = categories
        workspace.knowledge = knowledge ?? []
        let catalog = try workspace.effectiveCatalog(fallback: .prototype)
        let preserved = Set(audit.columns.filter { $0.handling == "preserved" }.map(\.name))
        var records: [LedgerTransaction] = [], sources: [String: UUID] = [:], total: Int64 = 0
        for row in rows {
            guard !row.sourceRow.isEmpty, row.sourceRow.count <= 500,
                  let cents = Int64(row.amountMinorUnits), String(cents) == row.amountMinorUnits,
                  let currency = Currency(rawValue: row.currency),
                  Set(row.preservedFields.keys) == preserved,
                  row.categoryID.map({ catalog.category(id: $0) != nil }) ?? true,
                  row.approval != .confirmed || (!row.approvalEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !row.discussionRequested) else {
                throw ExchangeError.invalid("Invalid history row \(row.sourceRow). Check exact amounts, categories, preserved columns and explicit approval evidence.")
            }
            let sum = total.addingReportingOverflow(cents)
            guard !sum.overflow else { throw MoneyError.outOfRange }; total = sum.partialValue
            var source: TransactionSource?
            if let label = row.sourceLabel {
                let id = sources[label] ?? UUID(); sources[label] = id; source = .init(id: id, label: label)
            }
            if row.sourceTransactionID != nil, source == nil { throw ExchangeError.invalid("A bank ID requires a source label.") }
            let draft = try TransactionDraft(date: TransactionDate(row.date), payee: row.merchant,
                amount: Money(minorUnits: cents, currency: currency), notes: row.notes, answer: row.answer,
                postingStatus: row.postingStatus, treatment: row.treatment, categoryID: row.categoryID, tags: row.tags,
                exceptionalEvent: row.exceptionalEvent, activityDate: row.activityDate.map { try TransactionDate($0) },
                source: source, refundAllocations: row.refundAllocations)
            let context = row.approval == .confirmed ? AssistantContext(ledgerNotes: row.assistantContext.ledgerNotes) : row.assistantContext
            let record = try LedgerTransaction(id: row.id, createdAt: at, draft: draft, approval: row.approval,
                discussionRequested: row.discussionRequested, assistantContext: context, classificationProvenance: row.classificationProvenance)
            try record.validateReviewState(catalog: catalog); records.append(record)
            if let bankID = row.sourceTransactionID, let source {
                let weekly = WeeklyTransaction(identity: .init(sourceAlias: source.label, transactionID: bankID), date: row.date,
                    activityDate: row.activityDate, merchant: row.merchant, amountMinorUnits: row.amountMinorUnits,
                    currency: row.currency, postingStatus: row.postingStatus, treatment: row.treatment, categoryID: row.categoryID, tags: row.tags)
                _ = try weekly.draft()
                workspace.sourceLinks.append(.init(identity: weekly.identity, recordID: row.id, original: weekly))
            }
            if workspace.historyDetails == nil { workspace.historyDetails = [:] }
            var details = row.preservedFields
            details["FinTrack: source row"] = row.sourceRow
            if !row.approvalEvidence.isEmpty { details["FinTrack: prior approval evidence"] = row.approvalEvidence }
            workspace.historyDetails?[row.id.uuidString] = details
            if row.hiddenFromSummary {
                if workspace.summaryVisibility == nil { workspace.summaryVisibility = .init() }
                workspace.summaryVisibility?.recordIDs.insert(row.id)
            }
        }
        guard String(total) == audit.netAmountMinorUnits else { throw ExchangeError.invalid("The history net control total does not match the exported rows.") }
        workspace.baselineEstablished = true
        workspace.historyImport = HistoryImportReceipt(id: id, digest: ContentDigest.sha256(try ExchangeJSON.encode(self)), sourceName: sourceName, recordIDs: rows.map(\.id), audit: audit, importedAt: at)
        let result = FullBackup(records: records, workspace: workspace)
        try result.validate(catalog: catalog)
        return result
    }
}

extension ReviewWorkspace {
    public func effectiveCatalog(fallback: ReviewCatalog) throws -> ReviewCatalog {
        guard let categories = importedCategories else { return fallback }
        guard !categories.isEmpty, categories.count <= 1_000,
              categories.allSatisfy({ $0.id.count <= 120 && $0.label.count <= 200 }) else { throw ReviewError.invalidCatalog }
        return try ReviewCatalog(categories: categories)
    }
    public func validateHistory(recordIDs: Set<UUID>) throws {
        for (key, fields) in historyDetails ?? [:] {
            guard let id = UUID(uuidString: key), key == id.uuidString, recordIDs.contains(id), fields.count <= 502,
                  fields.allSatisfy({ $0.key.count <= 500 && $0.value.utf8.count <= 1_000_000 }) else { throw ExchangeError.invalid("Invalid preserved history details.") }
        }
        if let receipt = historyImport {
            guard importedCategories != nil, !receipt.sourceName.isEmpty, receipt.sourceName.count <= 500,
                  !receipt.recordIDs.isEmpty, receipt.recordIDs.count <= BackupCapacity.maximumRecords,
                  receipt.digest.count == 64, receipt.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  Set(receipt.recordIDs).count == receipt.recordIDs.count, Set(receipt.recordIDs).isSubset(of: recordIDs),
                  receipt.audit.sourceRowCount == receipt.recordIDs.count + receipt.audit.excludedRows.count else {
                throw ExchangeError.invalid("Invalid history import receipt.")
            }
        }
    }
}

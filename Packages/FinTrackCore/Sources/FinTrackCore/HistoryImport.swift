import Foundation

public enum MigrationDisposition: String, Codable, CaseIterable, Sendable { case active, historical, deferredRefund, excluded }
public enum MigrationRowKind: String, Codable, Sendable { case financial, header, summary, helper, blank }
public enum ColumnTarget: String, Codable, Sendable {
    case date, activityDate, timestamp, merchant, amount, account, providerIdentity, classification, allocations, tags
    case historicalDecision, userNote, userAnswer, assistantQuestion, assistantReason, ledgerFact, mixedText
    case archival, configuration, sourceBaseline, lifecycle, visibility, exceptional, reimbursement, relationships, guidance
}
public struct HistoryColumn: Codable, Equatable, Sendable {
    public var name: String
    public var handling: String
    public var target: ColumnTarget?
    public var explanation: String
    public var essential: Bool
    public var tabs: [String]
    public init(name: String, handling: String, target: ColumnTarget?, explanation: String, essential: Bool = true, tabs: [String] = []) {
        self.name = name; self.handling = handling; self.target = target; self.explanation = explanation
        self.essential = essential; self.tabs = tabs
    }
}
public struct MigrationRow: Codable, Equatable, Sendable {
    public var locator: String
    public var kind: MigrationRowKind
    public var disposition: MigrationDisposition
    public var recordID: UUID?
    public var versionID: UUID?
    public var source: String
    public var tab: String
    public var treatment: TransactionTreatment?
    public var amount: Money?
    public var reason: String
    public init(locator: String, kind: MigrationRowKind = .financial, disposition: MigrationDisposition, recordID: UUID? = nil,
                versionID: UUID? = nil, source: String, tab: String, treatment: TransactionTreatment? = nil, amount: Money? = nil, reason: String = "") {
        self.locator = locator; self.kind = kind; self.disposition = disposition; self.recordID = recordID; self.versionID = versionID
        self.source = source; self.tab = tab; self.treatment = treatment; self.amount = amount; self.reason = reason
    }
}
public struct MigrationControl: Codable, Equatable, Sendable {
    public var group: String
    public var count: Int
    public var currency: Currency
    public var debitMinorUnits: String
    public var creditMinorUnits: String
    public var netMinorUnits: String
    public var spendingMinorUnits: String
    public var basis: String
    public init(group: String, count: Int, debitMinorUnits: String, creditMinorUnits: String, netMinorUnits: String, spendingMinorUnits: String,
                currency: Currency = .usd, basis: String = "all-source-rows-active-gross-posted") {
        self.group = group; self.count = count; self.currency = currency; self.debitMinorUnits = debitMinorUnits
        self.creditMinorUnits = creditMinorUnits; self.netMinorUnits = netMinorUnits; self.spendingMinorUnits = spendingMinorUnits; self.basis = basis
    }
    public func validate() throws {
        for text in [debitMinorUnits, creditMinorUnits, netMinorUnits, spendingMinorUnits] {
            try requireFinance(Int64(text).map { String($0) == text } == true, "Control totals need exact supported integer strings.")
        }
        try requireFinance(count >= 0 && !group.isEmpty && !basis.isEmpty && Int64(debitMinorUnits)! >= 0 && Int64(creditMinorUnits)! >= 0, "Invalid control total.")
    }
}
public struct HistoryAudit: Codable, Equatable, Sendable {
    public var sourceRowCount: Int
    public var columns: [HistoryColumn]
    public var rows: [MigrationRow]
    public var controls: [MigrationControl]
    public var warnings: [String]
    public var blockers: [String]
    public init(columns: [HistoryColumn], rows: [MigrationRow], controls: [MigrationControl], warnings: [String] = [], blockers: [String] = []) {
        sourceRowCount = rows.count; self.columns = columns; self.rows = rows; self.controls = controls; self.warnings = warnings
        self.blockers = blockers
    }
    public static func calculate(rows: [MigrationRow], records: [LedgerTransaction], includeUnreviewed: Bool = true) throws -> [MigrationControl] {
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [String: [MigrationRow]] = [:]
        for row in rows {
            for group in ["all", "source:" + row.source, "tab:" + row.tab, "treatment:" + (row.treatment?.rawValue ?? "nonfinancial"), "partition:" + row.disposition.rawValue] {
                groups[group, default: []].append(row)
            }
        }
        return try groups.keys.sorted().map { key in
            let values = groups[key]!
            var debit: Int64 = 0, credit: Int64 = 0, net: Int64 = 0, spending: Int64 = 0
            for row in values {
                guard let money = row.amount else { continue }
                if money.minorUnits >= 0 { debit = try addCents(debit, money.minorUnits) }
                else { guard let magnitude = Int64(exactly: money.minorUnits.magnitude) else { throw MoneyError.outOfRange }; credit = try addCents(credit, magnitude) }
                net = try addCents(net, money.minorUnits)
                if row.disposition == .active, let id = row.recordID, let record = byID[id], record.draft.postingStatus == .posted,
                   record.draft.treatment == .spending, includeUnreviewed || record.approval == .confirmed {
                    spending = try addCents(spending, money.minorUnits)
                }
            }
            return MigrationControl(group: key, count: values.count, debitMinorUnits: String(debit), creditMinorUnits: String(credit), netMinorUnits: String(net), spendingMinorUnits: String(spending))
        }
    }
    public func validate(records: [LedgerTransaction], reporting: ReportingConfiguration) throws {
        try requireFinance(blockers.isEmpty, "Unsupported essential source meaning blocks migration: " + blockers.joined(separator: "; "))
        try requireFinance(sourceRowCount == rows.count && !rows.isEmpty && Set(rows.map(\.locator)).count == rows.count,
            "Every source row needs one distinct accountable disposition.")
        try requireFinance(!columns.isEmpty && Set(columns.map(\.name)).count == columns.count && columns.count <= 1_000, "Every qualified source column needs one handling entry.")
        for column in columns {
            try requireFinance(!column.name.isEmpty && !column.explanation.isEmpty && ["mapped", "preserved", "omitted"].contains(column.handling), "Invalid column accounting.")
            try requireFinance(column.handling == "omitted" ? column.target == nil : column.target != nil, "Column handling requires a supported target or an explicit omission.")
            if column.handling == "preserved" { try requireFinance(column.target == .archival, "Preserved fields are archival, not live calculations.") }
            try requireFinance(!column.essential || column.handling != "omitted", "Essential source column cannot be omitted: " + column.name)
        }
        try requireFinance(Set(records.map(\.id)).count == records.count, "Duplicate imported record IDs.")
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let deferredIDs = rows.filter { $0.disposition == .deferredRefund }.compactMap(\.recordID)
        let historicalKeys = rows.filter { $0.disposition == .historical }.map { ($0.recordID?.uuidString ?? "") + ":" + ($0.versionID?.uuidString ?? "") }
        try requireFinance(Set(deferredIDs).count == deferredIDs.count && Set(historicalKeys).count == historicalKeys.count,
            "Each deferred refund and historical source version needs a distinct identity; source rows cannot collapse into one financial record.")
        var activeIDs: Set<UUID> = []
        for row in rows {
            try requireFinance(!row.locator.isEmpty && !row.source.isEmpty && !row.tab.isEmpty, "Source row locators, tabs and aliases must be explicit.")
            try requireFinance((row.kind == .financial) == (row.amount != nil && row.treatment != nil), "Financial rows need an amount/type; nonfinancial rows must not fabricate amounts.")
            switch row.disposition {
            case .active:
                guard let id = row.recordID, let record = byID[id] else { throw ExchangeError.invalid("Active source row has no imported record.") }
                try requireFinance(activeIDs.insert(id).inserted && row.amount == record.draft.amount && row.treatment == record.draft.treatment,
                    "Active row amounts/types must match exactly and cannot count a parent twice.")
                for column in columns where column.handling == "preserved" && (column.tabs.isEmpty || column.tabs.contains(row.tab)) {
                    try requireFinance(record.draft.archivalFields[column.name] != nil, "Preserved source field is missing: " + column.name + " at " + row.locator + ". Supply explicit absent/null/empty evidence rather than dropping it.")
                }
            case .historical:
                guard let id = row.recordID, let versionID = row.versionID, let version = byID[id]?.draft.sourceVersions.first(where: { $0.id == versionID }) else { throw ExchangeError.invalid("Historical source row needs its retained version.") }
                try requireFinance((version.successorID != nil || byID[id]?.draft.postingStatus == .superseded) && version.amount == row.amount, "Historical source facts must remain superseded, not active spending.")
            case .deferredRefund:
                try requireFinance(row.kind == .financial && row.treatment == .refund && row.amount!.minorUnits <= 0 && row.recordID != nil && byID[row.recordID!] == nil,
                    "Deferred merchant refunds are accounted separately and must not be active initial records.")
            case .excluded: try requireFinance(!row.reason.isEmpty && row.recordID == nil, "An excluded source row needs a reason and cannot masquerade as an imported record.")
            }
        }
        let required = Set(records.filter { $0.draft.postingStatus != .superseded }.map(\.id))
        let represented = Set(rows.filter { $0.disposition == .active || $0.disposition == .historical }.compactMap(\.recordID))
        try requireFinance(required.isSubset(of: activeIDs) && represented == Set(records.map(\.id)), "Every current logical record needs one active source disposition; standalone superseded records need historical evidence.")
        let expected = try Self.calculate(rows: rows, records: records, includeUnreviewed: reporting.includePostedUnreviewed)
        for control in controls { try control.validate() }
        try requireFinance(Set(controls.map(\.group)).count == controls.count && controls.sorted { $0.group < $1.group } == expected,
            "Independent row/debit/credit/net/spending/source/tab/treatment/partition controls do not reconcile. Nothing was imported.")
    }
}
public struct HistoryImportReceipt: Codable, Equatable, Sendable {
    public var id: UUID
    public var digest: String
    public var sourceName: String
    public var recordIDs: [UUID]
    public var audit: HistoryAudit
    public var importedAt: Date
}
public struct RefundImportReceipt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var digest: String
    public var migrationID: UUID
    public var locators: [String]
    public var recordIDs: [UUID]
    public var importedAt: Date
}
public struct HistoryImport: Codable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let purpose: String
    public var id: UUID
    public var amountSignConvention: String
    public var sourceName: String
    public var records: [LedgerTransaction]
    public var categories: [ReviewCategory]
    public var accounts: [AccountDefinition]
    public var programs: [BenefitProgram]
    public var claims: [ReimbursementClaim]
    public var repayments: [RepaymentAllocation]
    public var relationships: [RecordRelationship]
    public var reporting: ReportingConfiguration
    public var sourceBaselines: [SourceBaseline]
    public var knowledge: [KnowledgeRule]
    public var audit: HistoryAudit
    public init(id: UUID = UUID(), sourceName: String, records: [LedgerTransaction], categories: [ReviewCategory], audit: HistoryAudit,
                accounts: [AccountDefinition] = [], programs: [BenefitProgram] = [], claims: [ReimbursementClaim] = [], repayments: [RepaymentAllocation] = [],
                relationships: [RecordRelationship] = [], reporting: ReportingConfiguration = .init(), sourceBaselines: [SourceBaseline] = [], knowledge: [KnowledgeRule] = []) {
        schemaVersion = FinancialFormat.version; purpose = "fintrack-history-import"; self.id = id; amountSignConvention = Money.amountSignConvention
        self.sourceName = sourceName; self.records = records; self.categories = categories; self.audit = audit; self.accounts = accounts
        self.programs = programs; self.claims = claims; self.repayments = repayments; self.relationships = relationships
        self.reporting = reporting; self.sourceBaselines = sourceBaselines; self.knowledge = knowledge
    }
    public static func decode(_ data: Data) throws -> Self {
        try requireFinance(data.count <= ExchangeJSON.maximumBytes, "History file exceeds 50 MiB; no partial history was imported.")
        let value = try StrictJSON.decode(Self.self, from: data); _ = try value.snapshot(); return value
    }
    public var reviewWarnings: [String] {
        audit.warnings + audit.columns.filter { $0.handling != "mapped" }.map { $0.name + ": " + $0.handling + ". " + $0.explanation }
        + ["Deferred merchant refunds: \(audit.rows.filter { $0.disposition == .deferredRefund }.count). Purchases remain gross until the dedicated refund stage.",
           "FinTrack validates the supplied payload; source cell coverage and private control values must be independently checked by the user."]
    }
    public func snapshot(at: Date = .now) throws -> FullBackup {
        let records = try self.records.map { record in
            if record.approval == .confirmed || record.draft.questionState == .resolved {
                return try LedgerTransaction(id: record.id, revision: record.revision, createdAt: record.createdAt, updatedAt: record.updatedAt,
                    draft: record.draft.clearingResolvedAssistantText(), approval: record.approval, discussionRequested: record.discussionRequested,
                    assistantContext: .init(ledgerNotes: record.assistantContext.ledgerNotes), reviewHistory: record.reviewHistory,
                    classificationProvenance: record.classificationProvenance, discussionProgress: record.discussionProgress)
            }
            return record
        }
        try requireFinance(schemaVersion == FinancialFormat.version && purpose == "fintrack-history-import" && amountSignConvention == Money.amountSignConvention,
            "Unsupported history format. Use the current financial-framework contract.")
        try requireFinance(!sourceName.isEmpty && !records.isEmpty && records.allSatisfy { $0.draft.treatment != .refund }, "Initial history contains gross non-refund records only.")
        var workspace = ReviewWorkspace(); workspace.importedCategories = categories; workspace.accounts = accounts
        workspace.programs = programs; workspace.claims = claims; workspace.repayments = repayments; workspace.relationships = relationships
        workspace.reporting = reporting; workspace.sourceBaselines = sourceBaselines; workspace.knowledge = knowledge; workspace.baselineEstablished = true
        for record in records {
            try workspace.retainSourceEvidence(for: record)
            if record.draft.reportedVisibility.kind == .boolean && record.draft.reportedVisibility.boolean == true {
                if workspace.summaryVisibility == nil { workspace.summaryVisibility = .init() }; workspace.summaryVisibility?.recordIDs.insert(record.id)
            }
        }
        try audit.validate(records: records, reporting: reporting)
        workspace.historyImport = .init(id: id, digest: ContentDigest.sha256(try ExchangeJSON.encode(self)), sourceName: sourceName, recordIDs: records.map(\.id), audit: audit, importedAt: at)
        let snapshot = FullBackup(records: records, workspace: workspace); try snapshot.validate(catalog: .prototype); return snapshot
    }
}
public struct RefundImport: Codable, Sendable, Identifiable {
    public let schemaVersion: Int
    public let purpose: String
    public var id: UUID
    public var migrationID: UUID
    public var records: [LedgerTransaction]
    public var locators: [String]
    public var purchaseRevisions: [String: String]
    public init(id: UUID = UUID(), migrationID: UUID, records: [LedgerTransaction], locators: [String], purchaseRevisions: [String: String]) {
        schemaVersion = FinancialFormat.version; purpose = "fintrack-refund-import"; self.id = id; self.migrationID = migrationID
        self.records = records; self.locators = locators; self.purchaseRevisions = purchaseRevisions
    }
    public func applying(to snapshot: FullBackup, at: Date = .now) throws -> FullBackup {
        try requireFinance(schemaVersion == FinancialFormat.version && purpose == "fintrack-refund-import", "Unsupported dedicated refund format.")
        let digest = ContentDigest.sha256(try ExchangeJSON.encode(self))
        if let receipt = snapshot.workspace.refundImports.first(where: { $0.id == id }) {
            try requireFinance(receipt.digest == digest, "A refund file ID was reused with changed facts. Reconcile explicitly."); return snapshot
        }
        guard let migration = snapshot.workspace.historyImport, migration.id == migrationID else { throw ExchangeError.invalid("Refund stage does not match the committed initial migration.") }
        let deferred = migration.audit.rows.filter { $0.disposition == .deferredRefund }
        try requireFinance(snapshot.workspace.refundImports.isEmpty && Set(locators).count == locators.count && Set(locators) == Set(deferred.map(\.locator)), "The refund stage must account for the complete deferred set once.")
        try requireFinance(Set(records.map(\.id)).count == records.count && Set(records.map(\.id)) == Set(deferred.compactMap(\.recordID))
            && Set(records.map(\.id)).isDisjoint(with: snapshot.records.map(\.id)), "Refund identities must match deferred rows and cannot overwrite existing records.")
        let byID = Dictionary(uniqueKeysWithValues: snapshot.records.map { ($0.id, $0) })
        let referenced = Set(records.flatMap { ($0.draft.refundAllocations ?? []).map(\.purchaseID) })
        try requireFinance(Set(purchaseRevisions.keys) == Set(referenced.map(\.uuidString)), "Supply exact current purchase revisions for every refund target.")
        for id in referenced { try requireFinance(purchaseRevisions[id.uuidString] == byID[id].map { String($0.revision) }, "A purchase changed after refund preparation. Review the latest values.") }
        for record in records {
            try requireFinance(record.draft.treatment == .refund, "Dedicated refund records must be merchant refunds, not sign-guessed credits.")
            guard let row = deferred.first(where: { $0.recordID == record.id }) else { throw LedgerError.recordNotFound }
            try requireFinance(row.amount == record.draft.amount, "Deferred refund amount changed; reconcile source facts before importing.")
        }
        var workspace = snapshot.workspace
        for record in records { try workspace.retainSourceEvidence(for: record) }
        workspace.refundImports.append(.init(id: id, digest: digest, migrationID: migrationID, locators: locators, recordIDs: records.map(\.id), importedAt: at))
        let result = FullBackup(records: snapshot.records + records, workspace: workspace); try result.validate(catalog: .prototype); return result
    }
}
extension ReviewWorkspace {
    mutating func retainSourceEvidence(for record: LedgerTransaction) throws {
        try record.draft.validateEvidence()
        let versions = record.draft.sourceVersions
        let targets = Set(versions.compactMap(\.successorID))
        var next = versions.first { !targets.contains($0.id) }
        while let version = next {
            if let identity = version.identity {
                var facts = WeeklyTransaction(identity: identity, date: version.date.iso8601, activityDate: version.activityDate?.iso8601,
                    merchant: version.merchant, amountMinorUnits: String(version.amount.minorUnits), postingStatus: version.observedStatus,
                    treatment: version.treatment, categoryID: version.categoryID, tags: version.tags)
                facts.primarySubcategoryID = version.subcategoryID; facts.allocations = version.allocations
                facts.sourceReportDate = version.reportDate; facts.timestamp = version.timestamp; facts.sourceNotes = version.notes
                let successor = versions.first { $0.id == version.successorID }
                if let index = sourceLinks.firstIndex(where: { $0.identity == identity }) {
                    try requireFinance(sourceLinks[index].recordID == record.id, "One provider identity cannot identify two logical records.")
                    if sourceLinks[index].supersededDigests == nil { sourceLinks[index].supersededDigests = [] }
                    let oldDigest = ContentDigest.sha256(try ExchangeJSON.encode(sourceLinks[index].latest))
                    sourceLinks[index].supersededDigests?.insert(oldDigest)
                    sourceLinks[index].latest = facts
                    sourceLinks[index].supersededBy = successor?.identity == identity ? nil : successor?.identity
                } else {
                    var link = SourceLink(identity: identity, recordID: record.id, original: facts)
                    link.supersededBy = successor?.identity == identity ? nil : successor?.identity; sourceLinks.append(link)
                }
            }
            next = versions.first { $0.id == version.successorID }
        }
    }
    public func effectiveCatalog(fallback: ReviewCatalog) throws -> ReviewCatalog {
        guard let values = importedCategories else { return fallback }
        try requireFinance(!values.isEmpty && values.count <= 1_000, "Invalid current category catalog.")
        return try ReviewCatalog(categories: values)
    }
    public func validateHistory(recordIDs: Set<UUID>) throws {
        if let receipt = historyImport {
            try requireFinance(receipt.digest.count == 64 && Set(receipt.recordIDs).count == receipt.recordIDs.count && Set(receipt.recordIDs).isSubset(of: recordIDs), "Invalid migration receipt.")
        }
        try requireFinance(Set(refundImports.map(\.id)).count == refundImports.count, "Duplicate refund receipt IDs.")
        for receipt in refundImports { try requireFinance(receipt.migrationID == historyImport?.id && Set(receipt.recordIDs).isSubset(of: recordIDs), "Invalid refund stage receipt.") }
    }
}

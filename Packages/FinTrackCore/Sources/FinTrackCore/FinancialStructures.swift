import Foundation

public enum FinancialFormat {
    public static let version = 2
    public static let storeMarker = "fintrack-financial-framework-2"
}

func requireFinance(_ condition: Bool, _ message: String) throws {
    guard condition else { throw ExchangeError.invalid(message) }
}
func addCents(_ a: Int64, _ b: Int64) throws -> Int64 {
    let result = a.addingReportingOverflow(b)
    guard !result.overflow else { throw MoneyError.outOfRange }
    return result.partialValue
}

/// Source presence is evidence, not a defaulting instruction. Numbers retain
/// their original decimal text and never pass through Double.
public struct SourceValue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case absent, unknown, null, text, number, boolean }
    public var kind: Kind
    public var text: String?
    public var boolean: Bool?
    public init(kind: Kind, text: String? = nil, boolean: Bool? = nil) {
        self.kind = kind; self.text = text; self.boolean = boolean
    }
    public static let unknown = Self(kind: .unknown)
    public static let absent = Self(kind: .absent)
    public static func string(_ text: String) -> Self { .init(kind: .text, text: text) }
    public var display: String { text ?? boolean.map { $0 ? "true" : "false" } ?? kind.rawValue }
    public func validate() throws {
        try requireFinance((text?.utf8.count ?? 0) <= 1_000_000, "Source field exceeds 1 MiB.")
        switch kind {
        case .text, .number: try requireFinance(text != nil && boolean == nil, "A source text/number needs its exact text.")
        case .boolean: try requireFinance(boolean != nil && text == nil, "A source boolean needs a boolean value.")
        default: try requireFinance(text == nil && boolean == nil, "Absent/unknown/null must not fabricate a value.")
        }
        if kind == .number { try requireFinance(text!.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil, "A source number must retain valid exact numeric text.") }
    }
}
public enum TextOwnership: String, Codable, CaseIterable, Sendable {
    case userNote, userAnswer, assistantQuestion, assistantReason, ledgerFact, mixed, unknown
}
public struct SourceText: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var ownership: TextOwnership
    public var text: String
    public var sourceColumn: String?
    public init(id: UUID = UUID(), ownership: TextOwnership, text: String, sourceColumn: String? = nil) {
        self.id = id; self.ownership = ownership; self.text = text; self.sourceColumn = sourceColumn
    }
}
public struct ArchivalField: Codable, Equatable, Sendable {
    public var value: SourceValue
    public var ownership: TextOwnership
    public init(_ value: SourceValue, ownership: TextOwnership = .unknown) { self.value = value; self.ownership = ownership }
}
public struct TimestampEvidence: Codable, Equatable, Sendable {
    public var original: String
    public var timeZone: String?
    public var precision: String?
    public init(original: String, timeZone: String? = nil, precision: String? = nil) {
        self.original = original; self.timeZone = timeZone; self.precision = precision
    }
}
public struct HistoricalDecision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var approved: Bool?
    public var origin: ValueOrigin
    public var actor: String?
    public var decidedAt: TimestampEvidence?
    public var observedAt: TimestampEvidence?
    public var evidence: String
    public init(id: UUID = UUID(), approved: Bool?, origin: ValueOrigin = .unknown, actor: String? = nil,
                decidedAt: TimestampEvidence? = nil, observedAt: TimestampEvidence? = nil, evidence: String) {
        self.id = id; self.approved = approved; self.origin = origin; self.actor = actor
        self.decidedAt = decidedAt; self.observedAt = observedAt; self.evidence = evidence
    }
}
public struct ReviewSubcategory: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var storedLabel: String
    public var definition: SourceValue
    public var unresolved: Bool
    public var excluded: Bool
    public var origin: ValueOrigin
    public init(id: String, label: String, storedLabel: String? = nil, definition: SourceValue = .unknown,
                unresolved: Bool = false, excluded: Bool = false, origin: ValueOrigin = .unknown) {
        self.id = id; self.label = label; self.storedLabel = storedLabel ?? label; self.definition = definition
        self.unresolved = unresolved; self.excluded = excluded; self.origin = origin
    }
}
public struct ExpenseAllocation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var categoryID: String
    public var subcategoryID: String?
    public var amount: Money
    public var origin: ValueOrigin
    public init(id: UUID = UUID(), categoryID: String, subcategoryID: String? = nil, amount: Money, origin: ValueOrigin = .unknown) {
        self.id = id; self.categoryID = categoryID; self.subcategoryID = subcategoryID; self.amount = amount; self.origin = origin
    }
}

/// Immutable financial observations. Transient assistant text is deliberately
/// outside these snapshots so retention cannot be defeated by lifecycle history.
public struct SourceVersion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var identity: BankIdentity?
    public var date: TransactionDate
    public var activityDate: TransactionDate?
    public var reportDate: TransactionDate?
    public var timestamp: TimestampEvidence?
    public var merchant: String
    public var amount: Money
    public var observedStatus: PostingStatus
    public var successorID: UUID?
    public var notes: [SourceText]
    public var decisions: [HistoricalDecision]
    public var treatment: TransactionTreatment
    public var categoryID: String?
    public var subcategoryID: String?
    public var allocations: [ExpenseAllocation]
    public var tags: [String]
    public init(id: UUID = UUID(), identity: BankIdentity? = nil, date: TransactionDate, activityDate: TransactionDate? = nil,
                reportDate: TransactionDate? = nil, timestamp: TimestampEvidence? = nil, merchant: String, amount: Money,
                observedStatus: PostingStatus, successorID: UUID? = nil, notes: [SourceText] = [], decisions: [HistoricalDecision] = [],
                treatment: TransactionTreatment = .unresolved, categoryID: String? = nil, subcategoryID: String? = nil,
                allocations: [ExpenseAllocation] = [], tags: [String] = []) {
        self.id = id; self.identity = identity; self.date = date; self.activityDate = activityDate; self.reportDate = reportDate
        self.timestamp = timestamp; self.merchant = merchant; self.amount = amount; self.observedStatus = observedStatus
        self.successorID = successorID; self.notes = notes; self.decisions = decisions
        self.treatment = treatment; self.categoryID = categoryID; self.subcategoryID = subcategoryID; self.allocations = allocations; self.tags = tags
    }
    public var lifecycle: PostingStatus { successorID == nil ? observedStatus : .superseded }
}
public struct AccountDefinition: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var alias: String
    public var provider: SourceValue
    public var providerAccountID: SourceValue
    public init(id: UUID = UUID(), alias: String, provider: SourceValue = .unknown, providerAccountID: SourceValue = .unknown) {
        self.id = id; self.alias = alias; self.provider = provider; self.providerAccountID = providerAccountID
    }
}
public struct RecordRelationship: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case paymentCounterpart, duplicateCandidate }
    public var id: UUID
    public var kind: Kind
    public var from: UUID
    public var to: UUID
    public var evidence: String
    public init(id: UUID = UUID(), kind: Kind, from: UUID, to: UUID, evidence: String) {
        self.id = id; self.kind = kind; self.from = from; self.to = to; self.evidence = evidence
    }
}
public struct BenefitPeriod: Codable, Equatable, Sendable {
    public enum Basis: String, Codable, CaseIterable, Sendable { case unknown, calendarYear, fixedRange, rolling }
    public var basis: Basis
    public var from: TransactionDate?
    public var through: TransactionDate?
    public var description: String?
    public init(basis: Basis = .unknown, from: TransactionDate? = nil, through: TransactionDate? = nil, description: String? = nil) {
        self.basis = basis; self.from = from; self.through = through; self.description = description
    }
}
public struct BenefitProgram: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var currency: Currency
    public var limit: Money?
    public var period: BenefitPeriod
    public var eligibilityRules: SourceValue
    public var defaults: [String: SourceValue]
    public var origin: ValueOrigin
    public init(id: UUID = UUID(), label: String, currency: Currency = .usd, limit: Money? = nil,
                period: BenefitPeriod = .init(), eligibilityRules: SourceValue = .unknown,
                defaults: [String: SourceValue] = [:], origin: ValueOrigin = .unknown) {
        self.id = id; self.label = label; self.currency = currency; self.limit = limit; self.period = period
        self.eligibilityRules = eligibilityRules; self.defaults = defaults; self.origin = origin
    }
}
public enum ReimbursementEligibility: String, Codable, CaseIterable, Sendable { case unknown, eligible, ineligible }
public enum ClaimStatus: String, Codable, CaseIterable, Sendable { case unknown, notClaimed, submitted, partial, paid, denied }
public struct ReimbursementClaim: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var expenseID: UUID
    public var programID: UUID?
    public var eligibility: ReimbursementEligibility
    public var expected: Money?
    public var status: ClaimStatus
    public var sourceReportedReceived: Money?
    public var notes: String
    public init(id: UUID = UUID(), expenseID: UUID, programID: UUID? = nil, eligibility: ReimbursementEligibility = .unknown,
                expected: Money? = nil, status: ClaimStatus = .unknown, sourceReportedReceived: Money? = nil, notes: String = "") {
        self.id = id; self.expenseID = expenseID; self.programID = programID; self.eligibility = eligibility
        self.expected = expected; self.status = status; self.sourceReportedReceived = sourceReportedReceived; self.notes = notes
    }
}
public struct RepaymentAllocation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var receiptID: UUID
    public var claimID: UUID
    public var amount: Money
    public var expenseAllocationID: UUID?
    public init(id: UUID = UUID(), receiptID: UUID, claimID: UUID, amount: Money, expenseAllocationID: UUID? = nil) {
        self.id = id; self.receiptID = receiptID; self.claimID = claimID; self.amount = amount; self.expenseAllocationID = expenseAllocationID
    }
}
public struct ReportingConfiguration: Codable, Equatable, Sendable {
    public var timeZone: String = ReportingCalendar.timeZoneIdentifier
    public var firstWeekday: Int = ReportingCalendar.firstWeekday
    public var asOf: TransactionDate?
    public var includePostedUnreviewed: Bool = true
    public var sourceRules: [String: SourceValue] = [:]
    public var coverage: [CoverageStatement] = []
    public init() {}
}
public struct CoverageStatement: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case complete, partial, unknown }
    public var source: String
    public var from: TransactionDate?
    public var through: TransactionDate?
    public var status: Status
    public var limitations: String
    public init(source: String, from: TransactionDate? = nil, through: TransactionDate? = nil, status: Status = .unknown, limitations: String = "") {
        self.source = source; self.from = from; self.through = through; self.status = status; self.limitations = limitations
    }
}
public struct SourceBaseline: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    public var basis: [String: SourceValue]
    public var controls: [MigrationControl]
    public init(id: UUID = UUID(), label: String, basis: [String: SourceValue], controls: [MigrationControl]) {
        self.id = id; self.label = label; self.basis = basis; self.controls = controls
    }
}

public enum FinancialAccounting {
    public static func validate(records: [LedgerTransaction], workspace: ReviewWorkspace, catalog: ReviewCatalog) throws {
        try requireFinance(workspace.accounts.count <= 1_000 && workspace.programs.count <= 1_000 && workspace.claims.count <= 250_000 && workspace.repayments.count <= 250_000
            && workspace.relationships.count <= 250_000 && workspace.sourceBaselines.count <= 1_000, "Financial configuration exceeds supported object counts.")
        try requireFinance(Set(records.map(\.id)).count == records.count, "Duplicate financial record IDs.")
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for record in records {
            try record.validateReviewState(catalog: catalog)
            try record.draft.validateAllocations(catalog: catalog)
            try record.draft.validateEvidence()
            for version in record.draft.sourceVersions {
                let observed = TransactionDraft(date: version.date, payee: version.merchant, amount: version.amount,
                    postingStatus: version.observedStatus, treatment: version.treatment, categoryID: version.categoryID,
                    tags: version.tags, primarySubcategoryID: version.subcategoryID, allocations: version.allocations)
                try observed.validate(); try observed.validateAllocations(catalog: catalog)
            }
        }
        try requireFinance(Set(workspace.accounts.map(\.id)).count == workspace.accounts.count && Set(workspace.accounts.map(\.alias)).count == workspace.accounts.count, "Account identities and aliases must be distinct.")
        for account in workspace.accounts {
            try requireFinance(!account.alias.isEmpty && account.alias.count <= 120, "Invalid account alias.")
            try account.provider.validate(); try account.providerAccountID.validate()
        }
        for relation in workspace.relationships {
            try requireFinance(relation.from != relation.to && byID[relation.from] != nil && byID[relation.to] != nil, "Dangling or self financial relationship.")
            if relation.kind == .paymentCounterpart {
                try requireFinance([TransactionTreatment.payment, .transfer, .statementCredit].contains(byID[relation.from]!.draft.treatment)
                    && [TransactionTreatment.payment, .transfer, .statementCredit].contains(byID[relation.to]!.draft.treatment), "A payment counterpart is not a refund link.")
            }
        }
        try requireFinance(Set(workspace.relationships.map(\.id)).count == workspace.relationships.count, "Duplicate relationship IDs.")
        try requireFinance(Set(workspace.programs.map(\.id)).count == workspace.programs.count && Set(workspace.claims.map(\.id)).count == workspace.claims.count
            && Set(workspace.repayments.map(\.id)).count == workspace.repayments.count, "Duplicate reimbursement identities.")
        let programs = Dictionary(uniqueKeysWithValues: workspace.programs.map { ($0.id, $0) })
        for program in workspace.programs {
            try requireFinance(!program.label.isEmpty && program.label.count <= 200 && program.limit.map { $0.minorUnits >= 0 && $0.currency == program.currency } ?? true, "Invalid benefit program or currency.")
            if let from = program.period.from, let through = program.period.through { try requireFinance(from <= through, "Reversed benefit period.") }
            if program.period.basis == .fixedRange { try requireFinance(program.period.from != nil && program.period.through != nil, "Fixed benefit periods need both dates.") }
            try program.eligibilityRules.validate(); for value in program.defaults.values { try value.validate() }
        }
        let claims = Dictionary(uniqueKeysWithValues: workspace.claims.map { ($0.id, $0) })
        for claim in workspace.claims {
            guard let expense = byID[claim.expenseID], expense.draft.treatment == .spending else { throw ExchangeError.invalid("A claim must reference a purchase.") }
            if let id = claim.programID { try requireFinance(programs[id]?.currency == expense.draft.amount.currency, "Missing program or mismatched currency.") }
            for value in [claim.expected, claim.sourceReportedReceived].compactMap({ $0 }) { try requireFinance(value.minorUnits >= 0 && value.currency == expense.draft.amount.currency, "Invalid claim amount/currency.") }
        }
        var used: [UUID: Int64] = [:]
        for allocation in workspace.repayments {
            guard let receipt = byID[allocation.receiptID], let claim = claims[allocation.claimID], let expense = byID[claim.expenseID] else { throw ExchangeError.invalid("Repayment allocation references missing data.") }
            try requireFinance(receipt.draft.treatment == .reimbursementReceipt && receipt.draft.postingStatus == .posted
                && allocation.amount.minorUnits > 0 && allocation.amount.currency == receipt.draft.amount.currency
                && allocation.amount.currency == expense.draft.amount.currency, "Invalid repayment receipt, status, sign or currency.")
            if let part = allocation.expenseAllocationID { try requireFinance(expense.draft.components.contains { $0.id == part }, "Repayment allocation targets a missing expense component.") }
            used[receipt.id] = try addCents(used[receipt.id] ?? 0, allocation.amount.minorUnits)
            try requireFinance(UInt64(used[receipt.id]!) <= receipt.draft.amount.minorUnits.magnitude, "A reimbursement receipt was allocated more than once.")
        }
        try requireFinance(Set(workspace.sourceBaselines.map(\.id)).count == workspace.sourceBaselines.count, "Duplicate source baseline IDs.")
        try requireFinance(workspace.reporting.timeZone == ReportingCalendar.timeZoneIdentifier && workspace.reporting.firstWeekday == 2, "Reporting uses America/New_York and Monday weeks.")
        for value in workspace.reporting.sourceRules.values { try value.validate() }
        for coverage in workspace.reporting.coverage { if let a = coverage.from, let b = coverage.through { try requireFinance(a <= b, "Reversed coverage dates.") } }
        for baseline in workspace.sourceBaselines { for value in baseline.basis.values { try value.validate() }; for control in baseline.controls { try control.validate() } }
        try RefundAccounting.validate(records: records)
    }
    public static func received(claimID: UUID, workspace: ReviewWorkspace) throws -> Money {
        Money(minorUnits: try workspace.repayments.filter { $0.claimID == claimID }.reduce(Int64(0)) { try addCents($0, $1.amount.minorUnits) })
    }
    /// Negative balances explicitly expose overpayment; unknown expected stays unknown.
    public static func outstanding(claim: ReimbursementClaim, workspace: ReviewWorkspace) throws -> Money? {
        guard let expected = claim.expected else { return nil }
        return Money(minorUnits: try addCents(expected.minorUnits, -received(claimID: claim.id, workspace: workspace).minorUnits))
    }
}

/// Financial context travels with review requests, without drafts, raw responses,
/// folder permissions or an implicit grant to modify these settings.
public struct FinancialContext: Codable, Sendable {
    public var accounts: [AccountDefinition]
    public var programs: [BenefitProgram]
    public var claims: [ReimbursementClaim]
    public var repayments: [RepaymentAllocation]
    public var relationships: [RecordRelationship]
    public var reporting: ReportingConfiguration
    public var sourceBaselines: [SourceBaseline]
    public var migrationAudit: HistoryAudit?
    public var refundReceipts: [RefundImportReceipt]
    public init(workspace: ReviewWorkspace) {
        accounts = workspace.accounts; programs = workspace.programs; claims = workspace.claims
        repayments = workspace.repayments; relationships = workspace.relationships; reporting = workspace.reporting
        sourceBaselines = workspace.sourceBaselines; migrationAudit = workspace.historyImport?.audit; refundReceipts = workspace.refundImports
    }
}

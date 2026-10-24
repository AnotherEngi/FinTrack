import Foundation
import SwiftData
import FinTrackCore

enum LedgerSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTransaction.self] }

    @Model
    final class StoredTransaction {
        @Attribute(.unique) var recordID: UUID
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date
        var dateText: String
        var payee: String
        var amountMinorUnits: Int64
        var currencyCode: String
        var notes: String
        var reviewStatusCode: String

        // Persistent fields above are frozen as the original schema.
        init(_ record: LedgerTransaction, reviewStatusCode: String = "needsReview") {
            recordID = record.id
            revision = record.revision
            createdAt = record.createdAt
            updatedAt = record.updatedAt
            dateText = record.draft.date.iso8601
            payee = record.draft.payee
            amountMinorUnits = record.draft.amount.minorUnits
            currencyCode = record.draft.amount.currency.rawValue
            notes = record.draft.notes
            self.reviewStatusCode = reviewStatusCode
        }
    }
}

enum LedgerSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [StoredTransaction.self] }

    @Model
    final class StoredTransaction {
        @Attribute(.unique) var recordID: UUID
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date
        var dateText: String
        var payee: String
        var amountMinorUnits: Int64
        var currencyCode: String
        var notes: String
        var reviewStatusCode: String
        // Optional on migration. V1 rows are interpreted conservatively until edited.
        var payload: Data?

        init(_ record: LedgerTransaction) throws {
            let encoded = try JSONEncoder().encode(record)
            recordID = record.id
            revision = record.revision
            createdAt = record.createdAt
            updatedAt = record.updatedAt
            dateText = record.draft.date.iso8601
            payee = record.draft.payee
            amountMinorUnits = record.draft.amount.minorUnits
            currencyCode = record.draft.amount.currency.rawValue
            notes = record.draft.notes
            reviewStatusCode = record.draft.legacyReviewStatus?.rawValue ?? "needsReview"
            payload = encoded
        }

        func value() throws -> LedgerTransaction {
            if let payload {
                let record = try JSONDecoder().decode(LedgerTransaction.self, from: payload)
                guard record.id == recordID, record.revision == revision,
                      record.createdAt == createdAt, record.updatedAt == updatedAt,
                      record.draft.date.iso8601 == dateText, record.draft.payee == payee,
                      record.draft.amount.minorUnits == amountMinorUnits,
                      record.draft.amount.currency.rawValue == currencyCode,
                      record.draft.notes == notes,
                      (record.draft.legacyReviewStatus?.rawValue ?? "needsReview") == reviewStatusCode else {
                    throw PersistenceError.invalidStoredValue
                }
                return record
            }
            guard let currency = Currency(rawValue: currencyCode),
                  let legacyStatus = LegacyReviewStatus(rawValue: reviewStatusCode) else {
                throw PersistenceError.invalidStoredValue
            }
            // V1 did not store treatment/category. Preserve its old flag as history,
            // keep the amount unchanged, and require explicit classification/approval.
            return try LedgerTransaction(id: recordID, revision: revision,
                createdAt: createdAt, updatedAt: updatedAt,
                draft: TransactionDraft(date: TransactionDate(dateText), payee: payee,
                    amount: Money(minorUnits: amountMinorUnits, currency: currency),
                    notes: notes, postingStatus: .unresolved, legacyReviewStatus: legacyStatus))
        }

        func apply(_ record: LedgerTransaction) throws {
            let encoded = try JSONEncoder().encode(record)
            revision = record.revision
            updatedAt = record.updatedAt
            dateText = record.draft.date.iso8601
            payee = record.draft.payee
            amountMinorUnits = record.draft.amount.minorUnits
            currencyCode = record.draft.amount.currency.rawValue
            notes = record.draft.notes
            reviewStatusCode = record.draft.legacyReviewStatus?.rawValue ?? "needsReview"
            payload = encoded
        }
    }
}

enum LedgerSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }
    // Reuse the unchanged transaction model; V2's persisted fields remain frozen.
    static var models: [any PersistentModel.Type] { [LedgerSchemaV2.StoredTransaction.self, StoredWorkspace.self] }

    @Model
    final class StoredWorkspace {
        @Attribute(.unique) var key: String
        var payload: Data
        init(_ value: ReviewWorkspace) throws {
            key = "workspace"
            payload = try JSONEncoder().encode(value)
        }
    }
}

enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self, LedgerSchemaV2.self, LedgerSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LedgerSchemaV1.self, toVersion: LedgerSchemaV2.self),
         .lightweight(fromVersion: LedgerSchemaV2.self, toVersion: LedgerSchemaV3.self)]
    }
}

public enum PersistenceError: Error, Equatable, LocalizedError {
    case invalidStoredValue
    case amountConventionMigrationRequired
    case unsupportedAmountConvention

    public var errorDescription: String? {
        switch self {
        case .invalidStoredValue:
            "A stored record has an unsupported value. The store has been preserved."
        case .amountConventionMigrationRequired:
            "This earlier prototype's amounts need an explicit conversion before opening. Your records and drafts have been preserved."
        case .unsupportedAmountConvention:
            "This store uses an unsupported amount convention. Your records and drafts have been preserved."
        }
    }
}

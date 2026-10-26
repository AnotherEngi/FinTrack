import Foundation
import SwiftData
import FinTrackCore

/// One current development schema. No frozen prototype entities or migration chain.
enum LedgerSchema {
    static var schema: Schema { Schema([StoredTransaction.self, StoredWorkspace.self]) }
    @Model final class StoredTransaction {
        @Attribute(.unique) var recordID: UUID
        var revision: Int64
        var createdAt: Date
        var updatedAt: Date
        var dateText: String
        var payee: String
        var amountMinorUnits: Int64
        var currencyCode: String
        var payload: Data
        init(_ record: LedgerTransaction) throws {
            recordID = record.id; revision = record.revision; createdAt = record.createdAt; updatedAt = record.updatedAt
            dateText = record.draft.date.iso8601; payee = record.draft.payee; amountMinorUnits = record.draft.amount.minorUnits
            currencyCode = record.draft.amount.currency.rawValue; payload = try JSONEncoder().encode(record)
        }
        func value() throws -> LedgerTransaction {
            let record = try StrictJSON.decode(LedgerTransaction.self, from: payload)
            guard record.id == recordID, record.revision == revision, record.draft.amount.minorUnits == amountMinorUnits,
                  record.draft.date.iso8601 == dateText, record.draft.amount.currency.rawValue == currencyCode else { throw PersistenceError.invalidStoredValue }
            return record
        }
        func apply(_ record: LedgerTransaction) throws {
            payload = try JSONEncoder().encode(record); revision = record.revision; createdAt = record.createdAt; updatedAt = record.updatedAt
            dateText = record.draft.date.iso8601; payee = record.draft.payee; amountMinorUnits = record.draft.amount.minorUnits; currencyCode = record.draft.amount.currency.rawValue
        }
    }
    @Model final class StoredWorkspace {
        @Attribute(.unique) var key: String
        var payload: Data
        init(_ value: ReviewWorkspace) throws { key = "workspace"; payload = try JSONEncoder().encode(value) }
    }
}
public enum PersistenceError: Error, Equatable, LocalizedError {
    case invalidStoredValue, unsupportedFormat
    public var errorDescription: String? {
        switch self {
        case .invalidStoredValue: "The stored current-format record is invalid. No data was reset."
        case .unsupportedFormat: "This database belongs to a retired development format. Explicitly create a separate empty development ledger; prototype formats are not migrated."
        }
    }
}

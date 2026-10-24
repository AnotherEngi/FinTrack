import Foundation
import FinTrackCore

typealias EditorInput = TransactionInput

struct EditorDraft: Codable, Identifiable {
    var id: UUID
    var expectedRevision: Int64?
    var createdAt: Date
    var input: EditorInput

    static func new() -> Self {
        Self(id: UUID(), createdAt: .now, input: EditorInput(dateText: dateText(.now)))
    }

    init(record: LedgerTransaction) {
        id = record.id
        expectedRevision = record.revision
        createdAt = record.createdAt
        input = EditorInput(draft: record.draft)
    }

    private init(id: UUID, expectedRevision: Int64? = nil, createdAt: Date, input: EditorInput) {
        self.id = id
        self.expectedRevision = expectedRevision
        self.createdAt = createdAt
        self.input = input
    }

    static func dateText(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
}

extension TransactionTreatment {
    var label: String {
        switch self {
        case .spending: "Spending"
        case .refund: "Merchant refund"
        case .income: "Income"
        case .payment: "Payment"
        case .statementCredit: "Statement credit"
        case .transfer: "Transfer"
        case .unresolved: "Needs treatment review"
        }
    }
}

extension PostingStatus {
    var label: String {
        switch self {
        case .posted: "Posted"
        case .pending: "Pending"
        case .unresolved: "Needs posting review"
        }
    }
}

extension ApprovalStatus {
    var label: String {
        switch self {
        case .unreviewed: "Unreviewed"
        case .confirmed: "Approved"
        case .notApplicable: "Not applicable"
        }
    }
}

extension ReviewAction {
    var label: String {
        switch self {
        case .approve: "Approve"
        case .discuss: "Discuss"
        case .reopen: "Reopen"
        case .skip: "Skip"
        case .markDiscussionInProgress: "Mark reviewing in ChatGPT"
        }
    }
}

/// Incomplete input is stored separately from validated ledger records.
@MainActor
final class DraftStore {
    private let directory: URL

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ draft: EditorDraft) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(draft).write(to: url(for: draft.id), options: .atomic)
    }

    func remove(id: UUID) throws {
        let path = url(for: id)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    func fetchAll() throws -> [EditorDraft] {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        return try files.map { try JSONDecoder().decode(EditorDraft.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func url(for id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
}

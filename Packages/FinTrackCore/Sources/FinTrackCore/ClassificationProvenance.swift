import Foundation

/// A local source identity and its label on this record. Never a bank login or
/// account number. Raw bank provenance/import mapping remains a separate concern.
public struct TransactionSource: Codable, Equatable, Sendable {
    public let id: UUID
    public let label: String

    public init(id: UUID = UUID(), label: String) {
        self.id = id
        self.label = label
    }
}

public enum ValueOrigin: String, Codable, Sendable {
    case unknown, user, assistant
}

public struct ClassificationProvenance: Codable, Equatable, Sendable {
    public let category: ValueOrigin
    public let tags: [String: ValueOrigin]

    public init(category: ValueOrigin = .unknown, tags: [String: ValueOrigin] = [:]) {
        self.category = category
        self.tags = tags
    }

    public static func manual(_ draft: TransactionDraft) -> Self {
        Self(category: draft.categoryID == nil ? .unknown : .user,
            tags: Dictionary(draft.tags.map { ($0, .user) }, uniquingKeysWith: { first, _ in first }))
    }

    func afterManualEdit(from old: TransactionDraft, to new: TransactionDraft) -> Self {
        Self(category: new.categoryID == nil ? .unknown
                : new.categoryID != old.categoryID ? .user : category,
            tags: Dictionary(uniqueKeysWithValues: new.tags.map { tag in
                (tag, old.tags.contains(tag) ? tags[tag] ?? .unknown : .user)
            }))
    }

    func validate(for draft: TransactionDraft) throws {
        guard (draft.categoryID != nil || category == .unknown),
              tags.keys.allSatisfy({ draft.tags.contains($0) }) else {
            throw ReviewError.invalidProvenance
        }
    }
}

/// Workflow status explicitly recorded by the user, never a network receipt.
public enum DiscussionProgress: String, Codable, Sendable {
    case awaitingExport, reviewingInChatGPT
}

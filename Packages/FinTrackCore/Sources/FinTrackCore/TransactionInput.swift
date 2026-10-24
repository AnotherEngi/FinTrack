import Foundation

/// Durable raw editor input. It may be incomplete and is not a review proposal.
public struct TransactionInput: Codable, Equatable, Sendable {
    public var dateText: String
    public var activityDateText: String
    public var payee: String
    public var amountText: String
    public var notes: String
    public var answer: String
    public var postingStatus: PostingStatus
    public var treatment: TransactionTreatment
    public var categoryID: String?
    public var tagsText: String
    public var exceptionalEvent: Bool
    public let legacyReviewStatus: LegacyReviewStatus?
    public var sourceLabel: String
    public let sourceID: UUID

    public init(dateText: String, activityDateText: String = "", payee: String = "",
                amountText: String = "", notes: String = "", answer: String = "",
                postingStatus: PostingStatus = .posted, treatment: TransactionTreatment = .unresolved,
                categoryID: String? = nil, tagsText: String = "", exceptionalEvent: Bool = false,
                legacyReviewStatus: LegacyReviewStatus? = nil,
                sourceLabel: String = "", sourceID: UUID = UUID()) {
        self.dateText = dateText
        self.activityDateText = activityDateText
        self.payee = payee
        self.amountText = amountText
        self.notes = notes
        self.answer = answer
        self.postingStatus = postingStatus
        self.treatment = treatment
        self.categoryID = categoryID
        self.tagsText = tagsText
        self.exceptionalEvent = exceptionalEvent
        self.legacyReviewStatus = legacyReviewStatus
        self.sourceLabel = sourceLabel
        self.sourceID = sourceID
    }

    public init(draft: TransactionDraft) {
        self.init(dateText: draft.date.iso8601, activityDateText: draft.activityDate?.iso8601 ?? "",
            payee: draft.payee, amountText: draft.amount.decimalText, notes: draft.notes,
            answer: draft.answer, postingStatus: draft.postingStatus, treatment: draft.treatment,
            categoryID: draft.categoryID, tagsText: draft.tags.joined(separator: "; "),
            exceptionalEvent: draft.exceptionalEvent, legacyReviewStatus: draft.legacyReviewStatus,
            sourceLabel: draft.source?.label ?? "", sourceID: draft.source?.id ?? UUID())
    }

    public func value() throws -> TransactionDraft {
        let tags = tagsText.split(separator: ";").map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        let activity = activityDateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = try TransactionDraft(date: TransactionDate(dateText), payee: payee,
            amount: Money(decimalText: amountText), notes: notes, answer: answer,
            postingStatus: postingStatus, treatment: treatment, categoryID: categoryID, tags: tags,
            exceptionalEvent: exceptionalEvent, activityDate: activity.isEmpty ? nil : TransactionDate(activity),
            legacyReviewStatus: legacyReviewStatus,
            source: sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                : TransactionSource(id: sourceID, label: sourceLabel.trimmingCharacters(in: .whitespacesAndNewlines)))
        try draft.validate()
        return draft
    }

    private enum CodingKeys: String, CodingKey {
        case dateText, activityDateText, payee, amountText, notes, answer, postingStatus
        case treatment, categoryID, tagsText, exceptionalEvent, legacyReviewStatus, sourceLabel, sourceID
    }
    private enum LegacyKeys: String, CodingKey { case reviewStatus }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let old = try decoder.container(keyedBy: LegacyKeys.self)
        try self.init(dateText: values.decode(String.self, forKey: .dateText),
            activityDateText: values.decodeIfPresent(String.self, forKey: .activityDateText) ?? "",
            payee: values.decode(String.self, forKey: .payee),
            amountText: values.decode(String.self, forKey: .amountText),
            notes: values.decodeIfPresent(String.self, forKey: .notes) ?? "",
            answer: values.decodeIfPresent(String.self, forKey: .answer) ?? "",
            postingStatus: values.decodeIfPresent(PostingStatus.self, forKey: .postingStatus) ?? .unresolved,
            treatment: values.decodeIfPresent(TransactionTreatment.self, forKey: .treatment) ?? .unresolved,
            categoryID: values.decodeIfPresent(String.self, forKey: .categoryID),
            tagsText: values.decodeIfPresent(String.self, forKey: .tagsText) ?? "",
            exceptionalEvent: values.decodeIfPresent(Bool.self, forKey: .exceptionalEvent) ?? false,
            legacyReviewStatus: values.decodeIfPresent(LegacyReviewStatus.self, forKey: .legacyReviewStatus)
                ?? old.decodeIfPresent(LegacyReviewStatus.self, forKey: .reviewStatus),
            sourceLabel: values.decodeIfPresent(String.self, forKey: .sourceLabel) ?? "",
            sourceID: values.decodeIfPresent(UUID.self, forKey: .sourceID) ?? UUID())
    }
}

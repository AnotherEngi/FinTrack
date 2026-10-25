import Foundation

public struct DiscussionAnswer: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let expectedRevision: String
    public let text: String
    public let questionForUser: String?
    public init(id: UUID = UUID(), recordID: UUID, expectedRevision: String, text: String, questionForUser: String? = nil) {
        self.id = id; self.recordID = recordID; self.expectedRevision = expectedRevision
        self.text = text; self.questionForUser = questionForUser
    }
}

public struct UserDiscussionReply: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let recordID: UUID
    public let sentRevision: String
    public let text: String
    public let respondingTo: UUID?
    public init(recordID: UUID, sentRevision: String, text: String, respondingTo: UUID? = nil) {
        id = UUID(); self.recordID = recordID; self.sentRevision = sentRevision; self.text = text
        self.respondingTo = respondingTo
    }
}

public struct DiscussionDraft: Codable, Equatable, Sendable {
    public let recordID: UUID
    public let expectedRevision: String
    public let text: String
    public init(recordID: UUID, expectedRevision: String, text: String) {
        self.recordID = recordID; self.expectedRevision = expectedRevision; self.text = text
    }
}

public struct DiscussionBoundary: Codable, Equatable, Sendable {
    public let question: String
    public let notes: String
    public let answer: String
    public let lastRequestID: UUID?
    public let answerIDs: [UUID]
    public let replyIDs: [UUID]
    public init(record: LedgerTransaction, answers: [DiscussionAnswer], replies: [UserDiscussionReply]) {
        question = record.assistantContext.question; notes = record.draft.notes; answer = record.draft.answer
        lastRequestID = record.reviewHistory.last(where: { $0.request.action == .discuss })?.id
        answerIDs = answers.map(\.id); replyIDs = replies.map(\.id)
    }
}

public enum DiscussionStatus: String, Codable, Sendable {
    case draft, awaitingYou, readyToSend, waitingForChatGPT, responseReceived, resolved
}

public struct DiscussionThread: Codable, Identifiable, Sendable {
    public var id: UUID { recordID }
    public let recordID: UUID
    public let originalQuestion: String
    public let userQuestion: String
    public let answers: [DiscussionAnswer]
    public let replies: [UserDiscussionReply]
    public let isResolved: Bool
    public let status: DiscussionStatus
    public var questionForUser: String? { answers.last?.questionForUser ?? (originalQuestion.isEmpty ? nil : originalQuestion) }
}

extension ClassificationProposal {
    public func changesClassification(of record: LedgerTransaction) -> Bool {
        if let categoryID, categoryID != record.draft.categoryID { return true }
        if let tags, Set(tags) != Set(record.draft.tags) { return true }
        return false
    }
}

extension ReviewWorkspace {
    /// Importing records receipt of a validated response, never acceptance of its
    /// edits. Unacknowledged operations and all later edits remain pending.
    public mutating func receive(_ data: Data) throws {
        try stage(data)
        if let response = try? ExchangeJSON.decode(ReviewResponse.self, from: data),
           response.purpose == "fintrack-review-response" { try acknowledge(response) }
    }

    public func discussion(for record: LedgerTransaction) -> DiscussionThread? {
        discussion(for: record, responses: discussionResponses)
    }

    public func discussions(in records: [LedgerTransaction]) -> [DiscussionThread] {
        let responses = discussionResponses
        return records.compactMap { discussion(for: $0, responses: responses) }
    }

    private var discussionResponses: [ReviewResponse] {
        staged.filter { $0.purpose == "fintrack-review-response" }.compactMap {
            try? ExchangeJSON.decode(ReviewResponse.self, from: $0.data)
        }
    }

    private func discussion(for record: LedgerTransaction, responses: [ReviewResponse]) -> DiscussionThread? {
        var answers: [DiscussionAnswer] = []
        for response in responses {
            answers.append(contentsOf: response.answers.filter { $0.recordID == record.id })
            // Compatibility: older exports had no answer channel, so explanations
            // and follow-up questions were incorrectly wrapped as proposals.
            for proposal in response.proposals where proposal.recordID == record.id {
                let manifest = manifests.first { $0.id == response.packetID }
                let sentRevision = Int64(proposal.expectedRevision) ?? 0
                let intent = record.reviewHistory.last { $0.appliedRevision <= sentRevision
                    && ($0.request.action == .discuss || $0.request.action == .resolveDiscussion) }
                let legacyRequested = intent.map { $0.request.action == .discuss }
                    ?? (record.discussionRequested || !record.assistantContext.question.isEmpty
                        || record.reviewHistory.contains { $0.request.action == .resolveDiscussion && $0.appliedRevision > sentRevision })
                let sentForDiscussion = manifest?.discussionRecordIDs?.contains(record.id) ?? legacyRequested
                let isDiscussion = (proposal.categoryID == nil && proposal.tags == nil)
                    || proposal.question?.isEmpty == false || sentForDiscussion
                if isDiscussion {
                    answers.append(DiscussionAnswer(id: proposal.id, recordID: record.id,
                        expectedRevision: proposal.expectedRevision, text: proposal.rationale, questionForUser: proposal.question))
                }
            }
        }
        // A late reply to an older packet remains readable without replacing
        // the current question/direction. Retain import order for equal revisions.
        var ordered: [(offset: Int, value: DiscussionAnswer)] = []
        for (offset, value) in answers.enumerated() { ordered.append((offset, value)) }
        ordered.sort { left, right in
            let a = Int64(left.value.expectedRevision) ?? 0
            let b = Int64(right.value.expectedRevision) ?? 0
            return a == b ? left.offset < right.offset : a < b
        }
        answers = ordered.map { $0.value }
        let replies = (discussionReplies ?? []).filter { $0.recordID == record.id }
        let question = record.assistantContext.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasHistory = record.reviewHistory.contains { $0.request.action == .discuss || $0.request.action == .resolveDiscussion }
        let hasDraft = discussionDrafts?[record.id.uuidString] != nil
        guard record.discussionRequested || !question.isEmpty || !answers.isEmpty || !replies.isEmpty
            || hasHistory || hasDraft || resolvedDiscussions?[record.id.uuidString] != nil else { return nil }
        let boundary = DiscussionBoundary(record: record, answers: answers, replies: replies)
        let resolved = resolvedDiscussions?[record.id.uuidString] == boundary
        let latestAnswerRevision = answers.compactMap { Int64($0.expectedRevision) }.max() ?? 0
        let latestReplyRevision = replies.compactMap { Int64($0.sentRevision) }.max() ?? 0
        let needsUser = answers.last?.questionForUser?.isEmpty == false
            ? (replies.last?.respondingTo != answers.last?.id && latestReplyRevision <= latestAnswerRevision)
            : (!question.isEmpty && record.draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && answers.isEmpty)
        let ready = pending.contains { event in event.recordID == record.id && event.kind != "resolveDiscussion" }
        let status: DiscussionStatus
        if hasDraft { status = .draft }
        else if resolved { status = .resolved }
        else if needsUser { status = .awaitingYou }
        else if ready { status = .readyToSend }
        else if !answers.isEmpty { status = .responseReceived }
        else { status = .waitingForChatGPT }
        let userAsked = record.discussionRequested || record.reviewHistory.contains { $0.request.action == .discuss }
        return DiscussionThread(recordID: record.id, originalQuestion: question, userQuestion: userAsked ? record.draft.notes : "",
            answers: answers, replies: replies, isResolved: resolved, status: status)
    }

    public mutating func resolveDiscussion(for record: LedgerTransaction) {
        guard let thread = discussion(for: record) else { return }
        if resolvedDiscussions == nil { resolvedDiscussions = [:] }
        resolvedDiscussions?[record.id.uuidString] = DiscussionBoundary(record: record, answers: thread.answers, replies: thread.replies)
    }
}

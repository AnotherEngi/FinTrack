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

private struct DiscussionSlice {
    let packetID: UUID
    let proposals: [ClassificationProposal]
    let answers: [DiscussionAnswer]
}

extension ClassificationProposal {
    public func changesClassification(of record: LedgerTransaction) -> Bool {
        if let categoryID, categoryID != record.draft.categoryID { return true }
        if let tags, Set(tags) != Set(record.draft.tags) { return true }
        if let primarySubcategoryID, primarySubcategoryID != (record.draft.primarySubcategoryID ?? "") { return true }
        if let allocations, allocations != record.draft.allocations { return true }
        return false
    }
}

extension ReviewWorkspace {
    /// Importing records receipt of a validated response, never acceptance of its
    /// edits. Unacknowledged operations and all later edits remain pending.
    public mutating func receive(_ data: Data) throws {
        try stage(data)
        struct Header: Decodable { let id: UUID }
        let header = try ExchangeJSON.decode(Header.self, from: data)
        if importReceipts?.contains(where: { $0.id == header.id }) == true { return }
        if let response = try? ExchangeJSON.decode(ReviewResponse.self, from: data),
           response.purpose == "fintrack-review-response" { try acknowledge(response) }
    }

    public func discussion(for record: LedgerTransaction) -> DiscussionThread? {
        discussion(for: record, responses: discussionSlices()[record.id] ?? [],
            cachedAnswers: (discussionAnswers ?? []).filter { $0.recordID == record.id },
            replies: (discussionReplies ?? []).filter { $0.recordID == record.id },
            ready: pending.contains { $0.recordID == record.id && $0.kind != "resolveDiscussion" })
    }

    public func discussions(in records: [LedgerTransaction]) -> [DiscussionThread] {
        let responses = discussionSlices()
        let answers = Dictionary(grouping: discussionAnswers ?? [], by: \.recordID)
        let replies = Dictionary(grouping: discussionReplies ?? [], by: \.recordID)
        let ready = Set(pending.filter { $0.kind != "resolveDiscussion" }.compactMap(\.recordID))
        return records.compactMap { record in
            discussion(for: record, responses: responses[record.id] ?? [], cachedAnswers: answers[record.id] ?? [],
                replies: replies[record.id] ?? [], ready: ready.contains(record.id))
        }
    }

    private var discussionResponses: [ReviewResponse] {
        staged.filter { $0.purpose == "fintrack-review-response" }.compactMap {
            try? ExchangeJSON.decode(ReviewResponse.self, from: $0.data)
        }
    }

    private func discussionSlices() -> [UUID: [DiscussionSlice]] {
        var result: [UUID: [DiscussionSlice]] = [:]
        for response in discussionResponses {
            let proposals = Dictionary(grouping: response.proposals, by: \.recordID)
            let answers = Dictionary(grouping: response.answers, by: \.recordID)
            for id in Set(proposals.keys).union(answers.keys) {
                result[id, default: []].append(DiscussionSlice(packetID: response.packetID,
                    proposals: proposals[id] ?? [], answers: answers[id] ?? []))
            }
        }
        return result
    }

    private func discussion(for record: LedgerTransaction, responses: [DiscussionSlice], cachedAnswers: [DiscussionAnswer],
                            replies: [UserDiscussionReply], ready: Bool) -> DiscussionThread? {
        var answers = cachedAnswers
        for response in responses {
            answers.append(contentsOf: response.answers.filter { $0.recordID == record.id })
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
        var seen: Set<UUID> = []
        answers = answers.filter { seen.insert($0.id).inserted }
        let lastRequest = record.reviewHistory.last { $0.request.action == .discuss }?.appliedRevision ?? 0
        let closedRevision = discussionClosureRevision(for: record)
        if closedRevision > 0, lastRequest > closedRevision {
            answers.removeAll { (Int64($0.expectedRevision) ?? 0) <= closedRevision }
        }
        let closed = isDiscussionClosed(for: record) && !answers.contains { (Int64($0.expectedRevision) ?? 0) > closedRevision }
        if closed { answers = [] }
        let supplied = ([record.assistantContext.question] + record.draft.sourceNotes.filter { $0.ownership == .assistantQuestion }.map(\.text))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        let fallback = [.open, .unknown].contains(record.draft.questionState) ? "The source marks a question as open or unknown. Review this transaction and clarify or resolve it." : ""
        let question = closed ? "" : (supplied.isEmpty ? fallback : supplied)
        let hasHistory = record.reviewHistory.contains { $0.request.action == .discuss || $0.request.action == .resolveDiscussion }
        let hasDraft = discussionDrafts?[record.id.uuidString] != nil
        guard record.discussionRequested || !question.isEmpty || !answers.isEmpty || !replies.isEmpty
            || hasHistory || hasDraft
            || discussionClosedRevisions?[record.id.uuidString] != nil else { return nil }
        let resolved = !hasDraft && closed
        let latestAnswerRevision = answers.compactMap { Int64($0.expectedRevision) }.max() ?? 0
        let latestReplyRevision = replies.compactMap { Int64($0.sentRevision) }.max() ?? 0
        let needsUser = answers.last?.questionForUser?.isEmpty == false
            ? (replies.last?.respondingTo != answers.last?.id && latestReplyRevision <= latestAnswerRevision)
            : (!question.isEmpty && record.draft.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && answers.isEmpty)
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
        closeDiscussion(for: record)
    }
}

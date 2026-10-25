import Foundation
import Testing
@testable import FinTrackCore

@Test func failedPreparationLeavesBaselineFeedbackAndManifestsUnchanged() throws {
    var workspace = ReviewWorkspace()
    let before = try ExchangeJSON.encode(workspace)
    #expect(throws: (any Error).self) { try workspace.prepare(records: [], catalog: .prototype, mode: .pending) }
    #expect(try ExchangeJSON.encode(workspace) == before)
    let record = try SyntheticTransactions.make()[0]
    #expect(throws: (any Error).self) {
        try workspace.prepare(records: [record, record], catalog: .prototype, mode: .fullHistory)
    }
    #expect(try ExchangeJSON.encode(workspace) == before)
}

@Test func explanationAndUnchangedClassificationCannotBeAppliedAsRecordEdits() throws {
    let record = try SyntheticTransactions.make()[0]
    let explanation = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        question: "Fictional follow-up?", rationale: "A fictional explanation only")
    #expect(throws: (any Error).self) { try record.applyingSuggestion(explanation, catalog: .prototype) }
    let unchanged = ClassificationProposal(recordID: record.id, expectedRevision: String(record.revision),
        categoryID: record.draft.categoryID, tags: Array(record.draft.tags.reversed()), rationale: "Unchanged values")
    #expect(throws: (any Error).self) { try record.applyingSuggestion(unchanged, catalog: .prototype) }
    #expect(record.revision == 1)
    #expect(record.assistantContext.question != explanation.question)
}

@Test func backupRejectsDiscussionRepliesAndDraftsFromFutureRevisions() throws {
    let record = try SyntheticTransactions.make()[0]
    let future = String(record.revision + 1)
    var workspace = ReviewWorkspace()
    workspace.discussionReplies = [UserDiscussionReply(recordID: record.id, sentRevision: future, text: "Fictional future reply")]
    #expect(throws: (any Error).self) { try FullBackup(records: [record], workspace: workspace).validate(catalog: .prototype) }
    workspace.discussionReplies = nil
    workspace.discussionDrafts = [record.id.uuidString: DiscussionDraft(recordID: record.id, expectedRevision: future, text: "Fictional future draft")]
    #expect(throws: (any Error).self) { try FullBackup(records: [record], workspace: workspace).validate(catalog: .prototype) }
}

@Test func backupPreservesValidStaleReplyDraftsInsteadOfSilentlyRebasingThem() throws {
    let original = try SyntheticTransactions.make()[0]
    var draft = original.draft; draft.notes = "Fictional later note"
    let newer = try original.revising(with: draft, expectedRevision: original.revision)
    var workspace = ReviewWorkspace()
    workspace.discussionDrafts = [original.id.uuidString: DiscussionDraft(recordID: original.id,
        expectedRevision: String(original.revision), text: "Fictional older draft")]
    let archive = FullBackup(records: [newer], workspace: workspace)
    try archive.validate(catalog: .prototype)
    let restored = try ExchangeJSON.decode(FullBackup.self, from: ExchangeJSON.encode(archive))
    #expect(restored.workspace.discussionDrafts?[original.id.uuidString]?.expectedRevision == String(original.revision))
}

@Test func backupRejectsDiscussionScopeOutsideItsPacket() throws {
    let record = try SyntheticTransactions.make()[0]
    var workspace = ReviewWorkspace()
    _ = try workspace.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    var json = try #require(JSONSerialization.jsonObject(with: ExchangeJSON.encode(workspace)) as? [String: Any])
    var manifests = try #require(json["manifests"] as? [[String: Any]])
    manifests[0]["discussionRecordIDs"] = [UUID().uuidString]
    json["manifests"] = manifests
    let invalid = try ExchangeJSON.decode(ReviewWorkspace.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(throws: (any Error).self) { try FullBackup(records: [record], workspace: invalid).validate(catalog: .prototype) }
}

@Test func lateOldReplyCannotReplaceTheNewestOutstandingQuestion() throws {
    let original = try SyntheticTransactions.make()[0]
    var workspace = ReviewWorkspace()
    let first = try workspace.prepare(records: [original], catalog: .prototype, mode: .pending)
    var draft = original.draft; draft.notes = "Fictional newer context"
    let newer = try original.revising(with: draft, expectedRevision: original.revision)
    workspace.recordUserChange(before: original, after: newer)
    let second = try workspace.prepare(records: [newer], catalog: .prototype, mode: .pending)
    let freshAnswer = DiscussionAnswer(recordID: newer.id, expectedRevision: String(newer.revision),
        text: "Fresh fictional response", questionForUser: "Newest fictional question?")
    let fresh = ReviewResponse(packetID: second.manifest.id, knowledgeVersion: second.manifest.knowledgeVersion,
        acknowledgedOperationIDs: second.manifest.operationIDs, answers: [freshAnswer])
    try workspace.receive(ExchangeJSON.encode(fresh))
    let lateAnswer = DiscussionAnswer(recordID: original.id, expectedRevision: String(original.revision),
        text: "Late fictional response", questionForUser: "Outdated fictional question?")
    let late = ReviewResponse(packetID: first.manifest.id, knowledgeVersion: first.manifest.knowledgeVersion,
        acknowledgedOperationIDs: first.manifest.operationIDs, answers: [lateAnswer])
    try workspace.receive(ExchangeJSON.encode(late))
    #expect(workspace.discussion(for: newer)?.questionForUser == freshAnswer.questionForUser)
    #expect(workspace.discussion(for: newer)?.status == .awaitingYou)
    #expect(workspace.pending.isEmpty)
}

import Foundation

public struct ImportReceipt: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let purpose: String
    public let digest: String
    public let packetID: UUID?
    public let itemIDs: [UUID]
    public let compactedAt: Date
    public let disposition: String?
    public let decisionIDs: [UUID]?
    public let reportedCoverage: String?
    public let rowCount: Int?
    /// Display once, then clear; this is not permanent receipt history.
    public var unreadSummary: String?
    public init(file: StagedFile, response: ReviewResponse? = nil, disposition: String = "processed", decisionIDs: [UUID] = [],
                reportedCoverage: String? = nil, rowCount: Int? = nil, at: Date = .now) {
        id = file.id; purpose = file.purpose; digest = ContentDigest.sha256(file.data)
        packetID = response?.packetID
        itemIDs = response.map { $0.proposals.map(\.id) + $0.knowledgeProposals.map(\.id) + $0.answers.map(\.id) } ?? []
        compactedAt = at
        self.disposition = disposition
        self.decisionIDs = decisionIDs
        self.reportedCoverage = reportedCoverage; self.rowCount = rowCount
        unreadSummary = response.flatMap { $0.summary.isEmpty ? nil : $0.summary }
    }
}

extension ReviewWorkspace {
    public func discussionClosureRevision(for record: LedgerTransaction) -> Int64 {
        let saved = Int64(discussionClosedRevisions?[record.id.uuidString] ?? "0") ?? 0
        let action = record.reviewHistory.last { $0.request.action == .approve || $0.request.action == .resolveDiscussion }?.appliedRevision ?? 0
        return max(max(saved, action), record.approval == .confirmed && !record.discussionRequested ? record.revision : 0)
    }
    public func isDiscussionClosed(for record: LedgerTransaction) -> Bool {
        let closed = discussionClosureRevision(for: record)
        let request = record.reviewHistory.last { $0.request.action == .discuss }?.appliedRevision ?? 0
        return closed > 0 && request <= closed
    }

    public mutating func closeDiscussion(for record: LedgerTransaction) {
        if discussionClosedRevisions == nil { discussionClosedRevisions = [:] }
        discussionClosedRevisions?[record.id.uuidString] = String(record.revision)
        resolvedDiscussions?.removeValue(forKey: record.id.uuidString)
    }

    /// No age-based deletion of unfinished financial work. Completed files are
    /// replaced by content fingerprints; active discussion answers survive outside
    /// raw response JSON only until their discussion is closed.
    public mutating func compactCompletedExchanges(records: [LedgerTransaction], at: Date = .now) throws {
        guard Set(records.map(\.id)).count == records.count,
              Set(sourceLinks.map(\.identity)).count == sourceLinks.count else {
            throw ExchangeError.invalid("Duplicate record/source identities in the retained workspace.")
        }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let latestSources = Dictionary(uniqueKeysWithValues: sourceLinks.map { ($0.identity, $0.latest) })
        var decisions = Set(decidedProposals)
        let originalReceiptCount = importReceipts?.count ?? 0
        var responsePackets: [UUID: UUID] = [:]
        let threads = discussions(in: records)
        for thread in threads where thread.isResolved && resolvedDiscussions?[thread.recordID.uuidString] != nil {
            if let record = byID[thread.recordID] { closeDiscussion(for: record) }
        }
        let retainedAnswers = threads.filter { !$0.isResolved }.flatMap(\.answers)
        if !retainedAnswers.isEmpty || discussionAnswers != nil { discussionAnswers = retainedAnswers }
        let retainedReplies = (discussionReplies ?? []).filter { reply in
            guard let record = byID[reply.recordID] else { return false }
            return !isDiscussionClosed(for: record) || pending.contains {
                $0.recordID == reply.recordID && $0.kind == "discussion-reply" && $0.afterRevision == reply.sentRevision
            }
        }
        if !retainedReplies.isEmpty || discussionReplies != nil { discussionReplies = retainedReplies }
        var finished: [UUID] = []
        for file in staged {
            if file.purpose == "fintrack-review-response" {
                let response = try ExchangeJSON.decode(ReviewResponse.self, from: file.data)
                responsePackets[file.id] = response.packetID
                guard processedFiles.contains(response.id) else { continue }
                // Approval settles older classification questions, never guidance
                // proposals or a newer discussion opened after that approval.
                for proposal in response.proposals {
                    guard let record = byID[proposal.recordID], isDiscussionClosed(for: record),
                          let revision = Int64(proposal.expectedRevision),
                          revision < discussionClosureRevision(for: record) else { continue }
                    if decisions.insert(proposal.id).inserted { decidedProposals.append(proposal.id) }
                }
                let changes = response.proposals.filter { proposal in
                    guard let record = byID[proposal.recordID] else { return true }
                    return proposal.changesClassification(of: record) || decisions.contains(proposal.id)
                }
                guard (changes.map(\.id) + response.knowledgeProposals.map(\.id)).allSatisfy({ decisions.contains($0) }) else { continue }
                if importReceipts == nil { importReceipts = [] }
                let settled = (response.proposals.map(\.id) + response.knowledgeProposals.map(\.id)).filter { decisions.contains($0) }
                importReceipts?.append(ImportReceipt(file: file, response: response, decisionIDs: settled, at: at))
                finished.append(file.id)
            } else if file.purpose == "fintrack-weekly-intake" {
                let batch = try ExchangeJSON.decode(WeeklyBatch.self, from: file.data)
                let incorporated = batch.transactions.allSatisfy { latestSources[$0.identity] == $0 }
                if incorporated {
                    if importReceipts == nil { importReceipts = [] }
                    importReceipts?.append(ImportReceipt(file: file, reportedCoverage: batch.coverage, rowCount: batch.transactions.count, at: at)); finished.append(file.id)
                }
            }
        }
        let removed = Set(finished)
        staged.removeAll { removed.contains($0.id) }
        processedFiles.removeAll { removed.contains($0) }
        let retiredItems = Set((importReceipts ?? []).dropFirst(originalReceiptCount).flatMap(\.itemIDs))
        decidedProposals.removeAll { retiredItems.contains($0) }
        let activePackets = Set(responsePackets.filter { !removed.contains($0.key) }.values)
        let completedPackets = Set((importReceipts ?? []).compactMap(\.packetID))
        let pendingIDs = Set(pending.map(\.id))
        let retire = manifests.filter { manifest in
            !activePackets.contains(manifest.id) &&
                ((completedPackets.contains(manifest.id) && Set(manifest.operationIDs).isDisjoint(with: pendingIDs))
                    || at.timeIntervalSince(manifest.createdAt) >= 90 * 24 * 60 * 60)
        }
        if !retire.isEmpty {
            if retiredPacketIDs == nil { retiredPacketIDs = [] }
            retiredPacketIDs?.formUnion(retire.map(\.id))
            let retired = Set(retire.map(\.id)); manifests.removeAll { retired.contains($0.id) }
        }
    }

    public mutating func dismissIncoming(fileID: UUID, records: [LedgerTransaction], at: Date = .now) throws {
        if importReceipts?.contains(where: { $0.id == fileID }) == true { return }
        guard let file = staged.first(where: { $0.id == fileID }) else { throw ExchangeError.invalid("Incoming file not found.") }
        discussionAnswers = discussions(in: records).filter { !$0.isResolved }.flatMap(\.answers)
        let response = file.purpose == "fintrack-review-response" ? try ExchangeJSON.decode(ReviewResponse.self, from: file.data) : nil
        let weekly = file.purpose == "fintrack-weekly-intake" ? try ExchangeJSON.decode(WeeklyBatch.self, from: file.data) : nil
        let decisions = response.map { $0.proposals.filter { $0.categoryID != nil || $0.tags != nil }.map(\.id) + $0.knowledgeProposals.map(\.id) } ?? []
        let receipt = ImportReceipt(file: file, response: response, disposition: "dismissed", decisionIDs: decisions,
            reportedCoverage: weekly?.coverage, rowCount: weekly?.transactions.count, at: at)
        if importReceipts == nil { importReceipts = [] }; importReceipts?.append(receipt)
        staged.removeAll { $0.id == fileID }; processedFiles.removeAll { $0 == fileID }
        let ids = Set(receipt.itemIDs); decidedProposals.removeAll { ids.contains($0) }
        // Dismissing a file is not acknowledgement of the user's outstanding work.
        try compactCompletedExchanges(records: records, at: at)
    }

    public func validateRetention(records: [LedgerTransaction]) throws {
        guard Set(records.map(\.id)).count == records.count else { throw LedgerError.duplicateID }
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        let receipts = importReceipts ?? []
        guard Set(receipts.map(\.id)).count == receipts.count,
              Set(receipts.map(\.id)).isDisjoint(with: Set(staged.map(\.id))),
              (retiredPacketIDs ?? []).isDisjoint(with: Set(manifests.map(\.id))) else {
            throw ExchangeError.invalid("Invalid retained import/packet identities.")
        }
        var itemIDs: Set<UUID> = []
        for receipt in receipts {
            guard ["fintrack-review-response", "fintrack-weekly-intake"].contains(receipt.purpose),
                  receipt.disposition == nil || ["processed", "dismissed"].contains(receipt.disposition!),
                  (receipt.reportedCoverage?.count ?? 0) <= 10_000,
                  (receipt.unreadSummary?.count ?? 0) <= 50_000,
                  receipt.rowCount.map({ (0...10_000).contains($0) }) ?? true,
                  (receipt.purpose == "fintrack-review-response") == (receipt.packetID != nil),
                  receipt.packetID.map({ packet in manifests.contains { $0.id == packet } || (retiredPacketIDs ?? []).contains(packet) }) ?? true,
                  receipt.digest.count == 64, receipt.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                  Set(receipt.itemIDs).count == receipt.itemIDs.count,
                  Set(receipt.decisionIDs ?? []).count == (receipt.decisionIDs ?? []).count,
                  Set(receipt.decisionIDs ?? []).isSubset(of: Set(receipt.itemIDs)),
                  itemIDs.isDisjoint(with: receipt.itemIDs) else { throw ExchangeError.invalid("Invalid compact import receipt.") }
            itemIDs.formUnion(receipt.itemIDs)
        }
        let answers = discussionAnswers ?? []
        guard Set(answers.map(\.id)).count == answers.count else { throw ExchangeError.invalid("Duplicate retained answers.") }
        for answer in answers {
            guard let record = byID[answer.recordID], let revision = Int64(answer.expectedRevision), revision > 0,
                  revision <= record.revision, !answer.text.isEmpty, answer.text.count <= 50_000,
                  (answer.questionForUser?.count ?? 0) <= 10_000 else { throw ExchangeError.invalid("Invalid retained discussion answer.") }
        }
        for (key, text) in discussionClosedRevisions ?? [:] {
            guard let id = UUID(uuidString: key), key == id.uuidString, let record = byID[id], let revision = Int64(text),
                  revision > 0, revision <= record.revision, String(revision) == text else { throw ExchangeError.invalid("Invalid discussion closure revision.") }
        }
    }
}

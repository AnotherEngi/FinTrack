import Foundation
import Testing
@testable import FinTrackCore

@Test func clipboardAcceptsOnlyCompleteBoundedReplyJSONAndAnOptionalSingleFence() throws {
    let record = try SyntheticTransactions.make()[0]
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: [record], catalog: .prototype, mode: .fullHistory)
    let response = ReviewResponse(packetID: packet.manifest.id, knowledgeVersion: packet.manifest.knowledgeVersion,
        answers: [.init(recordID: record.id, expectedRevision: "1", text: "Fictional café answer")])
    let json = String(decoding: try ExchangeJSON.encode(response), as: UTF8.self)
    let raw = try ClipboardExchange.incoming(json)
    #expect(try ClipboardExchange.incoming("\u{feff}\n```json\n" + json + "\n```\n") == raw)
    try workspace.receive(raw)
    #expect(workspace.discussion(for: record)?.answers.first?.text == "Fictional café answer")
    for invalid in ["https://example.invalid/reply.json", "Here is your JSON:\n" + json, "```json\n" + json,
                    json + "{}", "{}", String(repeating: "x", count: ClipboardExchange.maximumBytes + 1),
                    "{\"schemaVersion\":1,\"purpose\":\"fintrack-full-backup\"}"] {
        #expect(throws: (any Error).self) { try ClipboardExchange.incoming(invalid) }
    }
}

@Test func clipboardReviewIncludesTheEntirePacketOrFailsWithoutTruncation() throws {
    var workspace = ReviewWorkspace()
    let packet = try workspace.prepare(records: SyntheticTransactions.make(), catalog: .prototype, mode: .fullHistory)
    let bytes = try ExchangeJSON.encode(packet)
    let text = try ClipboardExchange.reviewText(bytes)
    #expect(text.hasSuffix(String(decoding: bytes, as: UTF8.self)) && text.contains(packet.manifest.id.uuidString))
    #expect(throws: (any Error).self) { try ClipboardExchange.reviewText(Data(repeating: 120, count: ClipboardExchange.maximumBytes)) }
}

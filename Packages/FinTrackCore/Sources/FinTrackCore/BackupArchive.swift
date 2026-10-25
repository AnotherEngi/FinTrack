import Foundation
#if os(Windows)
import WinSDK
#endif

public protocol ArchiveCompression: Sendable {
    func compress(_ data: Data) throws -> Data?
    func decompress(_ data: Data, expectedSize: Int) throws -> Data
}

public struct UncompressedArchive: ArchiveCompression {
    public init() {}
    public func compress(_ data: Data) throws -> Data? { nil }
    public func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        throw ExchangeError.invalid("This archive uses compression unavailable in this reader. Open it in FinTrack on iPad or Mac.")
    }
}

/// Limits are independent of the 50 MiB AI exchange contract. Capacity is checked
/// before committing local state; no cloud/network availability is required.
public enum BackupCapacity {
    public static let maximumRecords = 250_000
    public static let maximumLogicalBytes = 1_024 * 1_024 * 1_024
    public static let maximumFileBytes = 2 * 1_024 * 1_024 * 1_024
    public static let maximumEntryBytes = 80 * 1_024 * 1_024
    public static let maximumEntries = 1_000_000
    public static func validate(recordCount: Int, recordBytes: Int, workspace: ReviewWorkspace) throws {
        guard recordCount <= maximumRecords else { throw ExchangeError.invalid("This ledger exceeds the supported 250,000-record capacity. No changes were committed.") }
        var workspaceBytes = 0, entries = recordCount
        try BackupArchive.workspaceParts(workspace) { _, _, data in
            guard data.count <= maximumEntryBytes else { throw ExchangeError.invalid("An individual backup item exceeds 80 MiB. No changes were committed.") }
            workspaceBytes += data.count; entries += 1
            guard workspaceBytes <= maximumLogicalBytes else { throw ExchangeError.invalid("Workspace exceeds backup capacity.") }
        }
        guard recordBytes <= maximumLogicalBytes - workspaceBytes - 1_048_576, entries + 2 <= maximumEntries else {
            throw ExchangeError.invalid("This state exceeds the supported backup capacity (1 GiB logical data). Export or resolve outstanding imports before adding more data. Existing data was preserved.")
        }
    }
}

/// Framed logical archive v2. Payloads are independently bounded/compressed and
/// hashed. The terminal digest binds their order and headers; it is integrity,
/// not authentication. No paths from an archive are ever extracted to disk.
public enum BackupArchive {
    public static let magic = Data("FINTRACK-ARCHIVE-2\n".utf8)
    private struct Manifest: Codable {
        let version: Int
        let minimumReader: Int
        let generation: Foundation.UUID
        let createdAt: Date
        let amountConvention: String
        let records: Int
    }
    private struct Header: Codable {
        let field: String
        let key: String?
        let bytes: Int
        let storedBytes: Int
        let compressed: Bool
        let digest: String
    }
    private struct End: Codable { let entries: Int; let logicalBytes: Int; let chain: String; let counts: [String: Int] }
    private static func encoder() -> JSONEncoder {
        let result = JSONEncoder(); result.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return result
    }
    private static func digest(field: String, key: String?, data: Data) -> String {
        var input = Data((field + "\u{0}" + (key ?? "") + "\u{0}").utf8); input.append(data)
        return ContentDigest.sha256(input)
    }

    /// Atomic destination replacement. A failed writer never publishes a partial archive.
    public static func write(_ snapshot: FullBackup, to destination: URL,
                             compression: any ArchiveCompression = UncompressedArchive()) throws {
        try snapshot.validate(catalog: .prototype)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".archive-\(Foundation.UUID().uuidString).partial")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil) else { throw ExchangeError.invalid("Could not create backup file.") }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        var closed = false
        defer { if !closed { try? output.close() } }
        try output.write(contentsOf: magic)
        var chain = "", count = 0, logicalBytes = 0, fileBytes = magic.count
        var counts: [String: Int] = [:]
        func emit(_ field: String, _ key: String?, _ data: Data, terminal: Bool = false) throws {
            guard data.count <= BackupCapacity.maximumEntryBytes else { throw ExchangeError.invalid("Backup entry exceeds 80 MiB.") }
            let compressed = try compression.compress(data)
            let stored = compressed.flatMap { $0.count < data.count ? $0 : nil } ?? data
            let header = Header(field: field, key: key, bytes: data.count, storedBytes: stored.count,
                compressed: stored.count != data.count, digest: digest(field: field, key: key, data: data))
            let headerBytes = try encoder().encode(header)
            fileBytes += headerBytes.count + stored.count + 2
            guard fileBytes <= BackupCapacity.maximumFileBytes else { throw ExchangeError.invalid("Backup file exceeds 2 GiB.") }
            if !terminal {
                count += 1; logicalBytes += data.count
                guard count <= BackupCapacity.maximumEntries, logicalBytes <= BackupCapacity.maximumLogicalBytes else { throw ExchangeError.invalid("Backup exceeds supported capacity.") }
                counts[field, default: 0] += 1
                chain = ContentDigest.sha256(Data((chain + String(decoding: headerBytes, as: UTF8.self)).utf8))
            }
            try output.write(contentsOf: headerBytes); try output.write(contentsOf: Data([10]))
            try output.write(contentsOf: stored); try output.write(contentsOf: Data([10]))
        }
        let manifest = Manifest(version: 2, minimumReader: 2, generation: snapshot.workspace.generation,
            createdAt: snapshot.createdAt, amountConvention: snapshot.amountSignConvention, records: snapshot.records.count)
        try emit("manifest", nil, encoder().encode(manifest))
        for record in snapshot.records { try emit("record", nil, encoder().encode(record)) }
        try workspaceParts(snapshot.workspace) { try emit($0, $1, $2) }
        try emit("end", nil, encoder().encode(End(entries: count, logicalBytes: logicalBytes, chain: chain, counts: counts)), terminal: true)
        try output.synchronize(); try output.close(); closed = true
        if FileManager.default.fileExists(atPath: destination.path) {
            #if os(Windows)
            // Foundation's replaceItemAt is not implemented on Windows. Publish
            // by a same-directory filesystem rename without deleting the old file first.
            let sourcePath = Array(temporary.path.utf16) + [0]
            let destinationPath = Array(destination.path.utf16) + [0]
            let replaced = sourcePath.withUnsafeBufferPointer { source in
                destinationPath.withUnsafeBufferPointer { target in
                    MoveFileExW(source.baseAddress, target.baseAddress, DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
                }
            }
            guard replaced else { throw ExchangeError.invalid("Could not replace backup file (Windows error \(GetLastError())).") }
            #else
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            #endif
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }

    public static func read(from url: URL, compression: any ArchiveCompression = UncompressedArchive()) throws -> FullBackup {
        let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard size.isRegularFile == true, let bytes = size.fileSize, bytes <= BackupCapacity.maximumFileBytes else { throw ExchangeError.invalid("Choose a regular backup file no larger than 2 GiB.") }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        func readExactly(_ count: Int) throws -> Data {
            var data = Data()
            while data.count < count {
                guard let next = try input.read(upToCount: count - data.count), !next.isEmpty else { throw ExchangeError.invalid("The backup is truncated.") }
                data.append(next)
            }
            return data
        }
        let prefix = try readExactly(min(bytes, magic.count))
        if prefix != magic {
            // Read compatibility for the old bounded JSON archive; never silently
            // apply its exchange ceiling to new archive files.
            guard bytes <= ExchangeJSON.maximumBytes else { throw ExchangeError.invalid("This is not a supported FinTrack archive. Legacy JSON backups must be at most 50 MiB.") }
            try input.seek(toOffset: 0)
            let data = try readExactly(bytes)
            let backup = try ExchangeJSON.decode(FullBackup.self, from: data)
            try backup.validate(catalog: .prototype); return backup
        }
        var chain = "", count = 0, logicalBytes = 0, counts: [String: Int] = [:]
        var manifest: Manifest?, workspace: ReviewWorkspace?, records: [LedgerTransaction] = []
        var dictionaryKeys: Set<String> = []
        while true {
            var line = Data()
            while true {
                let byte = try readExactly(1)
                if byte[0] == 10 { break }
                line.append(byte)
                guard line.count <= 4096 else { throw ExchangeError.invalid("Oversized backup header.") }
            }
            let header = try JSONDecoder().decode(Header.self, from: line)
            guard header.bytes > 0, header.bytes <= BackupCapacity.maximumEntryBytes,
                  header.storedBytes > 0, header.storedBytes <= header.bytes,
                  header.compressed || header.storedBytes == header.bytes,
                  header.field.count <= 80, (header.key?.count ?? 0) <= 120 else { throw ExchangeError.invalid("Invalid archive entry size or identity.") }
            let stored = try readExactly(header.storedBytes)
            guard try readExactly(1) == Data([10]) else { throw ExchangeError.invalid("Invalid archive framing.") }
            let data = header.compressed ? try compression.decompress(stored, expectedSize: header.bytes) : stored
            guard data.count == header.bytes, digest(field: header.field, key: header.key, data: data) == header.digest else { throw ExchangeError.invalid("A backup entry failed its integrity check.") }
            if header.field == "end" {
                let end = try JSONDecoder().decode(End.self, from: data)
                guard let manifest, let workspace, end.entries == count, end.logicalBytes == logicalBytes,
                      end.chain == chain, end.counts == counts, records.count == manifest.records,
                      workspace.generation == manifest.generation,
                      (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw ExchangeError.invalid("Incomplete or inconsistent archive manifest.") }
                let result = FullBackup(records: records, workspace: workspace, at: manifest.createdAt)
                try result.validate(catalog: .prototype); return result
            }
            count += 1; logicalBytes += data.count; counts[header.field, default: 0] += 1
            guard count <= BackupCapacity.maximumEntries, logicalBytes <= BackupCapacity.maximumLogicalBytes else { throw ExchangeError.invalid("The expanded backup exceeds supported capacity.") }
            chain = ContentDigest.sha256(Data((chain + String(decoding: line, as: UTF8.self)).utf8))
            if header.field == "manifest" {
                guard count == 1, manifest == nil, header.key == nil else { throw ExchangeError.invalid("Duplicate or misplaced archive manifest.") }
                let value = try JSONDecoder().decode(Manifest.self, from: data)
                guard value.version == 2, value.minimumReader <= 2, value.amountConvention == Money.amountSignConvention,
                      (0...BackupCapacity.maximumRecords).contains(value.records) else { throw ExchangeError.invalid("Unsupported archive version, convention, or record capacity.") }
                manifest = value
            } else {
                guard manifest != nil else { throw ExchangeError.invalid("Archive is missing its manifest.") }
                if header.field == "record" {
                    guard records.count < BackupCapacity.maximumRecords, workspace == nil else { throw ExchangeError.invalid("Unexpected archive record.") }
                    records.append(try JSONDecoder().decode(LedgerTransaction.self, from: data))
                } else if header.field == "workspace" {
                    guard workspace == nil else { throw ExchangeError.invalid("Duplicate archive workspace.") }
                    let value = try JSONDecoder().decode(ReviewWorkspace.self, from: data)
                    var parts = 0; try workspaceParts(value) { _, _, _ in parts += 1 }
                    guard parts == 1 else { throw ExchangeError.invalid("Collections cannot be embedded in archive workspace metadata.") }
                    workspace = value
                } else {
                    guard var value = workspace else { throw ExchangeError.invalid("Missing workspace metadata.") }
                    if let key = header.key {
                        guard dictionaryKeys.insert(header.field + ":" + key).inserted else { throw ExchangeError.invalid("Duplicate archive dictionary key.") }
                    }
                    try apply(data, field: header.field, key: header.key, to: &value); workspace = value
                }
            }
        }
    }

    static func workspaceParts(_ workspace: ReviewWorkspace, emit: (String, String?, Data) throws -> Void) throws {
        var base = workspace
        base.pending = []; base.manifests = []; base.staged = []; base.processedFiles = []; base.decidedProposals = []
        base.knowledge = []; base.sourceLinks = []; base.drafts = [:]; base.discussionReplies = nil
        base.resolvedDiscussions = nil; base.discussionDrafts = nil; base.summaryVisibility = nil
        base.importReceipts = nil; base.retiredPacketIDs = nil; base.discussionAnswers = nil; base.discussionClosedRevisions = nil
        base.importedCategories = nil; base.historyImport = nil; base.historyDetails = nil
        func item<T: Encodable>(_ value: T, _ field: String, _ key: String? = nil) throws { try emit(field, key, encoder().encode(value)) }
        try item(base, "workspace")
        for value in workspace.pending { try item(value, "pending") }
        for value in workspace.manifests { try item(value, "manifests") }
        for value in workspace.staged { try item(value, "staged") }
        for value in workspace.processedFiles { try item(value, "processedFiles") }
        for value in workspace.decidedProposals { try item(value, "decidedProposals") }
        for value in workspace.knowledge { try item(value, "knowledge") }
        for value in workspace.sourceLinks { try item(value, "sourceLinks") }
        for key in workspace.drafts.keys.sorted() { try item(workspace.drafts[key]!, "drafts", key) }
        for value in workspace.discussionReplies ?? [] { try item(value, "discussionReplies") }
        for key in (workspace.resolvedDiscussions ?? [:]).keys.sorted() { try item(workspace.resolvedDiscussions![key]!, "resolvedDiscussions", key) }
        for key in (workspace.discussionDrafts ?? [:]).keys.sorted() { try item(workspace.discussionDrafts![key]!, "discussionDrafts", key) }
        if let value = workspace.summaryVisibility { try item(value, "summaryVisibility") }
        for value in workspace.importReceipts ?? [] { try item(value, "importReceipts") }
        for value in (workspace.retiredPacketIDs ?? []).sorted(by: { $0.uuidString < $1.uuidString }) { try item(value, "retiredPacketIDs") }
        for value in workspace.discussionAnswers ?? [] { try item(value, "discussionAnswers") }
        for key in (workspace.discussionClosedRevisions ?? [:]).keys.sorted() { try item(workspace.discussionClosedRevisions![key]!, "discussionClosedRevisions", key) }
        for value in workspace.importedCategories ?? [] { try item(value, "importedCategories") }
        if let receipt = workspace.historyImport { try item(receipt, "historyImport") }
        for key in (workspace.historyDetails ?? [:]).keys.sorted() { try item(workspace.historyDetails![key]!, "historyDetails", key) }
    }

    private static func apply(_ data: Data, field: String, key: String?, to value: inout ReviewWorkspace) throws {
        func decode<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: data) }
        let dictionaries: Set<String> = ["drafts", "resolvedDiscussions", "discussionDrafts", "discussionClosedRevisions", "historyDetails"]
        guard (key != nil) == dictionaries.contains(field) else { throw ExchangeError.invalid("Invalid archive entry key.") }
        switch field {
        case "pending": value.pending.append(try decode(FeedbackEvent.self))
        case "manifests": value.manifests.append(try decode(ReviewManifest.self))
        case "staged": value.staged.append(try decode(StagedFile.self))
        case "processedFiles": value.processedFiles.append(try decode(UUID.self))
        case "decidedProposals": value.decidedProposals.append(try decode(UUID.self))
        case "knowledge": value.knowledge.append(try decode(KnowledgeRule.self))
        case "sourceLinks": value.sourceLinks.append(try decode(SourceLink.self))
        case "drafts": value.drafts[key!] = try decode(Data.self)
        case "discussionReplies": if value.discussionReplies == nil { value.discussionReplies = [] }; value.discussionReplies?.append(try decode(UserDiscussionReply.self))
        case "resolvedDiscussions": if value.resolvedDiscussions == nil { value.resolvedDiscussions = [:] }; value.resolvedDiscussions?[key!] = try decode(DiscussionBoundary.self)
        case "discussionDrafts": if value.discussionDrafts == nil { value.discussionDrafts = [:] }; value.discussionDrafts?[key!] = try decode(DiscussionDraft.self)
        case "summaryVisibility": guard value.summaryVisibility == nil else { throw ExchangeError.invalid("Duplicate visibility settings.") }; value.summaryVisibility = try decode(SummaryVisibility.self)
        case "importReceipts": if value.importReceipts == nil { value.importReceipts = [] }; value.importReceipts?.append(try decode(ImportReceipt.self))
        case "retiredPacketIDs": if value.retiredPacketIDs == nil { value.retiredPacketIDs = [] }; guard value.retiredPacketIDs?.insert(try decode(UUID.self)).inserted == true else { throw ExchangeError.invalid("Duplicate retired packet ID.") }
        case "discussionAnswers": if value.discussionAnswers == nil { value.discussionAnswers = [] }; value.discussionAnswers?.append(try decode(DiscussionAnswer.self))
        case "discussionClosedRevisions": if value.discussionClosedRevisions == nil { value.discussionClosedRevisions = [:] }; value.discussionClosedRevisions?[key!] = try decode(String.self)
        case "importedCategories": if value.importedCategories == nil { value.importedCategories = [] }; value.importedCategories?.append(try decode(ReviewCategory.self))
        case "historyImport": guard value.historyImport == nil else { throw ExchangeError.invalid("Duplicate history import receipt.") }; value.historyImport = try decode(HistoryImportReceipt.self)
        case "historyDetails": if value.historyDetails == nil { value.historyDetails = [:] }; value.historyDetails?[key!] = try decode([String: String].self)
        default: throw ExchangeError.invalid("Unsupported archive section: " + field)
        }
    }
}

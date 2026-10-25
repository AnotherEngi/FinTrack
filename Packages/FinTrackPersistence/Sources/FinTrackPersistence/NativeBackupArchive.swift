import Foundation
import Compression
import CryptoKit
import FinTrackCore

private struct DeflateArchive: ArchiveCompression {
    func compress(_ data: Data) throws -> Data? {
        guard !data.isEmpty else { return nil }
        var output = Data(count: data.count)
        let capacity = output.count
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written; return output
    }
    func decompress(_ data: Data, expectedSize: Int) throws -> Data {
        guard !data.isEmpty, expectedSize > 0, expectedSize <= BackupCapacity.maximumEntryBytes else { throw ExchangeError.invalid("Invalid compressed backup size.") }
        // The extra byte detects streams that expand beyond the advertised bound.
        var output = Data(count: expectedSize + 1)
        let capacity = output.count
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_decode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ExchangeError.invalid("Invalid compressed archive entry.") }
        output.count = written; return output
    }
}

/// Synchronous, filesystem-only work. Call from a worker actor/detached task,
/// never by transferring a SwiftData context across actors.
public enum NativeBackupArchive {
    public static func write(_ snapshot: FullBackup, to url: URL) throws {
        try BackupArchive.write(snapshot, to: url, compression: DeflateArchive())
    }
    public static func read(from url: URL) throws -> FullBackup {
        try BackupArchive.read(from: url, compression: DeflateArchive())
    }
    public static func readSelectedFile(_ url: URL) throws -> FullBackup {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var snapshot: FullBackup?, operationError: Error?, coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { source in
            do { snapshot = try read(from: source) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }; if let operationError { throw operationError }
        guard let snapshot else { throw ExchangeError.invalid("The selected archive could not be read.") }
        return snapshot
    }
    public static func fingerprint(_ url: URL) throws -> String {
        let info = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard info.isRegularFile == true, let size = info.fileSize, size <= BackupCapacity.maximumFileBytes else {
            throw ExchangeError.invalid("Invalid or oversized archive file.")
        }
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hasher = SHA256()
        var total = 0
        while let bytes = try input.read(upToCount: 1_048_576), !bytes.isEmpty {
            total += bytes.count
            guard total <= BackupCapacity.maximumFileBytes else { throw ExchangeError.invalid("Archive changed size while being read.") }
            hasher.update(data: bytes)
        }
        guard total == size else { throw ExchangeError.invalid("Archive changed size while being read.") }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation
import Darwin
import FinTrackCore

public struct PreservedStore: Identifiable, Sendable {
    public let id: String
    public let createdAt: Date?
}

/// Database recovery does not open or encode the damaged source store. A fresh
/// isolated store is committed and reopened before an atomic pointer switch.
@MainActor
public enum StoreRecovery {
    private struct Pointer: Codable { let directory: UUID }
    private static func pointerURL(_ directory: URL) -> URL { directory.appendingPathComponent("ActiveStore.json") }
    public static func activeURL(in directory: URL) throws -> URL {
        let pointer = pointerURL(directory)
        guard FileManager.default.fileExists(atPath: pointer.path) else { return directory.appendingPathComponent("FinTrack.store") }
        let info = try pointer.resourceValues(forKeys: [.fileSizeKey])
        guard (info.fileSize ?? Int.max) <= 4096 else { throw PersistenceError.invalidStoredValue }
        let value = try JSONDecoder().decode(Pointer.self, from: Data(contentsOf: pointer))
        let target = storeURL(value.directory, in: directory)
        guard FileManager.default.fileExists(atPath: target.path),
              FileManager.default.fileExists(atPath: target.appendingPathExtension("amount-sign").path) else {
            throw ExchangeError.invalid("The selected database is missing. Restore a backup; an empty replacement was not created.")
        }
        return target
    }
    private static func storeURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("Stores", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent("FinTrack.store")
    }
    public static func prepare(_ snapshot: FullBackup, in directory: URL,
                               catalog: ReviewCatalog = .prototype) throws -> UUID {
        try snapshot.validate(catalog: catalog)
        let id = UUID(), url = storeURL(id, in: directory)
        do {
            do {
                let repository = try LocalTransactionRepository(storeURL: url, catalog: catalog)
                try repository.restore(snapshot)
            }
            let check = try LocalTransactionRepository(storeURL: url, catalog: catalog)
            let restored = try check.backup()
            try restored.validate(catalog: catalog)
            let ordered = { (records: [LedgerTransaction]) in records.sorted { $0.id.uuidString < $1.id.uuidString } }
            guard ordered(restored.records) == ordered(snapshot.records),
                  restored.workspace.pending == snapshot.workspace.pending,
                  restored.workspace.knowledge == snapshot.workspace.knowledge,
                  restored.workspace.drafts == snapshot.workspace.drafts,
                  restored.workspace.summaryVisibility == snapshot.workspace.summaryVisibility,
                  restored.workspace.importedCategories == snapshot.workspace.importedCategories,
                  restored.workspace.historyImport == snapshot.workspace.historyImport,
                  restored.workspace.historyDetails == snapshot.workspace.historyDetails else {
                throw ExchangeError.invalid("The isolated restore did not match the archive. The active store is unchanged.")
            }
            return id
        } catch {
            // Only this operation's newly created UUID directory is discarded.
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            throw error
        }
    }
    public static func activate(_ id: UUID, in directory: URL, catalog: ReviewCatalog = .prototype) throws {
        let target = storeURL(id, in: directory)
        guard FileManager.default.fileExists(atPath: target.path),
              FileManager.default.fileExists(atPath: target.appendingPathExtension("amount-sign").path) else { throw ExchangeError.invalid("The recovery database has not been prepared.") }
        let check = try LocalTransactionRepository(storeURL: target, catalog: catalog)
        try check.backup().validate(catalog: catalog)
        let pointer = pointerURL(directory)
        let replacing = FileManager.default.fileExists(atPath: pointer.path)
        if replacing {
            let info = try pointer.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info.isRegularFile == true, info.isSymbolicLink != true else {
                throw ExchangeError.invalid("The active database pointer is not a regular file. It was preserved; recovery was not activated.")
            }
        }
        // When replacing, this name receives the old pointer in the same atomic
        // operation that publishes the new one. Never read the damaged bytes or
        // inherit their permissions, and never remove the old pointer first.
        let name = replacing ? "PreviousStore-\(UUID().uuidString).json" : ".ActiveStore-\(UUID().uuidString).json"
        let replacement = directory.appendingPathComponent(name)
        var preserveReplacement = false
        defer { if !preserveReplacement { try? FileManager.default.removeItem(at: replacement) } }
        try JSONEncoder().encode(Pointer(directory: id)).write(to: replacement, options: .atomic)
        if replacing {
            let result = try replacement.withUnsafeFileSystemRepresentation { source in
                try pointer.withUnsafeFileSystemRepresentation { destination in
                    guard let source, let destination else { throw PersistenceError.invalidStoredValue }
                    return Darwin.renamex_np(source, destination, UInt32(RENAME_SWAP))
                }
            }
            // Unsupported swaps and permission failures leave the original in
            // place. Do not fall back to a non-atomic remove/move sequence.
            guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            preserveReplacement = true
        } else { try FileManager.default.moveItem(at: replacement, to: pointer) }
    }
    public static func preservedStores(in directory: URL) throws -> [PreservedStore] {
        let active = try activeURL(in: directory).standardizedFileURL
        var result: [PreservedStore] = []
        let legacy = directory.appendingPathComponent("FinTrack.store")
        let legacyFiles = [legacy, directory.appendingPathComponent("FinTrack.store-wal"),
            directory.appendingPathComponent("FinTrack.store-shm"), legacy.appendingPathExtension("amount-sign")]
        let draftFolder = directory.appendingPathComponent("Drafts", isDirectory: true)
        let draftFiles: [URL]
        if FileManager.default.fileExists(atPath: draftFolder.path) {
            draftFiles = try FileManager.default.contentsOfDirectory(at: draftFolder, includingPropertiesForKeys: nil)
        } else { draftFiles = [] }
        let hasOldDrafts = draftFiles.contains { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil }
        if legacy.standardizedFileURL != active, legacyFiles.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) || hasOldDrafts {
            let source = legacyFiles.first { FileManager.default.fileExists(atPath: $0.path) } ?? draftFolder
            result.append(PreservedStore(id: "legacy", createdAt: try source.resourceValues(forKeys: [.creationDateKey]).creationDate))
        }
        let stores = directory.appendingPathComponent("Stores", isDirectory: true)
        if FileManager.default.fileExists(atPath: stores.path) {
            for child in try FileManager.default.contentsOfDirectory(at: stores, includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey]) {
                guard let id = UUID(uuidString: child.lastPathComponent),
                      storeURL(id, in: directory).standardizedFileURL != active,
                      try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                result.append(PreservedStore(id: id.uuidString, createdAt: try child.resourceValues(forKeys: [.creationDateKey]).creationDate))
            }
        }
        return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
    public static func deletePreservedStore(id: String, in directory: URL) throws {
        guard try preservedStores(in: directory).contains(where: { $0.id == id }) else {
            throw ExchangeError.invalid("This is not an inactive preserved store. The active store cannot be deleted here.")
        }
        if id == "legacy" {
            for name in ["FinTrack.store", "FinTrack.store-wal", "FinTrack.store-shm", "FinTrack.store.amount-sign"] {
                let file = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            }
            let drafts = directory.appendingPathComponent("Drafts", isDirectory: true)
            if FileManager.default.fileExists(atPath: drafts.path) {
                for file in try FileManager.default.contentsOfDirectory(at: drafts, includingPropertiesForKeys: [.isRegularFileKey]) {
                    guard file.pathExtension == "json", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil,
                          try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    try FileManager.default.removeItem(at: file)
                }
            }
        } else if let uuid = UUID(uuidString: id) {
            try FileManager.default.removeItem(at: storeURL(uuid, in: directory).deletingLastPathComponent())
        }
    }
}

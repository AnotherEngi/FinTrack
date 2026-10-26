import Foundation
import Observation
import FinTrackCore
import FinTrackPersistence

/// Permissions and progress only. Candidate bytes live in a bounded archive file,
/// not a base64 copy inside this journal. retired journals are not converted.
private struct BackupDiskState: Codable, Sendable {
    var format = FinancialFormat.version
    var bookmark: Data?
    var progress = BackupProgress()
    var candidateFile: String?
    var candidateBytes: Int?
    var candidateDigest: String?
    var confirmedBytes: Int?
    var confirmedDigest: String?
    var confirmedAt: Date?
    var cleanup: [BackupVersion]?
}

private actor CloudBackupFiles {
    func bookmark(for folder: URL) throws -> Data {
        guard folder.startAccessingSecurityScopedResource() else { throw ExchangeError.invalid("Cannot access that folder. Select it again.") }
        defer { folder.stopAccessingSecurityScopedResource() }
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey])
        guard values.isDirectory == true, values.isUbiquitousItem == true else { throw ExchangeError.invalid("Choose a folder inside iCloud Drive.") }
        return try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    func prepare(_ snapshot: FullBackup, version: BackupVersion, directory: URL) throws -> (Int, String) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(version.fileName)
        try NativeBackupArchive.write(snapshot, to: url)
        return try verify(url, generation: version.generation)
    }
    private nonisolated func verify(_ url: URL, generation: UUID) throws -> (Int, String) {
        let value = try NativeBackupArchive.read(from: url)
        guard value.workspace.generation == generation,
              let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { throw ExchangeError.invalid("Backup generation or size does not match its journal.") }
        return (size, try NativeBackupArchive.fingerprint(url))
    }
    func write(local: URL, digest: String, version: BackupVersion, bookmark: Data) throws {
        guard try NativeBackupArchive.fingerprint(local) == digest else { throw ExchangeError.invalid("The local pending archive changed. It was preserved for recovery.") }
        try access(bookmark) { folder in
            let target = folder.appendingPathComponent(version.fileName)
            var coordinationError: NSError?, operationError: Error?
            NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { destination in
                do {
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        let staging = destination.deletingLastPathComponent().appendingPathComponent(".FinTrack-upload-\(version.id.uuidString).partial")
                        if FileManager.default.fileExists(atPath: staging.path) {
                            // An unreadable/truncated unpublished attempt can be replaced;
                            // a finalized backup is never treated this way.
                            if (try? NativeBackupArchive.fingerprint(staging)) != digest { try FileManager.default.removeItem(at: staging) }
                        }
                        if !FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.copyItem(at: local, to: staging) }
                        guard try NativeBackupArchive.fingerprint(staging) == digest else { throw ExchangeError.invalid("The staged upload failed its integrity check.") }
                        // Only complete, verified bytes acquire the monitored final name.
                        try FileManager.default.moveItem(at: staging, to: destination)
                    }
                    guard try NativeBackupArchive.fingerprint(destination) == digest else { throw ExchangeError.invalid("The pending cloud file changed outside FinTrack. The previous confirmed backup remains protected.") }
                    _ = try verify(destination, generation: version.generation)
                } catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }; if let operationError { throw operationError }
        }
    }
    func remove(_ version: BackupVersion, bookmark: Data) throws {
        try access(bookmark) { folder in
            let url = folder.appendingPathComponent(version.fileName)
            var coordinationError: NSError?, operationError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { destination in
                do { if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) } }
                catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }; if let operationError { throw operationError }
        }
    }
    func cleanupLocal(directory: URL, keeping name: String?) throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) {
            guard file.lastPathComponent != name, file.lastPathComponent.hasPrefix("FinTrack-"),
                  UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.dropFirst(9))) != nil,
                  ["fintrack", "json"].contains(file.pathExtension),
                  try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            try FileManager.default.removeItem(at: file)
        }
    }
    func cleanupStaging(bookmark: Data, keeping id: UUID?) throws {
        try access(bookmark) { folder in
            let prefix = ".FinTrack-upload-", cutoff = Date.now.addingTimeInterval(-86_400)
            for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]) {
                guard file.lastPathComponent.hasPrefix(prefix), file.pathExtension == "partial",
                      let uuid = UUID(uuidString: String(file.deletingPathExtension().lastPathComponent.dropFirst(prefix.count))), uuid != id else { continue }
                let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true, let date = info.contentModificationDate, date < cutoff else { continue }
                try FileManager.default.removeItem(at: file)
            }
        }
    }
    private func access(_ bookmark: Data, work: (URL) throws -> Void) throws {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.startAccessingSecurityScopedResource() else { throw ExchangeError.invalid("Backup folder permission expired. Select it again.") }
        defer { folder.stopAccessingSecurityScopedResource() }
        try work(folder)
    }
}

@MainActor @Observable
final class CloudBackup {
    private var disk = BackupDiskState()
    private let journalURL: URL
    private let cacheURL: URL
    private let files = CloudBackupFiles()
    private var task: Task<Void, Never>?
    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var scopedFolder: URL?
    private var latest: FullBackup?
    private var configurationFailure: String?
    private var observedConfirmed = false
    private var verifiedCandidate: UUID?
    private var busy = false
    private(set) var status = "Choose an iCloud Drive folder to enable automatic backup."
    private(set) var failure: String?
    var configured: Bool { disk.bookmark != nil }
    var lastConfirmed: Date? { disk.confirmedAt ?? disk.progress.confirmed?.createdAt }
    private var archiveUpgradeNeeded: Bool { disk.progress.confirmed?.archiveVersion != 2 || disk.confirmedDigest == nil }
    var isCurrent: Bool {
        guard let latest else { return false }
        return !archiveUpgradeNeeded && observedConfirmed && disk.progress.isCurrent(generation: latest.workspace.generation)
    }
    init(directory: URL) throws {
        journalURL = directory.appendingPathComponent("BackupConnection.json")
        cacheURL = directory.appendingPathComponent("BackupCandidates", isDirectory: true)
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do {
                let info = try journalURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard info.isRegularFile == true, let size = info.fileSize, size <= 80 * 1_024 * 1_024 else {
                    throw ExchangeError.invalid("The backup journal is oversized or unreadable.")
                }
                disk = try StrictJSON.decode(BackupDiskState.self, from: Data(contentsOf: journalURL))
                guard disk.format == FinancialFormat.version else { throw ExchangeError.invalid("Unsupported backup connection format; select the folder again.") }
                if let version = disk.progress.candidate {
                    guard version.archiveVersion == 2, disk.candidateFile == version.fileName,
                          disk.candidateBytes != nil, disk.candidateDigest != nil else { throw ExchangeError.invalid("Inconsistent current backup journal.") }
                } else {
                    guard disk.candidateFile == nil else { throw ExchangeError.invalid("Orphan candidate metadata.") }
                }
            } catch {
                configurationFailure = "Backup settings could not be read. Select the iCloud folder again; the damaged journal will be preserved. \(error.localizedDescription)"
                failure = configurationFailure; disk = BackupDiskState()
            }
        }
    }
    func configure(folder: URL) async throws {
        guard !busy else { throw ExchangeError.invalid("A backup is running. Try again when it finishes.") }
        busy = true; defer { busy = false }
        let bookmark = try await files.bookmark(for: folder)
        if configurationFailure != nil {
            try FileManager.default.copyItem(at: journalURL, to: journalURL.deletingLastPathComponent()
                .appendingPathComponent("BackupConnection-damaged-\(UUID().uuidString).json"))
        }
        let previous = disk; disk = BackupDiskState(bookmark: bookmark)
        do { try persist() } catch { disk = previous; throw error }
        configurationFailure = nil; stopQuery(); busy = false; await run()
    }
    func schedule(_ snapshot: FullBackup) {
        latest = snapshot
        if isCurrent { status = "Backed up to iCloud."; return }
        status = configured ? "Saved on this iPad. Cloud backup pending." : "Automatic iCloud backup needs a folder."
        task?.cancel()
        task = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await self?.run()
        }
    }
    func retry() async { await run() }
    func pauseObservation() { stopQuery() }
    private func persist() throws { try JSONEncoder().encode(disk).write(to: journalURL, options: .atomic) }
    private func run() async {
        guard !busy, let bookmark = disk.bookmark, let latest else { return }
        busy = true; defer { busy = false }
        do {
            failure = nil
            if query == nil { try startQuery(bookmark: bookmark) }
            if disk.progress.candidate == nil && (archiveUpgradeNeeded || !disk.progress.isCurrent(generation: latest.workspace.generation)
                || (query?.isGathering == false && !observedConfirmed)) {
                var next = disk
                let version = next.progress.begin(generation: latest.workspace.generation)
                let info = try await files.prepare(latest, version: version, directory: cacheURL)
                next.candidateFile = version.fileName; next.candidateBytes = info.0; next.candidateDigest = info.1
                let previous = disk; disk = next
                do { try persist() } catch { disk = previous; throw error }
            }
            if let version = disk.progress.candidate, let name = disk.candidateFile, let digest = disk.candidateDigest {
                status = "Saved on this iPad. Waiting for iCloud upload confirmation."
                try await files.write(local: cacheURL.appendingPathComponent(name), digest: digest, version: version, bookmark: bookmark)
                verifiedCandidate = version.id
            }
            inspectMetadata()
            try await cleanup(bookmark: bookmark)
        } catch { failure = error.localizedDescription; status = "Saved on this iPad. Cloud backup needs attention." }
    }
    private func cleanup(bookmark: Data) async throws {
        for version in disk.cleanup ?? [] {
            try await files.remove(version, bookmark: bookmark)
            let previous = disk
            disk.cleanup?.removeAll { $0.id == version.id }
            do { try persist() } catch { disk = previous; throw error }
        }
        if disk.progress.confirmed != nil {
            try await files.cleanupLocal(directory: cacheURL, keeping: disk.candidateFile)
            try await files.cleanupStaging(bookmark: bookmark, keeping: disk.progress.candidate?.id)
        }
    }
    private func startQuery(bookmark: Data) throws {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.startAccessingSecurityScopedResource() else { throw ExchangeError.invalid("Select the backup folder again to renew permission.") }
        scopedFolder = folder
        let query = NSMetadataQuery(); query.searchScopes = [folder]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemFSNameKey, "FinTrack-")
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.inspectMetadata() }
            })
        }
        self.query = query
        guard query.start() else { stopQuery(); throw ExchangeError.invalid("iCloud monitoring could not start. Retry or select the folder again.") }
    }
    private func stopQuery() {
        query?.stop(); query = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }; observers.removeAll()
        scopedFolder?.stopAccessingSecurityScopedResource(); scopedFolder = nil
        observedConfirmed = false; verifiedCandidate = nil
    }
    private func inspectMetadata() {
        guard let query, !query.isGathering, let folder = scopedFolder else { return }
        query.disableUpdates(); defer { query.enableUpdates() }
        var uploaded: Set<String> = []
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { continue }
            if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError { failure = error.localizedDescription; continue }
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.intValue
            let expected = disk.progress.candidate?.fileName == url.lastPathComponent ? disk.candidateBytes
                : disk.progress.confirmed?.fileName == url.lastPathComponent ? disk.confirmedBytes : nil
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) == true,
               expected.map({ $0 == size }) ?? true { uploaded.insert(url.lastPathComponent) }
        }
        observedConfirmed = disk.progress.confirmed.map { uploaded.contains($0.fileName) } ?? false
        if let candidate = disk.progress.candidate, verifiedCandidate == candidate.id, uploaded.contains(candidate.fileName) {
            let previous = disk
            let old = disk.progress.confirm(id: candidate.id)
            disk.confirmedBytes = disk.candidateBytes; disk.confirmedDigest = disk.candidateDigest; disk.confirmedAt = .now
            disk.candidateFile = nil; disk.candidateBytes = nil; disk.candidateDigest = nil
            if let old {
                if disk.cleanup == nil { disk.cleanup = [] }; disk.cleanup?.append(old)
            }
            do { try persist() } catch { disk = previous; failure = error.localizedDescription; return }
            observedConfirmed = true; verifiedCandidate = nil
            if let latest, !isCurrent { schedule(latest) }
            if !busy { Task { [weak self] in await self?.run() } }
        }
        if isCurrent { status = "Backed up to iCloud." }
        else if disk.progress.candidate != nil { status = "Saved on this iPad. Cloud backup pending." }
        else if !observedConfirmed, disk.progress.confirmed != nil {
            status = "The last cloud backup cannot currently be verified."
            if !busy { Task { [weak self] in await self?.run() } }
        }
    }
}

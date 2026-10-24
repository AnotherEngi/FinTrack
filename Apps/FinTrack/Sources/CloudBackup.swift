import Foundation
import Observation
import FinTrackCore

/// Local permission/journal only; never part of exported financial archives.
private struct BackupDiskState: Codable, Sendable {
    var bookmark: Data?
    var progress = BackupProgress()
    var candidateData: Data?
}

private actor CloudBackupFiles {
    func bookmark(for folder: URL) throws -> Data {
        guard folder.startAccessingSecurityScopedResource() else {
            throw ExchangeError.invalid("Cannot access that folder. Choose an iCloud Drive folder again.")
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isUbiquitousItemKey])
        guard values.isDirectory == true, values.isUbiquitousItem == true else {
            throw ExchangeError.invalid("Choose a folder inside iCloud Drive, not On My iPad or another provider.")
        }
        return try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    func write(_ data: Data, version: BackupVersion, bookmark: Data) throws {
        try access(bookmark) { folder in
            let url = folder.appendingPathComponent(version.fileName)
            var coordinationError: NSError?
            var operationError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { destination in
                do {
                    // Never rewrite a candidate whose metadata might already say uploaded.
                    if FileManager.default.fileExists(atPath: destination.path) {
                        guard try Data(contentsOf: destination) == data else {
                            throw ExchangeError.invalid("The pending backup file changed outside FinTrack. Choose another backup folder to recover safely.")
                        }
                    } else { try data.write(to: destination, options: .atomic) }
                } catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
        }
    }

    func remove(_ version: BackupVersion, bookmark: Data) throws {
        try access(bookmark) { folder in
            let url = folder.appendingPathComponent(version.fileName)
            var coordinationError: NSError?
            var operationError: Error?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forDeleting, error: &coordinationError) { destination in
                do {
                    if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                } catch { operationError = error }
            }
            if let coordinationError { throw coordinationError }
            if let operationError { throw operationError }
        }
    }

    private func access(_ bookmark: Data, work: (URL) throws -> Void) throws {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.startAccessingSecurityScopedResource() else {
            throw ExchangeError.invalid("Backup folder permission expired. Choose the iCloud Drive folder again.")
        }
        defer { folder.stopAccessingSecurityScopedResource() }
        try work(folder)
    }
}

@MainActor
@Observable
final class CloudBackup {
    private var disk = BackupDiskState()
    private let journalURL: URL
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
    var lastConfirmed: Date? { disk.progress.confirmed?.createdAt }
    var isCurrent: Bool {
        guard let latest else { return false }
        return observedConfirmed && disk.progress.isCurrent(generation: latest.workspace.generation)
    }

    init(directory: URL) throws {
        journalURL = directory.appendingPathComponent("BackupConnection.json")
        if FileManager.default.fileExists(atPath: journalURL.path) {
            do {
                disk = try JSONDecoder().decode(BackupDiskState.self, from: Data(contentsOf: journalURL))
                guard (disk.progress.candidate == nil) == (disk.candidateData == nil) else {
                    throw ExchangeError.invalid("The backup journal is inconsistent.")
                }
                if let candidate = disk.progress.candidate, let data = disk.candidateData {
                    let snapshot = try ExchangeJSON.decode(FullBackup.self, from: data)
                    try snapshot.validate(catalog: .prototype)
                    guard snapshot.workspace.generation == candidate.generation else {
                        throw ExchangeError.invalid("The pending backup does not match its journal.")
                    }
                }
            } catch {
                configurationFailure = "Backup settings could not be read. Select the iCloud folder again; the damaged journal will be preserved. \(error.localizedDescription)"
                failure = configurationFailure
                disk = BackupDiskState()
            }
        }
    }

    func configure(folder: URL) async throws {
        guard !busy else { throw ExchangeError.invalid("A backup operation is running. Try again when it finishes.") }
        busy = true
        defer { busy = false }
        let bookmark = try await files.bookmark(for: folder)
        if configurationFailure != nil {
            let recovery = journalURL.deletingLastPathComponent().appendingPathComponent("BackupConnection-damaged-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: journalURL, to: recovery)
        }
        let previous = disk
        disk = BackupDiskState(bookmark: bookmark)
        do { try persist() } catch { disk = previous; throw error }
        configurationFailure = nil
        observedConfirmed = false
        verifiedCandidate = nil
        stopQuery()
        busy = false
        await run()
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

    private func persist() throws {
        try JSONEncoder().encode(disk).write(to: journalURL, options: .atomic)
    }

    private func run() async {
        guard !busy, let bookmark = disk.bookmark, let latest else { return }
        busy = true
        defer { busy = false }
        do {
            failure = nil
            if query == nil { try startQuery(bookmark: bookmark) }
            if disk.progress.candidate == nil && (!disk.progress.isCurrent(generation: latest.workspace.generation)
                || (query?.isGathering == false && !observedConfirmed)) {
                var next = disk
                try latest.validate(catalog: .prototype)
                _ = next.progress.begin(generation: latest.workspace.generation)
                next.candidateData = try ExchangeJSON.encode(latest)
                let previous = disk; disk = next
                do { try persist() } catch { disk = previous; throw error }
            }
            if let version = disk.progress.candidate, let data = disk.candidateData {
                status = "Saved on this iPad. Waiting for iCloud upload confirmation."
                try await files.write(data, version: version, bookmark: bookmark)
                verifiedCandidate = version.id
            }
            inspectMetadata()
        } catch {
            failure = error.localizedDescription
            status = "Saved on this iPad. Cloud backup needs attention."
        }
    }

    private func startQuery(bookmark: Data) throws {
        var stale = false
        let folder = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, folder.startAccessingSecurityScopedResource() else {
            throw ExchangeError.invalid("Choose the backup folder again to renew permission.")
        }
        scopedFolder = folder
        let query = NSMetadataQuery()
        query.searchScopes = [folder]
        query.predicate = NSPredicate(format: "%K BEGINSWITH %@", NSMetadataItemFSNameKey, "FinTrack-")
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.inspectMetadata() }
            })
        }
        self.query = query
        guard query.start() else {
            stopQuery()
            throw ExchangeError.invalid("iCloud upload monitoring could not start. Retry or reselect the folder.")
        }
    }

    private func stopQuery() {
        query?.stop(); query = nil
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        scopedFolder?.stopAccessingSecurityScopedResource(); scopedFolder = nil
        observedConfirmed = false
        verifiedCandidate = nil
    }

    private func inspectMetadata() {
        guard let query, !query.isGathering, let folder = scopedFolder else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }
        var uploaded: Set<String> = []
        var expectedSize: [String: Int] = [:]
        if let candidate = disk.progress.candidate, let data = disk.candidateData {
            expectedSize[candidate.fileName] = data.count
        }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL else { continue }
            if let error = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError {
                failure = error.localizedDescription
                continue
            }
            let size = (item.value(forAttribute: NSMetadataItemFSSizeKey) as? NSNumber)?.intValue
            if (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) == true,
               expectedSize[url.lastPathComponent].map({ $0 == size }) ?? true {
                uploaded.insert(url.lastPathComponent)
            }
        }
        observedConfirmed = disk.progress.confirmed.map { uploaded.contains($0.fileName) } ?? false
        if let candidate = disk.progress.candidate, verifiedCandidate == candidate.id,
           uploaded.contains(candidate.fileName) {
            // Persist confirmation before removing the previous good cloud file.
            let previous = disk
            let old = disk.progress.confirm(id: candidate.id)
            disk.candidateData = nil
            do { try persist() }
            catch { disk = previous; failure = error.localizedDescription; return }
            observedConfirmed = true
            verifiedCandidate = nil
            failure = nil
            if let old, let bookmark = disk.bookmark {
                Task { [weak self] in
                    do { try await self?.files.remove(old, bookmark: bookmark) }
                    catch { self?.failure = "The latest backup is uploaded; an older temporary backup could not be removed: \(error.localizedDescription)" }
                }
            }
            if let latest, !disk.progress.isCurrent(generation: latest.workspace.generation) {
                schedule(latest)
            }
        }
        if isCurrent { status = "Backed up to iCloud." }
        else if disk.progress.candidate != nil { status = "Saved on this iPad. Cloud backup pending." }
        else if !observedConfirmed, disk.progress.confirmed != nil {
            status = "The last cloud backup cannot currently be verified."
            if !busy { Task { [weak self] in await self?.run() } }
        }
    }
}

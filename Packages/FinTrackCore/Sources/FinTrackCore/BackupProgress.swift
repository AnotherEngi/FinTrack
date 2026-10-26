import Foundation

public struct BackupVersion: Codable, Equatable, Sendable {
    public let id: UUID
    public let generation: UUID
    public let createdAt: Date
    public let archiveVersion: Int
    public var fileName: String { "FinTrack-\(id.uuidString).fintrack" }
    public init(generation: UUID, at: Date = .now) { id = UUID(); self.generation = generation; createdAt = at; archiveVersion = 2 }
}

/// One confirmed file plus at most one replacement. Cloud confirmation is supplied
/// only by the Apple adapter; local write completion cannot advance this cursor.
public struct BackupProgress: Codable, Sendable {
    public private(set) var confirmed: BackupVersion?
    public private(set) var candidate: BackupVersion?
    public init() {}
    public mutating func begin(generation: UUID) -> BackupVersion {
        if let candidate { return candidate }
        let next = BackupVersion(generation: generation)
        candidate = next
        return next
    }
    @discardableResult
    public mutating func confirm(id: UUID) -> BackupVersion? {
        guard let candidate, candidate.id == id else { return nil }
        let old = confirmed
        confirmed = candidate; self.candidate = nil
        return old
    }
    public func isCurrent(generation: UUID) -> Bool { confirmed?.generation == generation }
}

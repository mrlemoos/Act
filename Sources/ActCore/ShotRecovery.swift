import Foundation

public struct ShotRecoveryRecord: Codable, Equatable, Sendable {
    public var document: ShotListDocument
    public var path: String?
    public var baseline: Data?
    public var isDirty: Bool
    public var screenplayFingerprint: String
    public var screenplayIdentity: String

    public init(document: ShotListDocument, path: String?, baseline: Data?, isDirty: Bool, screenplayFingerprint: String, screenplayIdentity: String) {
        self.document = document
        self.path = path
        self.baseline = baseline
        self.isDirty = isDirty
        self.screenplayFingerprint = screenplayFingerprint
        self.screenplayIdentity = screenplayIdentity
    }
}

/// Keeps shot-list recovery separate from Fountain files and native document autosaves.
public struct ShotRecoveryStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    public func url(identity: String) -> URL {
        directory.appendingPathComponent(SceneAnchor.digest(identity) + ".json")
    }

    /// A native restored untitled document gets a new process identity. Only a
    /// unique dirty untitled record with identical source can be claimed safely.
    public func load(identity: String, source: String) -> ShotRecoveryRecord? {
        if let exact = read(at: url(identity: identity)), exact.screenplayIdentity == identity {
            return exact
        }
        guard identity.hasPrefix("untitled:"), !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let fingerprint = SceneAnchor.digest(source)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        let matches = files.filter { $0.pathExtension == "json" }.compactMap { read(at: $0) }.filter {
            $0.isDirty && $0.screenplayIdentity.hasPrefix("untitled:") && $0.screenplayFingerprint == fingerprint
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public func save(record: ShotRecoveryRecord, identity: String) throws {
        // Recovery never bypasses the saved-document format's validation.
        _ = try ShotListStore.data(for: record.document)
        var stored = record
        stored.screenplayIdentity = identity
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(stored)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: url(identity: identity), options: .atomic)
    }

    public func discard(identity: String) throws {
        let file = url(identity: identity)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    /// Persist the destination before removing the previous recovery. A failed
    /// destination write leaves the existing recovery untouched.
    public func relocate(from oldIdentity: String, to newIdentity: String, record: ShotRecoveryRecord) throws {
        try save(record: record, identity: newIdentity)
        if oldIdentity != newIdentity { try discard(identity: oldIdentity) }
    }

    private func read(at url: URL) -> ShotRecoveryRecord? {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(ShotRecoveryRecord.self, from: data),
              (try? ShotListStore.data(for: record.document)) != nil else { return nil }
        return record
    }
}

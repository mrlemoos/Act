import Foundation
import CryptoKit

public struct Shot: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var sceneID: String
    public var framing: String
    public var action: String
    public var cameraMovement: String
    public var rationale: String

    public init(id: UUID = UUID(), sceneID: String, framing: String = "", action: String = "", cameraMovement: String = "", rationale: String = "") {
        self.id = id
        self.sceneID = sceneID
        self.framing = framing
        self.action = action
        self.cameraMovement = cameraMovement
        self.rationale = rationale
    }
}

public struct SceneAnchor: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var heading: String
    public var fingerprint: String

    public init(id: String, heading: String, text: String) {
        self.id = id
        self.heading = heading
        self.fingerprint = Self.digest(text)
    }

    public static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum SceneLinkState: Equatable, Sendable {
    case current
    case changed
    case missing
}

public struct ShotListDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var title: String
    public var screenplayName: String?
    public var sourceFingerprint: String
    public var anchors: [SceneAnchor]
    public var shots: [Shot]

    public init(title: String = "Untitled shot list", screenplayName: String? = nil, source: String, anchors: [SceneAnchor] = [], shots: [Shot] = []) {
        self.version = Self.currentVersion
        self.title = title
        self.screenplayName = screenplayName
        self.sourceFingerprint = SceneAnchor.digest(source)
        self.anchors = anchors
        self.shots = shots
    }

    public func linkState(for sceneID: String, currentScenes: [SceneAnchor]) -> SceneLinkState {
        guard let current = currentScenes.first(where: { $0.id == sceneID }) else { return .missing }
        guard let saved = anchors.first(where: { $0.id == sceneID }), saved.fingerprint == current.fingerprint else { return .changed }
        return .current
    }

    /// Accept new scene text only when the user explicitly regenerates or acknowledges the revision.
    public mutating func acknowledge(_ anchor: SceneAnchor) {
        anchors.removeAll { $0.id == anchor.id }
        anchors.append(anchor)
    }

    public mutating func replaceShots(for anchor: SceneAnchor, with replacements: [Shot]) throws {
        guard replacements.allSatisfy({ $0.sceneID == anchor.id }) else { throw ShotListError.wrongScene }
        let retained = shots.filter { $0.sceneID != anchor.id }
        let resultingIDs = retained.map(\.id) + replacements.map(\.id)
        guard Set(resultingIDs).count == resultingIDs.count else { throw ShotListError.duplicateShots }
        shots.removeAll { $0.sceneID == anchor.id }
        shots.append(contentsOf: replacements)
        acknowledge(anchor)
    }
}

public enum ShotListError: LocalizedError {
    case unsupportedVersion(Int)
    case duplicateShots
    case duplicateScenes
    case wrongScene

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This shot list uses unsupported format version \(version). Your existing file has not been changed."
        case .duplicateShots: "This shot list contains duplicate shot identifiers."
        case .duplicateScenes: "This shot list contains duplicate scene identifiers."
        case .wrongScene: "Generated shots do not belong to the selected scene."
        }
    }
}

public enum ShotListStore {
    public static func data(for document: ShotListDocument) throws -> Data {
        try validate(document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    public static func read(from url: URL) throws -> ShotListDocument {
        try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> ShotListDocument {
        let document = try JSONDecoder().decode(ShotListDocument.self, from: data)
        try validate(document)
        return document
    }

    public static func write(_ document: ShotListDocument, to url: URL) throws {
        try data(for: document).write(to: url, options: .atomic)
    }

    private static func validate(_ document: ShotListDocument) throws {
        guard document.version == ShotListDocument.currentVersion else { throw ShotListError.unsupportedVersion(document.version) }
        guard Set(document.shots.map(\.id)).count == document.shots.count else { throw ShotListError.duplicateShots }
        guard Set(document.anchors.map(\.id)).count == document.anchors.count else { throw ShotListError.duplicateScenes }
        guard document.shots.allSatisfy({ shot in document.anchors.contains(where: { $0.id == shot.sceneID }) }) else { throw ShotListError.wrongScene }
    }
}

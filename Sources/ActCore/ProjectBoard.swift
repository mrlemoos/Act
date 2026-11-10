import Foundation

public struct BoardPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double = 0, y: Double = 0) { self.x = x; self.y = y }
}

public struct BoardCard: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case draft, scene, note, characters, shots }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var text: String
    public var position: BoardPoint
    public var groupID: UUID?
    /// Asset provenance always points to the original draft card, including shared assets.
    public var draftID: UUID?
    public var sharedWith: [UUID]
    public var path: String?
    public var anchor: SceneAnchor?
    public init(kind: Kind, title: String, position: BoardPoint = BoardPoint(), draftID: UUID? = nil, path: String? = nil, anchor: SceneAnchor? = nil) {
        id = UUID(); self.kind = kind; self.title = title; text = ""; self.position = position
        self.draftID = draftID; self.path = path; self.anchor = anchor; sharedWith = []
    }
}

public struct BoardGroup: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var position: BoardPoint
    public init(title: String, position: BoardPoint = BoardPoint()) {
        id = UUID(); self.title = title; self.position = position
    }
}

public struct ProjectBoard: Codable, Equatable, Sendable {
    public var version = 1
    public var cards: [BoardCard] = []
    public var groups: [BoardGroup] = []
    public var pan = BoardPoint(x: 80, y: 80)
    public var zoom: Double = 1
    public init() {}

    public mutating func navigate(by delta: BoardPoint, magnification factor: Double = 1, around point: BoardPoint = BoardPoint()) {
        guard delta.x.isFinite, delta.y.isFinite, factor.isFinite, factor > 0, point.x.isFinite, point.y.isFinite else { return }
        if factor != 1 {
            let next = min(2, max(0.25, zoom * factor))
            pan.x = point.x - (point.x - pan.x) * next / zoom
            pan.y = point.y - (point.y - pan.y) * next / zoom
            zoom = next
        } else { pan.x += delta.x; pan.y += delta.y }
    }
    public mutating func moveCard(_ id: UUID, by delta: BoardPoint) {
        guard let i = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[i].position.x += delta.x; cards[i].position.y += delta.y
    }
    public mutating func moveGroup(_ id: UUID, by delta: BoardPoint) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].position.x += delta.x; groups[i].position.y += delta.y
        for index in cards.indices where cards[index].groupID == id {
            cards[index].position.x += delta.x; cards[index].position.y += delta.y
        }
    }
    public mutating func removeCard(_ id: UUID) {
        // Retain dependent references; missing provenance must never attach to another draft.
        cards.removeAll { $0.id == id }
    }
    public func resolvedURL(for card: BoardCard) -> URL? {
        if let path = card.path { return URL(fileURLWithPath: path) }
        return cards.first(where: { $0.id == card.draftID }).flatMap { $0.path }.map { URL(fileURLWithPath: $0) }
    }
    public func sceneState(for card: BoardCard, source: String) -> SceneLinkState {
        guard let anchor = card.anchor,
              let current = FountainParser.parse(source).scenes.first(where: { $0.id == anchor.id }) else { return .missing }
        return SceneAnchor.digest(current.text) == anchor.fingerprint ? .current : .changed
    }
    public func validated() throws -> Self {
        let ids = cards.map(\.id) + groups.map(\.id)
        guard version == 1, Set(ids).count == ids.count,
              zoom.isFinite, (0.25...2).contains(zoom), Self.finite(pan),
              cards.allSatisfy({ Self.finite($0.position) && ($0.path == nil || $0.path!.hasPrefix("/")) }),
              groups.allSatisfy({ Self.finite($0.position) }),
              cards.allSatisfy({ card in
                  (card.groupID == nil || groups.contains { $0.id == card.groupID }) &&
                  (card.kind != .scene || card.anchor != nil)
              }) else { throw BoardError.invalid }
        return self
    }
    private static func finite(_ point: BoardPoint) -> Bool { point.x.isFinite && point.y.isFinite }
}

public enum BoardError: LocalizedError {
    case invalid
    public var errorDescription: String? { "This project board contains unsupported or invalid data. Existing files are preserved." }
}

public enum ProjectBoardStore {
    public static func data(_ board: ProjectBoard) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(board.validated())
    }
    public static func load(_ data: Data) throws -> ProjectBoard {
        try JSONDecoder().decode(ProjectBoard.self, from: data).validated()
    }
}

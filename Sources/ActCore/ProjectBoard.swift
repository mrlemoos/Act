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
    public var errorDescription: String? { L10n.string("This project board contains unsupported or invalid data. Existing files are preserved.", table: "Board") }
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

public enum BoardWorkspaceTarget: Equatable, Sendable {
    case screenplay
    case characters
    case shots
}

public struct BoardOpenPlan: Equatable, Sendable {
    public var screenplayURL: URL
    public var workspace: BoardWorkspaceTarget
    public var sceneID: String?
    public var shotListURL: URL?
}

extension ProjectBoard {
    public func linkedSceneIDs(for draftID: UUID) -> Set<String> {
        Set(cards.filter { $0.kind == .scene && $0.draftID == draftID }.compactMap(\.anchor?.id))
    }

    public func draftFileName(for card: BoardCard) -> String? {
        if let path = card.path { return URL(fileURLWithPath: path).lastPathComponent }
        return cards.first(where: { $0.id == card.draftID })?.path.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func openPlan(for card: BoardCard) -> BoardOpenPlan? {
        guard card.kind != .note else { return nil }
        let owner = cards.first { $0.id == card.draftID }
        let screenplayURL: URL?
        switch card.kind {
        case .draft: screenplayURL = resolvedURL(for: card)
        case .shots: screenplayURL = owner.flatMap { resolvedURL(for: $0) }
        case .characters, .scene: screenplayURL = owner.flatMap { resolvedURL(for: $0) }
        case .note: return nil
        }
        guard let screenplayURL else { return nil }
        let workspace: BoardWorkspaceTarget = switch card.kind {
        case .characters: .characters
        case .shots: .shots
        default: .screenplay
        }
        return BoardOpenPlan(screenplayURL: screenplayURL, workspace: workspace,
            sceneID: card.kind == .scene ? card.anchor?.id : nil,
            shotListURL: card.kind == .shots ? card.path.map(URL.init(fileURLWithPath:)) : nil)
    }

    public func linkedSceneSelection(for card: BoardCard, source: String) -> String? {
        guard card.kind == .scene, sceneState(for: card, source: source) == .current else { return nil }
        return card.anchor?.id
    }

    public mutating func toggleSharedReference(assetID: UUID, draftID: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == assetID }),
              cards[index].kind == .characters || cards[index].kind == .shots,
              cards[index].draftID != draftID,
              cards.contains(where: { $0.id == draftID && $0.kind == .draft }) else { return }
        if cards[index].sharedWith.contains(draftID) { cards[index].sharedWith.removeAll { $0 == draftID } }
        else { cards[index].sharedWith.append(draftID) }
    }

    public mutating func relinkPath(_ path: String, for cardID: UUID) {
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        cards[index].path = path
        if cards[index].kind == .draft { cards[index].title = URL(fileURLWithPath: path).lastPathComponent }
    }

    public func characterPreviewImageURL(for card: BoardCard, fileManager: FileManager = .default) -> URL? {
        guard card.kind == .characters, let screenplay = resolvedURL(for: card) else { return nil }
        let directory = CharacterLibraryStore.directory(for: screenplay)
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("characters.json")),
              let library = try? CharacterLibraryStore.decode(data),
              let version = library.characters.compactMap(\.activeVersion).first,
              CharacterLibraryStore.safeImagePath(version.imageFile) else { return nil }
        let libraryRoot = directory.resolvingSymlinksInPath()
        let imageURL = directory.appendingPathComponent(version.imageFile).resolvingSymlinksInPath()
        let imagesRoot = libraryRoot.appendingPathComponent("images")
        guard imageURL.path.hasPrefix(imagesRoot.path + "/"),
              let size = try? imageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 25_165_824,
              fileManager.fileExists(atPath: imageURL.path) else { return nil }
        return imageURL
    }
}

/// Localised board labels never alter stored card kinds, titles or references.
public enum BoardPresentation {
    public static func defaultAssetTitle(_ kind: BoardCard.Kind, locale: String? = nil) -> String {
        switch kind {
        case .characters: L10n.string("Character sheets", table: "Board", locale: locale)
        case .shots: L10n.string("Shot list", table: "Board", locale: locale)
        default: kindTitle(kind, locale: locale)
        }
    }

    public static func defaultNoteTitle(locale: String? = nil) -> String {
        L10n.string("Untitled beat", table: "Board", locale: locale)
    }

    public static func defaultGroupTitle(locale: String? = nil) -> String {
        L10n.string("Untitled group", table: "Board", locale: locale)
    }

    public static func kindTitle(_ kind: BoardCard.Kind, locale: String? = nil) -> String {
        let key: String
        switch kind {
        case .draft: key = "Draft"
        case .scene: key = "Scene"
        case .note: key = "Note"
        case .characters: key = "Characters"
        case .shots: key = "Shots"
        }
        return L10n.string(key, table: "Board", locale: locale)
    }

    public static func sceneCount(_ count: Int, locale: String? = nil) -> String {
        L10n.format("%lld scenes", count, table: "Board", locale: locale)
    }

    public static func sharedDraftCount(_ count: Int, locale: String? = nil) -> String {
        L10n.format("Shared reference · %lld other drafts", count, table: "Board", locale: locale)
    }
}

import Foundation

public struct FountainOutlineEntry: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case section, scene, synopsis }
    public let id: String
    public let kind: Kind
    public let text: String
    /// The exact UTF-16 source line range, including its Fountain prefix.
    public let range: NSRange
    public let depth: Int
    public let parentID: String?
    /// Only heading entries identify a screenplay scene. Synopsis bodies do not.
    public let sceneID: String?
}

public enum FountainOutline {
    public static func entries(in screenplay: FountainScreenplay) -> [FountainOutlineEntry] {
        let scenes = Dictionary(uniqueKeysWithValues: screenplay.scenes.map { ($0.range.location, $0) })
        var result: [FountainOutlineEntry] = []
        var sections: [FountainOutlineEntry] = []
        var owner: FountainOutlineEntry?
        for element in screenplay.elements {
            let text = (element.presentationText ?? element.text).trimmingCharacters(in: .whitespaces)
            switch element.kind {
            case .section:
                let level = text.prefix(while: { $0 == "#" }).count
                let depth = max(0, level - 1)
                sections.removeAll { $0.depth >= depth }
                let entry = FountainOutlineEntry(id: "section:\(element.range.location)", kind: .section,
                    text: String(text.dropFirst(level)).trimmingCharacters(in: .whitespaces), range: element.range,
                    depth: depth, parentID: sections.last?.id, sceneID: nil)
                result.append(entry)
                sections.append(entry)
                owner = entry
            case .sceneHeading:
                guard let scene = scenes[element.range.location] else { continue }
                let entry = FountainOutlineEntry(id: "scene:\(scene.id)", kind: .scene, text: scene.heading,
                    range: element.range, depth: sections.last.map { $0.depth + 1 } ?? 0,
                    parentID: sections.last?.id, sceneID: scene.id)
                result.append(entry)
                owner = entry
            case .synopsis:
                result.append(FountainOutlineEntry(id: "synopsis:\(element.range.location)", kind: .synopsis,
                    text: String(text.dropFirst()).trimmingCharacters(in: .whitespaces), range: element.range,
                    depth: owner.map { $0.depth + 1 } ?? 0, parentID: owner?.id, sceneID: nil))
            default: break
            }
        }
        return result
    }
}

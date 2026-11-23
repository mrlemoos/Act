import Foundation

/// The versioned automation wire format. No Foundation objects cross the process boundary.
public enum AutomationValue: Codable, Equatable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([Self]), object([String: Self])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var array: [Self]? { if case .array(let v) = self { v } else { nil } }
    public var object: [String: Self]? { if case .object(let v) = self { v } else { nil } }
    public subscript(_ key: String) -> Self { object?[key] ?? .null }
    public static func encoded<T: Encodable>(_ value: T) throws -> Self {
        try JSONDecoder().decode(Self.self, from: JSONEncoder().encode(value))
    }
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
    public func data(pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public struct AutomationRequest: Codable, Equatable, Sendable {
    public var version: Int
    public var requestID: String
    public var operation: String
    public var documentID: String?
    public var expectedRevision: String?
    public var parameters: [String: AutomationValue]
    public init(version: Int = 1, requestID: String = UUID().uuidString, operation: String,
                documentID: String? = nil, expectedRevision: String? = nil, parameters: [String: AutomationValue] = [:]) {
        self.version = version; self.requestID = requestID; self.operation = operation
        self.documentID = documentID; self.expectedRevision = expectedRevision; self.parameters = parameters
    }
}

public struct AutomationFailure: Error, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
}

public struct AutomationEdit: Codable, Equatable, Sendable {
    public var kind: String
    public var sceneID: String
    public var match: String?
    public var text: String?
    public var side: String?
    public var destinationSceneID: String?
    public var destinationAnchor: String?
    public var destinationSide: String?
}

public struct AutomationChange: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var operationID: UUID
    public var batchID: String
    public var kind: String
    public var role: String
    public var location: Int
    public var before: String
    public var after: String
    public var conflicted = false
    public var dismissed = false
    public var reverted = false
    public var accepted: Bool?
    public var createdAt = Date()
    public var range: NSRange { NSRange(location: location, length: (after as NSString).length) }
    public init(operationID: UUID, batchID: String, kind: String, role: String, location: Int, before: String, after: String) {
        self.operationID = operationID; self.batchID = batchID; self.kind = kind; self.role = role
        self.location = location; self.before = before; self.after = after
    }
}

public struct AutomationPreview: Codable, Sendable {
    public var id: String
    public var revision: String
    public var sourceFingerprint: String
    public var changes: [AutomationChange]
    public var result: String
}

public enum AutomationEditing {
    /// `$document` explicitly addresses title metadata or an empty screenplay.
    public static func match(_ value: String, sceneID: String, source: String, screenplay: FountainScreenplay? = nil) throws -> NSRange {
        let ns = source as NSString
        let scope: NSRange
        if sceneID == "$document" { scope = NSRange(location: 0, length: ns.length) }
        else {
            guard let scene = (screenplay ?? FountainParser.parse(source)).scenes.first(where: { $0.id == sceneID }) else {
                throw AutomationFailure("missing_anchor", "Scene no longer exists. Read source again.")
            }
            scope = scene.range
        }
        guard !value.isEmpty else { throw AutomationFailure("invalid_parameters", "An exact non-empty match is required.") }
        var hits: [NSRange] = [], start = scope.location
        while start <= NSMaxRange(scope) {
            let hit = ns.range(of: value, options: .literal, range: NSRange(location: start, length: NSMaxRange(scope) - start))
            if hit.location == NSNotFound { break }
            hits.append(hit)
            if hits.count > 1 { throw AutomationFailure("ambiguous_anchor", "Text matches more than once. Supply a larger exact anchor.") }
            start = hit.location + 1
        }
        guard let hit = hits.first else { throw AutomationFailure("missing_anchor", "Exact text was not found in the requested scene.") }
        return hit
    }

    public static func preview(source: String, revision: String, edits: [AutomationEdit]) throws -> AutomationPreview {
        guard !edits.isEmpty, edits.count <= 500 else { throw AutomationFailure("invalid_parameters", "Supply 1–500 edits.") }
        let batch = UUID().uuidString
        let screenplay = FountainParser.parse(source)
        var changes: [AutomationChange] = []
        func point(_ range: NSRange, _ side: String?) throws -> Int {
            guard side == "before" || side == "after" else { throw AutomationFailure("invalid_parameters", "Insertion side must be before or after.") }
            return side == "before" ? range.location : NSMaxRange(range)
        }
        for edit in edits {
            let operationID = UUID()
            if edit.kind == "insert", source.isEmpty, edit.sceneID == "$document", edit.match == "" {
                guard let text = edit.text, !text.isEmpty else { throw AutomationFailure("invalid_parameters", "Insertion text is required.") }
                changes.append(.init(operationID: operationID, batchID: batch, kind: "insert", role: "destination", location: 0, before: "", after: text))
                continue
            }
            let range = try match(edit.match ?? "", sceneID: edit.sceneID, source: source, screenplay: screenplay)
            switch edit.kind {
            case "insert":
                guard let text = edit.text, !text.isEmpty else { throw AutomationFailure("invalid_parameters", "Insertion text is required.") }
                changes.append(.init(operationID: operationID, batchID: batch, kind: "insert", role: "destination", location: try point(range, edit.side), before: "", after: text))
            case "replace", "remove":
                guard edit.kind == "remove" || edit.text != nil else { throw AutomationFailure("invalid_parameters", "Replacement text is required.") }
                let after = edit.kind == "remove" ? "" : edit.text!
                guard !after.isLiterallyEqual(to: edit.match!) else { throw AutomationFailure("invalid_parameters", "Edit would not change source.") }
                changes.append(.init(operationID: operationID, batchID: batch, kind: edit.kind, role: "source", location: range.location, before: edit.match!, after: after))
            case "move":
                let destination = try match(edit.destinationAnchor ?? "", sceneID: edit.destinationSceneID ?? edit.sceneID, source: source, screenplay: screenplay)
                let location = try point(destination, edit.destinationSide)
                guard location < range.location || location > NSMaxRange(range) else { throw AutomationFailure("invalid_parameters", "A move cannot target its own source.") }
                changes.append(.init(operationID: operationID, batchID: batch, kind: "move", role: "origin", location: range.location, before: edit.match!, after: ""))
                changes.append(.init(operationID: operationID, batchID: batch, kind: "move", role: "destination", location: location, before: "", after: edit.match!))
            default: throw AutomationFailure("invalid_parameters", "Unknown edit kind: \(edit.kind)")
            }
        }
        return try resolve(source: source, revision: revision, changes: changes, batchID: batch)
    }

    public static func resolve(source: String, revision: String, changes: [AutomationChange], batchID: String = UUID().uuidString) throws -> AutomationPreview {
        let sorted = changes.sorted { $0.location < $1.location }
        let ns = source as NSString
        for (index, change) in sorted.enumerated() {
            let range = NSRange(location: change.location, length: (change.before as NSString).length)
            guard range.location >= 0, NSMaxRange(range) <= ns.length,
                  ns.substring(with: range).isLiterallyEqual(to: change.before) else { throw AutomationFailure("revision_conflict", "Source no longer matches the edit.") }
            if index > 0 {
                let previous = sorted[index - 1]
                guard previous.location + (previous.before as NSString).length < change.location else {
                    throw AutomationFailure("overlapping_edits", "Changes overlap or share a boundary. Combine them into one edit.")
                }
            }
        }
        let result = NSMutableString(string: source)
        for change in sorted.reversed() {
            result.replaceCharacters(in: NSRange(location: change.location, length: (change.before as NSString).length), with: change.after)
        }
        var delta = 0
        let final = sorted.map { original in
            var change = original
            change.location += delta; change.batchID = batchID
            delta += (change.after as NSString).length - (change.before as NSString).length
            return change
        }
        return .init(id: batchID, revision: revision, sourceFingerprint: SceneAnchor.digest(source), changes: final, result: result as String)
    }

    public static func difference(from old: String, to new: String) -> (range: NSRange, replacementLength: Int) {
        let old = old as NSString, new = new as NSString
        var prefix = 0, suffix = 0
        while prefix < min(old.length, new.length), old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        while suffix < min(old.length, new.length) - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        return (NSRange(location: prefix, length: old.length - prefix - suffix), new.length - prefix - suffix)
    }
}

public struct AutomationReviewLedger: Codable, Sendable {
    public var version = 1
    public var sourceFingerprint = ""
    public var changes: [AutomationChange] = []
    public init() {}
    public mutating func reconcile(from old: String, to new: String) {
        let diff = AutomationEditing.difference(from: old, to: new)
        rebase(through: diff.range, replacementLength: diff.replacementLength)
        sourceFingerprint = SceneAnchor.digest(new)
    }
    public mutating func rebase(through edit: NSRange, replacementLength: Int) {
        for index in changes.indices where !changes[index].reverted {
            let range = changes[index].range
            if NSMaxRange(edit) <= range.location && !(range.length == 0 && edit.length == 0 && edit.location == range.location) {
                changes[index].location += replacementLength - edit.length
            } else if edit.location < NSMaxRange(range) || (range.length == 0 && edit.location <= range.location) {
                changes[index].conflicted = true
            }
        }
    }
    public mutating func verify(source: String) {
        if sourceFingerprint != SceneAnchor.digest(source) {
            for index in changes.indices { changes[index].conflicted = true }
        }
        sourceFingerprint = SceneAnchor.digest(source)
    }
}

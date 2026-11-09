import Foundation

/// Keeps the UTF-8 byte order marker separate from the editable screenplay.
public struct DocumentText: Equatable, Sendable {
    public var source: String
    public var hasByteOrderMarker: Bool

    public init(source: String = "", hasByteOrderMarker: Bool = false) {
        self.source = source
        self.hasByteOrderMarker = hasByteOrderMarker
    }

    public init(data: Data) throws {
        let marker = Data([0xEF, 0xBB, 0xBF])
        hasByteOrderMarker = data.starts(with: marker)
        let content = hasByteOrderMarker ? data.dropFirst(3) : data[...]
        guard let decoded = String(data: content, encoding: .utf8) else {
            throw DocumentError.invalidUTF8
        }
        source = decoded
    }

    public var data: Data {
        var result = hasByteOrderMarker ? Data([0xEF, 0xBB, 0xBF]) : Data()
        result.append(contentsOf: source.utf8)
        return result
    }
}

public enum DocumentError: LocalizedError, Sendable {
    case invalidUTF8
    case externalChange

    public var errorDescription: String? {
        switch self {
        case .invalidUTF8: "This Fountain file is not valid UTF-8."
        case .externalChange: "This file changed outside Act. Your writing has not been overwritten."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidUTF8: "Save a UTF-8 copy in the original application, then open that copy."
        case .externalChange: "Use Save As to keep your version separately, or reload the file to use the external version."
        }
    }
}

/// Comparison is byte based so same-size edits and timestamp collisions are detected.
public struct DocumentFileSnapshot: Sendable {
    public var data: Data
    public init(data: Data) { self.data = data }

    public func checkUnchanged(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DocumentError.externalChange
        }
        guard try Data(contentsOf: url) == data else {
            throw DocumentError.externalChange
        }
    }
}

import Foundation

public enum AutomationContract {
    public static func schema() throws -> AutomationValue {
        guard let url = Bundle.module.url(forResource: "automation-v1", withExtension: "json") else { throw AutomationFailure("missing_contract", "Automation contract resource is missing.") }
        return try JSONDecoder().decode(AutomationValue.self, from: Data(contentsOf: url))
    }

    public static func validate(_ request: AutomationRequest) throws {
        let definition = try schema()["operations"][request.operation]
        guard definition.object != nil else { throw AutomationFailure("unknown_operation", "Use schema to discover operations.") }
        try validate(.object(request.parameters), against: definition["parameters"], path: "parameters")
        if let revision = definition["revision"].string, revision != "none" {
            guard request.documentID != nil, request.expectedRevision != nil else { throw AutomationFailure("invalid_parameters", "This operation requires documentID and expectedRevision (\(revision)).") }
        }
    }

    private static func validate(_ value: AutomationValue, against schema: AutomationValue, path: String) throws {
        func invalid(_ message: String) -> AutomationFailure { .init("invalid_parameters", "\(path): \(message)") }
        if let fixed = schema.object?["const"], fixed != value { throw invalid("Unexpected value.") }
        if let values = schema["enum"].array, !values.contains(value) { throw invalid("Unsupported value.") }
        switch schema["type"].string {
        case "object":
            guard let object = value.object else { throw invalid("Expected an object.") }
            let properties = schema["properties"].object ?? [:]
            for key in schema["required"].array?.compactMap(\.string) ?? [] where object[key] == nil { throw invalid("Missing \(key).") }
            for (key, item) in object {
                guard let child = properties[key] else {
                    if schema["additionalProperties"].bool == false { throw invalid("Unknown parameter \(key).") }; continue
                }
                try validate(item, against: child, path: path + "." + key)
            }
        case "array":
            guard let array = value.array else { throw invalid("Expected an array.") }
            if case .number(let limit) = schema["maxItems"], array.count > Int(limit) { throw invalid("Too many items.") }
            if case .number(let limit) = schema["minItems"], array.count < Int(limit) { throw invalid("Too few items.") }
            for item in array { try validate(item, against: schema["items"], path: path + "[]") }
        case "string":
            guard let text = value.string else { throw invalid("Expected a string.") }
            if case .number(let limit) = schema["minLength"], text.count < Int(limit) { throw invalid("String is too short.") }
        case "boolean": if value.bool == nil { throw invalid("Expected a boolean.") }
        default: break
        }
    }
}

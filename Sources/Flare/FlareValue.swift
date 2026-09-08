import Foundation

/// JSON data that can safely cross Swift concurrency boundaries.
public enum FlareValue: Sendable, Equatable, Codable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case array([FlareValue])
    case object([String: FlareValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Int64.self) {
            self = .integer(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .double(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([FlareValue].self) {
            self = .array(value)
            return
        }
        self = .object(try container.decode([String: FlareValue].self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension FlareValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension FlareValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) { self = .integer(value) }
}

extension FlareValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension FlareValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension FlareValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FlareValue...) { self = .array(elements) }
}

extension FlareValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, FlareValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, new in new }))
    }
}

extension FlareValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

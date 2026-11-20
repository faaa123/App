import Foundation

/// Untyped JSON, so stored data can be parsed leniently field by field (like
/// Dart's `jsonDecode`) instead of failing as a whole.
public enum JSONValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public var intValue: Int? { if case .int(let v) = self { v } else { nil } }
    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    public var arrayValue: [JSONValue]? { if case .array(let v) = self { v } else { nil } }
    public var objectValue: [String: JSONValue]? { if case .object(let v) = self { v } else { nil } }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}

extension JSONValue: Codable {
    public init(from decoder: any Decoder) throws {
        if var a = try? decoder.unkeyedContainer() {
            var out: [JSONValue] = []
            while !a.isAtEnd { out.append(try a.decode(JSONValue.self)) }
            self = .array(out)
            return
        }
        if let o = try? decoder.container(keyedBy: AnyKey.self) {
            var out: [String: JSONValue] = [:]
            for k in o.allKeys { out[k.stringValue] = try o.decode(JSONValue.self, forKey: k) }
            self = .object(out)
            return
        }
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .null:
            var c = encoder.singleValueContainer(); try c.encodeNil()
        case .bool(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .int(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .double(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .string(let v):
            var c = encoder.singleValueContainer(); try c.encode(v)
        case .array(let v):
            var c = encoder.unkeyedContainer()
            for x in v { try c.encode(x) }
        case .object(let v):
            var c = encoder.container(keyedBy: AnyKey.self)
            for (k, x) in v { try c.encode(x, forKey: AnyKey(k)) }
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

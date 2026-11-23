import Foundation

/// The small part of GeoJSON the bundled files use: features with string
/// properties and (Multi)LineString / (Multi)Polygon geometry.
public struct GeoFeature: Sendable {
    public var properties: [String: String]
    /// Lines, or polygon rings (outer ring first, then holes; even-odd fill).
    public var parts: [[GeoPoint]]

    public init(properties: [String: String] = [:], parts: [[GeoPoint]]) {
        self.properties = properties
        self.parts = parts
    }
}

public enum GeoJSON {
    public enum DecodeError: Error, Equatable {
        case notAFeatureCollection
        case unsupportedGeometry(String)
    }

    public static func decode(_ data: Data) throws -> [GeoFeature] {
        let raw = try JSONDecoder().decode(RawCollection.self, from: data)
        guard raw.type == "FeatureCollection" else { throw DecodeError.notAFeatureCollection }
        return try raw.features.map { f in
            let parts: [[GeoPoint]]
            switch f.geometry.type {
            case "LineString":
                parts = [try f.geometry.coordinates.line()]
            case "MultiLineString", "Polygon":
                parts = try f.geometry.coordinates.lines()
            case "MultiPolygon":
                parts = try f.geometry.coordinates.list().flatMap { try $0.lines() }
            default:
                throw DecodeError.unsupportedGeometry(f.geometry.type)
            }
            return GeoFeature(properties: f.properties?.values ?? [:], parts: parts)
        }
    }
}

private struct RawCollection: Decodable {
    var type: String
    var features: [RawFeature]
}

private struct RawFeature: Decodable {
    var properties: StringProperties?
    var geometry: RawGeometry
}

private struct RawGeometry: Decodable {
    var type: String
    var coordinates: Nested
}

/// Keeps the string-valued properties and skips the rest.
private struct StringProperties: Decodable {
    var values: [String: String] = [:]

    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        for key in c.allKeys {
            if let s = try? c.decode(String.self, forKey: key) {
                values[key.stringValue] = s
            }
        }
    }
}

/// Arbitrarily nested coordinate arrays.
private indirect enum Nested: Decodable {
    case number(Double)
    case array([Nested])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else {
            self = .array(try c.decode([Nested].self))
        }
    }

    struct Malformed: Error {}

    func list() throws -> [Nested] {
        guard case .array(let a) = self else { throw Malformed() }
        return a
    }

    func point() throws -> GeoPoint {
        let a = try list()
        guard a.count >= 2, case .number(let lon) = a[0], case .number(let lat) = a[1] else { throw Malformed() }
        return GeoPoint(lon, lat)
    }

    func line() throws -> [GeoPoint] { try list().map { try $0.point() } }
    func lines() throws -> [[GeoPoint]] { try list().map { try $0.line() } }
}

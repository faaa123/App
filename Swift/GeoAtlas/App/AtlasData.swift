import Foundation
import GeoCore

/// The bundled GeoJSON, decoded once.
struct AtlasData: Sendable {
    struct River: Sendable {
        var name: String
        var lines: [[GeoPoint]]
    }

    var coastline: [[GeoPoint]] = []
    var borders: [[GeoPoint]] = []
    /// Polygon rings (even-odd).
    var land: [[GeoPoint]] = []
    var lakes: [[GeoPoint]] = []
    var rivers: [River] = []
    var plates: [PlateBoundaryKind: [[GeoPoint]]] = [:]
    /// Polygon rings per class (even-odd).
    var koppen: [KoppenClass: [[GeoPoint]]] = [:]

    enum LoadError: Error {
        case missing(String)
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> AtlasData {
        func features(_ name: String) throws -> [GeoFeature] {
            guard let url = bundle.url(forResource: name, withExtension: "geojson", subdirectory: "Geo") else {
                throw LoadError.missing(name)
            }
            return try GeoJSON.decode(Data(contentsOf: url))
        }
        var d = AtlasData()
        d.coastline = try features("coastline").flatMap(\.parts)
        d.borders = try features("borders").flatMap(\.parts)
        d.land = try features("land").flatMap(\.parts)
        d.lakes = try features("lakes").flatMap(\.parts)
        d.rivers = try features("rivers").map { River(name: $0.properties["name"] ?? "", lines: $0.parts) }
        for f in try features("plates") {
            if let kind = f.properties["kind"].flatMap(PlateBoundaryKind.init(rawValue:)) {
                d.plates[kind, default: []] += f.parts
            }
        }
        for f in try features("koppen") {
            if let c = f.properties["class"].flatMap(KoppenClass.init(rawValue:)) {
                d.koppen[c, default: []] += f.parts
            }
        }
        return d
    }
}

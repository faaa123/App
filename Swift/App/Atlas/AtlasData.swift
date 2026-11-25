import Foundation
import GeoCore

/// The bundled map data, decoded once.
struct AtlasData: Sendable {
    struct River: Sendable {
        var name: String
        var lines: [[GeoPoint]]
    }

    /// The 1:110m base map; finer levels load when zooming in
    /// (`loadDetail`).
    var base = BaseData()
    var rivers: [River] = []
    var plates: [PlateBoundaryKind: [[GeoPoint]]] = [:]
    /// Polygon rings per class (even-odd).
    var koppen: [KoppenClass: [[GeoPoint]]] = [:]

    enum LoadError: Error {
        case missing(String)
    }

    private static func url(_ name: String, _ ext: String, in bundle: Bundle) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Geo") else {
            throw LoadError.missing(name)
        }
        return url
    }

    /// The 1:50m or 1:10m base map (the fine level trims the climate fills
    /// with the 1:50m land, which is close enough at that zoom).
    static func loadDetail(_ detail: MapDetail, from bundle: Bundle = .main) throws -> BaseData {
        func features(_ name: String) throws -> [GeoFeature] {
            try GeoBinary.decode(Data(contentsOf: url(name, "geobin", in: bundle)))
        }
        let suffix = detail == .fine ? "10m" : "50m"
        return BaseData(
            coastline: try features("coastline_\(suffix)").flatMap(\.parts),
            borders: try features("borders_\(suffix)").flatMap(\.parts),
            lakes: try features("lakes_\(suffix)").map(\.parts),
            land: try features("land_50m").map(\.parts))
    }

    static func loadBundled(from bundle: Bundle = .main) throws -> AtlasData {
        func features(_ name: String) throws -> [GeoFeature] {
            try GeoJSON.decode(Data(contentsOf: url(name, "geojson", in: bundle)))
        }
        var d = AtlasData()
        d.base = BaseData(
            coastline: try features("coastline").flatMap(\.parts),
            borders: try features("borders").flatMap(\.parts),
            lakes: try features("lakes").map(\.parts),
            land: try features("land").map(\.parts))
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

import GeoCore
import SwiftUI

/// A label at each visible copy of its place, in map units.
struct PlacedLabel: Sendable {
    var text: String
    var points: [CGPoint]
}

/// A schematic arrow: one polyline per visible copy, in map units.
struct ArrowShape: Sendable {
    var copies: [[CGPoint]]
}

/// Everything drawn on the map, projected once per projection and central
/// meridian. Paths are in map units (y north); the view scales them.
struct ProjectedMap: Sendable {
    struct Belt: Sendable {
        var belt: PressureBelt
        var path: Path
        var labels: PlacedLabel
    }

    struct Wind: Sendable {
        var kind: WindKind
        var arrow: ArrowShape
    }

    struct Air: Sendable {
        var belts: [Belt]
        var winds: [Wind]
        var windLabels: [(WindKind, PlacedLabel)]
    }

    struct Current: Sendable {
        var current: OceanCurrent
        var arrow: ArrowShape
        var label: PlacedLabel
    }

    struct Orogeny: Sendable {
        var age: OrogenyAge
        /// Band width in map units.
        var width: CGFloat
        var path: Path
    }

    var halfExtent: CGSize
    /// Map units per degree of latitude near the equator.
    var unitsPerDegree: CGFloat
    var outline: Path
    var graticule: Path
    var equator: Path
    var tropics: Path

    var coastline: Path
    var borders: Path
    var land: Path
    var lakes: Path

    var plates: [(PlateBoundaryKind, Path)]
    var plateLabels: [PlacedLabel]
    var koppen: [(KoppenClass, Path)]
    var currents: [Current]
    var air: [Season: Air]
    var orogeny: [Orogeny]
    var ranges: [(MountainRange, Path, PlacedLabel)]
    var rivers: Path
    var riverLabels: [PlacedLabel]

    static func build(_ data: AtlasData, projector pj: MapProjector) -> ProjectedMap {
        let ext = pj.projection.halfExtent

        func path(_ lines: [[GeoPoint]], closed: Bool = false, step: Double = 2) -> Path {
            var p = Path()
            for line in pj.lines(lines, maxStep: step) {
                guard let first = line.first else { continue }
                p.move(to: CGPoint(x: first.x, y: first.y))
                for v in line.dropFirst() {
                    p.addLine(to: CGPoint(x: v.x, y: v.y))
                }
                if closed { p.closeSubpath() }
            }
            return p
        }
        func label(_ text: String, _ at: GeoPoint) -> PlacedLabel {
            PlacedLabel(text: text, points: pj.points(at).map { CGPoint(x: $0.x, y: $0.y) })
        }
        func arrow(_ points: [GeoPoint]) -> ArrowShape {
            ArrowShape(copies: pj.lines([points], maxStep: 1).map { $0.map { CGPoint(x: $0.x, y: $0.y) } })
        }

        var outline = Path()
        let ring = pj.projection.outline()
        outline.addLines(ring.map { CGPoint(x: $0.x, y: $0.y) })
        outline.closeSubpath()

        // Graticule every 30°, from the central meridian so it is symmetric.
        var gratLines: [[GeoPoint]] = []
        for k in -6...6 {
            let lon = pj.centralMeridian + 30 * Double(k)
            gratLines.append([GeoPoint(lon, -90), GeoPoint(lon, 90)])
        }
        for lat in [-60.0, -30, 30, 60] {
            gratLines.append([GeoPoint(-180, lat), GeoPoint(180, lat)])
        }
        let tropicLat = 23.44, polarLat = 66.56
        let tropics = [tropicLat, -tropicLat, polarLat, -polarLat].map { [GeoPoint(-180, $0), GeoPoint(180, $0)] }

        let air = Dictionary(uniqueKeysWithValues: Season.allCases.map { season in
            (season, Air(
                belts: GeoCore.Atmosphere.belts(season).map { b in
                    Belt(belt: b, path: path([b.ring], closed: true, step: 5),
                         labels: PlacedLabel(text: b.name, points: b.labels.flatMap { pj.points($0) }.map { CGPoint(x: $0.x, y: $0.y) }))
                },
                winds: GeoCore.Atmosphere.winds(season).map { Wind(kind: $0.kind, arrow: arrow([$0.from, $0.to])) },
                windLabels: GeoCore.Atmosphere.windLabels(season).map { ($0.0, label($0.0.name, $0.1)) }))
        })

        let perDegree = pj.projection.project(lambda: 0, phi: .pi / 180).y

        return ProjectedMap(
            halfExtent: CGSize(width: ext.x, height: ext.y),
            unitsPerDegree: perDegree,
            outline: outline,
            graticule: path(gratLines),
            equator: path([[GeoPoint(-180, 0), GeoPoint(180, 0)]]),
            tropics: path(tropics),
            coastline: path(data.coastline),
            borders: path(data.borders),
            land: path(data.land, closed: true),
            lakes: path(data.lakes, closed: true),
            plates: PlateBoundaryKind.allCases.map { ($0, path(data.plates[$0] ?? [])) },
            plateLabels: PlateNames.all.map { label($0.text, $0.at) },
            koppen: KoppenClass.allCases.map { ($0, path(data.koppen[$0] ?? [], closed: true, step: 5)) },
            currents: OceanCurrents.all.map { c in
                Current(current: c, arrow: arrow(c.path.smoothed()), label: label(c.name, c.labelPoint))
            },
            air: air,
            orogeny: Landforms.belts.map { b in
                Orogeny(age: b.age, width: perDegree * b.width, path: path([b.path.smoothed()], step: 1))
            },
            ranges: Landforms.ranges.map { r in
                (r, path([r.path.smoothed()], step: 1), label(r.name, r.labelPoint))
            },
            rivers: path(data.rivers.flatMap(\.lines)),
            riverLabels: data.rivers.compactMap { r in
                // Name the longest stretch at its middle.
                guard let line = r.lines.max(by: { $0.count < $1.count }), !line.isEmpty else { return nil }
                return label(r.name, line[line.count / 2])
            })
    }
}

import Foundation
import GeoCore
import SwiftUI
import UIKit

/// The map's MapLibre style: the white base map from the bundled 1:10m
/// GeoJSON (MapLibre cuts it into vector tiles per zoom, as web maps do)
/// and one set of layers per theme.
///
/// Layer ids carry what decides their visibility:
/// `<theme or base>.<season or all>.<label or shape>.<name>`.
enum AtlasStyle {
    struct LayerTag {
        var theme: Theme?
        var season: Season?
        var isLabel: Bool

        init?(id: String) {
            let parts = id.split(separator: ".")
            guard parts.count >= 4 else { return nil }
            theme = Theme(rawValue: String(parts[0]))
            season = Season(rawValue: String(parts[1]))
            isLabel = parts[2] == "label"
        }

        func isVisible(themes: Set<Theme>, season current: Season, labels: Bool) -> Bool {
            if let theme, !themes.contains(theme) { return false }
            if let season, season != current { return false }
            return labels || !isLabel
        }
    }

    /// The arrowhead icon (a template image, so MapLibre tints it).
    static let arrowhead = "arrowhead"

    static func arrowheadImage() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let p = UIBezierPath()
            p.move(to: CGPoint(x: 12, y: 2))
            p.addLine(to: CGPoint(x: 22, y: 22))
            p.addLine(to: CGPoint(x: 2, y: 22))
            p.close()
            UIColor.black.setFill()
            p.fill()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// Writes the style to Caches and returns its URL (MapLibre loads
    /// styles by URL; the style points at files in the app bundle).
    static func write(bundle: Bundle = .main) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: style(bundle: bundle))
        let url = URL.cachesDirectory.appending(path: "atlas-style.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Style

    static func style(bundle: Bundle) -> [String: Any] {
        let geo = bundle.resourceURL?.appending(path: "Geo") ?? URL(filePath: "/")
        func file(_ name: String) -> String { geo.appending(path: "\(name).geojson").absoluteString }

        var sources: [String: Any] = [
            "ocean": geojson(file("ocean")),
            "coastline": geojson(file("coastline")),
            "borders": geojson(file("borders")),
            "lakes": geojson(file("lakes")),
            "rivers": geojson(file("rivers")),
            "plates": geojson(file("plates")),
            "koppen": geojson(file("koppen")),
            "graticule": geojson(graticule()),
            "plateNames": geojson(PlateNames.all.map { point($0.at, ["name": $0.text]) }),
            "orogeny": geojson(Landforms.belts.map {
                line($0.path.smoothed(), ["young": $0.age == .young, "width": $0.width])
            }),
            "ranges": geojson(Landforms.ranges.map { line($0.path.smoothed(), ["name": $0.name]) }),
            "rangeNames": geojson(Landforms.ranges.map { point($0.labelPoint, ["name": $0.name]) }),
            "currents": geojson(OceanCurrents.all.map { line($0.path.smoothed(), ["warm": $0.warm]) }),
            "currentHeads": geojson(OceanCurrents.all.compactMap { head($0.path.smoothed(), ["warm": $0.warm]) }),
            "currentNames": geojson(OceanCurrents.all.map { point($0.labelPoint, ["name": $0.name, "warm": $0.warm]) }),
        ]
        for season in Season.allCases {
            let s = season.rawValue
            sources["belts-\(s)"] = geojson(Atmosphere.belts(season).map {
                polygon($0.ring, ["low": $0.kind == .low])
            })
            sources["beltNames-\(s)"] = geojson(Atmosphere.belts(season).flatMap { b in
                b.labels.map { point($0, ["name": b.name, "low": b.kind == .low]) }
            })
            let winds = Atmosphere.winds(season)
            sources["winds-\(s)"] = geojson(winds.map {
                line([$0.from, $0.to], ["monsoon": $0.kind == .monsoon])
            })
            sources["windHeads-\(s)"] = geojson(winds.compactMap {
                head([$0.from, $0.to], ["monsoon": $0.kind == .monsoon])
            })
            sources["windNames-\(s)"] = geojson(Atmosphere.windLabels(season).map {
                point($0.1, ["name": $0.0.name, "monsoon": $0.0 == .monsoon])
            })
        }

        return [
            "version": 8,
            "name": "白地図",
            // Latin glyphs only; Japanese is drawn with the system font
            // (MLNIdeographicFontFamilyName in Info.plist).
            "glyphs": geo.appending(path: "glyphs").absoluteString + "/{fontstack}/{range}.pbf",
            "sources": sources,
            "layers": layers(),
        ]
    }

    private static func layers() -> [[String: Any]] {
        var l: [[String: Any]] = []
        let paper = css(MapStyle.paper)

        l.append(["id": "base.all.shape.paper", "type": "background",
                  "paint": ["background-color": paper]])

        // Climate fills reach a little into the sea; the ocean, drawn over
        // them in paper white, trims them to the coast.
        var koppen: [Any] = ["match", ["get", "class"]]
        for c in KoppenClass.allCases {
            koppen += [c.rawValue, css(MapStyle.koppen(c))]
        }
        koppen.append("rgba(0,0,0,0)")
        l.append(["id": "climate.all.shape.koppen", "type": "fill", "source": "koppen",
                  "paint": ["fill-color": koppen]])
        l.append(["id": "base.all.shape.ocean", "type": "fill", "source": "ocean",
                  "paint": ["fill-color": paper, "fill-antialias": false]])
        l.append(["id": "base.all.shape.lakefill", "type": "fill", "source": "lakes",
                  "paint": ["fill-color": paper, "fill-antialias": false]])

        // Orogenic belts: bands a set number of degrees wide at every zoom.
        let pxPerDegree = 512.0 / 360
        l.append(["id": "landforms.all.shape.orogeny", "type": "line", "source": "orogeny",
                  "layout": ["line-cap": "round", "line-join": "round"],
                  "paint": [
                    "line-color": ["case", ["get", "young"],
                                   css(MapStyle.orogeny(.young)), css(MapStyle.orogeny(.old))],
                    "line-width": ["interpolate", ["exponential", 2], ["zoom"],
                                   0, ["max", 3, ["*", ["get", "width"], pxPerDegree]],
                                   12, ["*", ["get", "width"], pxPerDegree * 4096]],
                  ]])

        for season in Season.allCases {
            l.append(["id": "winds.\(season.rawValue).shape.belts", "type": "fill",
                      "source": "belts-\(season.rawValue)",
                      "paint": ["fill-color": ["case", ["get", "low"],
                                               css(MapStyle.pressure(.low)), css(MapStyle.pressure(.high))]]])
        }

        // Graticule: 30° lines, 10° lines when zoomed in, the tropics and
        // polar circles dashed, the equator darker.
        l.append(["id": "base.all.shape.grat10", "type": "line", "source": "graticule", "minzoom": 2.5,
                  "filter": ["==", ["get", "kind"], "10"],
                  "paint": ["line-color": css(MapStyle.graticule.opacity(0.6)), "line-width": 0.4]])
        l.append(["id": "base.all.shape.grat30", "type": "line", "source": "graticule",
                  "filter": ["==", ["get", "kind"], "30"],
                  "paint": ["line-color": css(MapStyle.graticule), "line-width": 0.5]])
        l.append(["id": "base.all.shape.tropics", "type": "line", "source": "graticule",
                  "filter": ["==", ["get", "kind"], "tropic"],
                  "paint": ["line-color": css(MapStyle.graticule), "line-width": 0.6, "line-dasharray": [5, 5]]])
        l.append(["id": "base.all.shape.equator", "type": "line", "source": "graticule",
                  "filter": ["==", ["get", "kind"], "equator"],
                  "paint": ["line-color": css(MapStyle.equator), "line-width": 0.7]])

        l.append(["id": "base.all.shape.borders", "type": "line", "source": "borders",
                  "paint": ["line-color": css(MapStyle.border), "line-width": 0.5]])
        l.append(["id": "base.all.shape.lakes", "type": "line", "source": "lakes",
                  "paint": ["line-color": css(MapStyle.coast), "line-width": 0.6]])
        l.append(["id": "base.all.shape.coastline", "type": "line", "source": "coastline",
                  "paint": ["line-color": css(MapStyle.coast), "line-width": 0.8]])

        let round: [String: Any] = ["line-cap": "round", "line-join": "round"]
        l.append(["id": "landforms.all.shape.rivers", "type": "line", "source": "rivers", "layout": round,
                  "paint": ["line-color": css(MapStyle.river), "line-width": 1.2]])
        l.append(["id": "landforms.all.shape.ranges", "type": "line", "source": "ranges", "layout": round,
                  "paint": ["line-color": css(MapStyle.range), "line-width": 3]])

        for k in PlateBoundaryKind.allCases {
            var paint: [String: Any] = ["line-color": css(MapStyle.plate(k)),
                                        "line-width": k == .convergent ? 3 : 2]
            // Dashes are in line widths.
            // Dashes keep square ends, so they stay apart.
            var layout = round
            if k == .transform {
                paint["line-dasharray"] = [2, 1.5]
                layout["line-cap"] = "butt"
            }
            l.append(["id": "plates.all.shape.\(k.rawValue)", "type": "line", "source": "plates",
                      "filter": ["==", ["get", "kind"], k.rawValue],
                      "layout": layout, "paint": paint])
        }

        let warm: [Any] = ["case", ["get", "warm"],
                           css(MapStyle.current(warm: true)), css(MapStyle.current(warm: false))]
        l.append(["id": "currents.all.shape.lines", "type": "line", "source": "currents", "layout": round,
                  "paint": ["line-color": warm, "line-width": 2.2]])
        l.append(arrowheads(id: "currents.all.shape.heads", source: "currentHeads", color: warm, size: 0.45))

        for season in Season.allCases {
            let s = season.rawValue
            let color: [Any] = ["case", ["get", "monsoon"],
                                css(MapStyle.wind(.monsoon)), css(MapStyle.wind(.westerly))]
            l.append(["id": "winds.\(s).shape.lines", "type": "line", "source": "winds-\(s)", "layout": round,
                      "paint": ["line-color": color,
                                "line-width": ["case", ["get", "monsoon"], 2.4, 1.6]]])
            l.append(arrowheads(id: "winds.\(s).shape.heads", source: "windHeads-\(s)", color: color, size: 0.35))
        }

        // Labels, least important first: MapLibre places the topmost
        // layer's labels first and drops any that would overlap.
        l.append(label(id: "landforms.all.label.rivers", source: "rivers",
                       color: css(MapStyle.river), alongLine: true))
        for season in Season.allCases {
            let s = season.rawValue
            l.append(label(id: "winds.\(s).label.winds", source: "windNames-\(s)",
                           color: ["case", ["get", "monsoon"],
                                   css(MapStyle.wind(.monsoon)), css(MapStyle.wind(.westerly))]))
        }
        l.append(label(id: "currents.all.label.names", source: "currentNames", color: warm, dy: -0.8))
        l.append(label(id: "landforms.all.label.ranges", source: "rangeNames",
                       color: css(MapStyle.range), bold: true, dy: 0.9))
        l.append(label(id: "plates.all.label.names", source: "plateNames",
                       color: css(Color(.secondaryLabel))))
        for season in Season.allCases {
            let s = season.rawValue
            l.append(label(id: "winds.\(s).label.belts", source: "beltNames-\(s)",
                           color: ["case", ["get", "low"],
                                   css(MapStyle.pressureText(.low)), css(MapStyle.pressureText(.high))],
                           bold: true))
        }
        return l
    }

    private static func arrowheads(id: String, source: String, color: Any, size: Double) -> [String: Any] {
        ["id": id, "type": "symbol", "source": source,
         "layout": ["icon-image": arrowhead, "icon-size": size,
                    "icon-rotate": ["get", "bearing"], "icon-rotation-alignment": "map",
                    "icon-allow-overlap": true, "icon-ignore-placement": true],
         "paint": ["icon-color": color]]
    }

    private static func label(id: String, source: String, color: Any, bold: Bool = false,
                              dy: Double = 0, alongLine: Bool = false) -> [String: Any] {
        var layout: [String: Any] = [
            "text-field": ["get", "name"],
            "text-font": ["geo"],
            "text-size": bold ? 13 : 12,
            "text-padding": 3,
        ]
        if alongLine {
            layout["symbol-placement"] = "line"
            layout["text-max-angle"] = 30
            layout["symbol-spacing"] = 400
        } else {
            layout["text-offset"] = [0, dy]
        }
        return ["id": id, "type": "symbol", "source": source, "layout": layout,
                "paint": ["text-color": color, "text-halo-color": css(MapStyle.labelHalo),
                          "text-halo-width": 1.5]]
    }

    // MARK: GeoJSON

    private static func geojson(_ url: String) -> [String: Any] {
        ["type": "geojson", "data": url,
         "attribution": "<a href=\"https://www.naturalearthdata.com\">Natural Earth</a>"]
    }

    private static func geojson(_ features: [[String: Any]]) -> [String: Any] {
        ["type": "geojson", "data": ["type": "FeatureCollection", "features": features]]
    }

    private static func coords(_ points: [GeoPoint]) -> [[Double]] {
        points.map { [$0.lon, $0.lat] }
    }

    private static func line(_ points: [GeoPoint], _ props: [String: Any]) -> [String: Any] {
        ["type": "Feature", "properties": props,
         "geometry": ["type": "LineString", "coordinates": coords(points)]]
    }

    private static func point(_ p: GeoPoint, _ props: [String: Any]) -> [String: Any] {
        var props = props
        if let name = props["name"] as? String { props["name"] = mapText(name) }
        return ["type": "Feature", "properties": props,
         "geometry": ["type": "Point", "coordinates": [p.lon, p.lat]]]
    }

    private static func polygon(_ ring: [GeoPoint], _ props: [String: Any]) -> [String: Any] {
        var closed = ring
        if let first = ring.first, ring.last != first { closed.append(first) }
        return ["type": "Feature", "properties": props,
                "geometry": ["type": "Polygon", "coordinates": [coords(closed)]]]
    }

    /// An arrowhead at the end of a line, turned along its last stretch as
    /// drawn on the (Mercator) map.
    private static func head(_ points: [GeoPoint], _ props: [String: Any]) -> [String: Any]? {
        guard let tip = points.last, points.count > 1 else { return nil }
        // A point a little way back, so a tiny last segment does not skew it.
        var back = points[points.count - 2]
        for p in points.reversed().dropFirst() where hypot(tip.lon - p.lon, tip.lat - p.lat) >= 1.5 {
            back = p
            break
        }
        func mercatorY(_ lat: Double) -> Double {
            let phi = min(max(lat, -85), 85) * .pi / 180
            return log(tan(.pi / 4 + phi / 2)) * 180 / .pi
        }
        let dx = tip.lon - back.lon
        let dy = mercatorY(tip.lat) - mercatorY(back.lat)
        var props = props
        props["bearing"] = atan2(dx, dy) * 180 / .pi
        return point(tip, props)
    }

    /// 30° and 10° lines, the tropics and polar circles, and the equator.
    private static func graticule() -> [[String: Any]] {
        var f: [[String: Any]] = []
        for lon in stride(from: -180, to: 180, by: 10) {
            let kind = lon % 30 == 0 ? "30" : "10"
            f.append(line([GeoPoint(Double(lon), -85), GeoPoint(Double(lon), 85)], ["kind": kind]))
        }
        for lat in stride(from: -80, through: 80, by: 10) where lat != 0 {
            let kind = lat % 30 == 0 ? "30" : "10"
            f.append(line([GeoPoint(-180, Double(lat)), GeoPoint(180, Double(lat))], ["kind": kind]))
        }
        for lat in [23.44, -23.44, 66.56, -66.56] {
            f.append(line([GeoPoint(-180, lat), GeoPoint(180, lat)], ["kind": "tropic"]))
        }
        f.append(line([GeoPoint(-180, 0), GeoPoint(180, 0)], ["kind": "equator"]))
        return f
    }

    /// Label text the map can draw: it renders CJK ideographs and kana
    /// with the system font and everything else from the bundled Latin
    /// glyphs, so full-width brackets and the like become their ASCII forms.
    static func mapText(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.map { u in
            (0xFF01...0xFF5E).contains(u.value) ? Unicode.Scalar(u.value - 0xFEE0) ?? u : u
        }))
    }

    // MARK: Colors

    /// A CSS color for the style, from a system color in the light
    /// appearance (the map is always an atlas's white paper).
    static func css(_ color: Color) -> String {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return "rgba(\(c(r)),\(c(g)),\(c(b)),\(String(format: "%.3f", a)))"
    }
}

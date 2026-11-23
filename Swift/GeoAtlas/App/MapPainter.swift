import GeoCore
import SwiftUI

/// Draws a projected map into a Canvas. Shapes are scaled by `transform`;
/// line widths and text stay the same size at every zoom.
struct MapPainter {
    var map: ProjectedMap
    var themes: Set<Theme>
    var season: Season
    var showLabels: Bool
    /// Map units → view points.
    var transform: CGAffineTransform
    var size: CGSize

    private var scale: CGFloat { transform.a }

    func draw(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(MapStyle.surround))
        let outline = map.outline.applying(transform)
        ctx.fill(outline, with: .color(MapStyle.paper))

        var c = ctx
        c.clip(to: outline)

        if themes.contains(.climate) { drawKoppen(&c) }
        if themes.contains(.landforms) { drawOrogeny(&c) }
        if themes.contains(.winds) { drawPressureBelts(&c) }

        c.stroke(map.graticule.applying(transform), with: .color(MapStyle.graticule), lineWidth: 0.5)
        c.stroke(map.tropics.applying(transform), with: .color(MapStyle.graticule),
                 style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
        c.stroke(map.equator.applying(transform), with: .color(MapStyle.equator), lineWidth: 0.7)

        c.stroke(map.borders.applying(transform), with: .color(MapStyle.border), lineWidth: 0.5)
        c.stroke(map.lakes.applying(transform), with: .color(MapStyle.coast), lineWidth: 0.6)
        c.stroke(map.coastline.applying(transform), with: .color(MapStyle.coast), lineWidth: 0.8)

        if themes.contains(.landforms) { drawRangesAndRivers(&c) }
        if themes.contains(.plates) {
            for (kind, path) in map.plates {
                c.stroke(path.applying(transform), with: .color(MapStyle.plate(kind)), style: MapStyle.plateStroke(kind))
            }
        }
        if themes.contains(.currents) {
            for cur in map.currents {
                drawArrow(&c, cur.arrow, color: MapStyle.current(warm: cur.current.warm), width: 2.2, head: 9)
            }
        }
        if themes.contains(.winds), let air = map.air[season] {
            for w in air.winds {
                drawArrow(&c, w.arrow, color: MapStyle.wind(w.kind), width: w.kind == .monsoon ? 2.4 : 1.6, head: 7)
            }
        }

        ctx.stroke(outline, with: .color(MapStyle.coast), lineWidth: 1)

        if showLabels { drawLabels(&c) }
    }

    // MARK: Layers

    private func drawKoppen(_ c: inout GraphicsContext) {
        c.drawLayer { layer in
            // The polygons reach a little into the sea; the coastline trims them.
            layer.clip(to: map.land.applying(transform), style: FillStyle(eoFill: true))
            for (cls, path) in map.koppen {
                layer.fill(path.applying(transform), with: .color(MapStyle.koppen(cls)), style: FillStyle(eoFill: true))
            }
        }
        c.fill(map.lakes.applying(transform), with: .color(MapStyle.paper))
    }

    private func drawOrogeny(_ c: inout GraphicsContext) {
        for o in map.orogeny {
            c.stroke(o.path.applying(transform), with: .color(MapStyle.orogeny(o.age)),
                     style: StrokeStyle(lineWidth: max(o.width * scale, 4), lineCap: .round, lineJoin: .round))
        }
    }

    private func drawPressureBelts(_ c: inout GraphicsContext) {
        guard let air = map.air[season] else { return }
        for b in air.belts {
            c.fill(b.path.applying(transform), with: .color(MapStyle.pressure(b.belt.kind)))
        }
    }

    private func drawRangesAndRivers(_ c: inout GraphicsContext) {
        c.stroke(map.rivers.applying(transform), with: .color(MapStyle.river),
                 style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        for (_, path, _) in map.ranges {
            c.stroke(path.applying(transform), with: .color(MapStyle.range),
                     style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
    }

    /// A polyline with a filled head at its end, per visible copy.
    private func drawArrow(_ c: inout GraphicsContext, _ arrow: ArrowShape, color: Color, width: CGFloat, head: CGFloat) {
        for copy in arrow.copies where copy.count > 1 {
            let pts = copy.map { $0.applying(transform) }
            guard let tip = pts.last else { continue }
            // Direction from a point a head's length back along the line.
            var back = pts[pts.count - 2]
            for p in pts.reversed() where hypot(tip.x - p.x, tip.y - p.y) >= head {
                back = p
                break
            }
            let len = hypot(tip.x - back.x, tip.y - back.y)
            guard len > 0 else { continue }
            let ux = (tip.x - back.x) / len, uy = (tip.y - back.y) / len
            let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)

            var line = Path()
            line.move(to: pts[0])
            for p in pts.dropFirst() {
                if hypot(p.x - tip.x, p.y - tip.y) < head * 0.8 { break }
                line.addLine(to: p)
            }
            line.addLine(to: base)
            c.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            var h = Path()
            h.move(to: tip)
            h.addLine(to: CGPoint(x: base.x - uy * head * 0.5, y: base.y + ux * head * 0.5))
            h.addLine(to: CGPoint(x: base.x + uy * head * 0.5, y: base.y - ux * head * 0.5))
            h.closeSubpath()
            c.fill(h, with: .color(color))
        }
    }

    // MARK: Labels

    private func drawLabels(_ c: inout GraphicsContext) {
        c.drawLayer { layer in
            // A paper-colored halo keeps names legible over lines and fills.
            layer.addFilter(.shadow(color: MapStyle.labelHalo, radius: 1.5))
            layer.addFilter(.shadow(color: MapStyle.labelHalo, radius: 1.5))
            if themes.contains(.plates) {
                for l in map.plateLabels {
                    place(&layer, l, Text(l.text).font(.caption2).foregroundStyle(Color(.secondaryLabel)))
                }
            }
            if themes.contains(.landforms) {
                for l in map.riverLabels {
                    place(&layer, l, Text(l.text).font(.caption2).foregroundStyle(MapStyle.river), dy: -8)
                }
                for (r, _, l) in map.ranges {
                    place(&layer, l, Text(r.name).font(.caption2.weight(.semibold)).foregroundStyle(MapStyle.range), dy: 10)
                }
            }
            if themes.contains(.currents) {
                for cur in map.currents {
                    place(&layer, cur.label, Text(cur.current.name).font(.caption2)
                        .foregroundStyle(MapStyle.current(warm: cur.current.warm)), dy: -9)
                }
            }
            if themes.contains(.winds), let air = map.air[season] {
                for b in air.belts {
                    place(&layer, b.labels, Text(b.belt.name).font(.caption2.weight(.semibold))
                        .foregroundStyle(MapStyle.pressureText(b.belt.kind)))
                }
                for (kind, l) in air.windLabels {
                    place(&layer, l, Text(kind.name).font(.caption2).foregroundStyle(MapStyle.wind(kind)))
                }
            }
        }
    }

    private func place(_ c: inout GraphicsContext, _ label: PlacedLabel, _ text: Text, dy: CGFloat = 0) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -20)
        var resolved: GraphicsContext.ResolvedText?
        for p in label.points {
            var v = p.applying(transform)
            guard bounds.contains(v) else { continue }
            v.y += dy
            if resolved == nil { resolved = c.resolve(text) }
            if let resolved { c.draw(resolved, at: v, anchor: .center) }
        }
    }
}

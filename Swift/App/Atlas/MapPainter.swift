import GeoCore
import SwiftUI

/// Draws a projected map into a Canvas. Shapes are scaled by `transform`;
/// line widths and text stay the same size at every zoom.
struct MapPainter {
    var map: ProjectedMap
    /// Coastline, borders and lakes at the detail level for this zoom.
    var base: BaseLayers
    var themes: Set<Theme>
    var season: Season
    var showLabels: Bool
    /// Map units → view points.
    var transform: CGAffineTransform
    var size: CGSize
    /// Repeat the map east and west, so panning never runs out of map
    /// (only for rectangular projections, whose copies meet seamlessly).
    var wraps = false

    private var scale: CGFloat { transform.a }

    /// The screen, in map units: only base-map cells reaching it are drawn.
    private var visible: CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: -4, dy: -4)
            .applying(transform.inverted()).standardized
    }

    func draw(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(MapStyle.surround))
        guard wraps else {
            drawCopy(&ctx)
            return
        }
        // One copy per world width that reaches the screen.
        let period = 2 * map.halfExtent.width * scale
        guard period > 1 else { return }
        let first = Int(((-period / 2 - transform.tx) / period).rounded(.up))
        let last = Int(((size.width + period / 2 - transform.tx) / period).rounded(.down))
        guard first <= last else { return }
        // Paper under every copy at once, so no hairline shows where they meet.
        let band = CGRect(x: -map.halfExtent.width, y: -map.halfExtent.height,
                          width: 2 * map.halfExtent.width, height: 2 * map.halfExtent.height)
            .applying(transform)
        ctx.fill(Path(CGRect(x: 0, y: band.minY, width: size.width, height: band.height)),
                 with: .color(MapStyle.paper))
        for k in first...last {
            var copy = self
            copy.transform.tx += CGFloat(k) * period
            copy.drawCopy(&ctx)
        }
    }

    private func drawCopy(_ ctx: inout GraphicsContext) {
        let outline = map.outline.applying(transform)
        ctx.fill(outline, with: .color(MapStyle.paper))

        var c = ctx
        c.clip(to: outline)

        if themes.contains(.climate) { drawKoppen(&c) }
        if themes.contains(.landforms) { drawOrogeny(&c) }
        if themes.contains(.winds) { drawPressureBelts(&c) }

        if scale * map.unitsPerDegree >= 12 {
            c.stroke(map.fineGraticule.applying(transform), with: .color(MapStyle.graticule.opacity(0.6)),
                     lineWidth: 0.4)
        }
        c.stroke(map.graticule.applying(transform), with: .color(MapStyle.graticule), lineWidth: 0.5)
        c.stroke(map.tropics.applying(transform), with: .color(MapStyle.graticule),
                 style: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
        c.stroke(map.equator.applying(transform), with: .color(MapStyle.equator), lineWidth: 0.7)

        let view = visible
        c.stroke(base.borders.path(in: view).applying(transform), with: .color(MapStyle.border), lineWidth: 0.5)
        c.stroke(base.lakes.path(in: view).applying(transform), with: .color(MapStyle.coast), lineWidth: 0.6)
        c.stroke(base.coastline.path(in: view).applying(transform), with: .color(MapStyle.coast), lineWidth: 0.8)

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

        if wraps {
            // Copies meet at the date line: only the poles' edges are drawn.
            let top = map.halfExtent.height, w = map.halfExtent.width
            var edges = Path()
            edges.move(to: CGPoint(x: -w, y: top))
            edges.addLine(to: CGPoint(x: w, y: top))
            edges.move(to: CGPoint(x: -w, y: -top))
            edges.addLine(to: CGPoint(x: w, y: -top))
            ctx.stroke(edges.applying(transform), with: .color(MapStyle.coast), lineWidth: 1)
        } else {
            ctx.stroke(outline, with: .color(MapStyle.coast), lineWidth: 1)
        }

        if showLabels { drawLabels(&c) }
    }

    // MARK: Layers

    private func drawKoppen(_ c: inout GraphicsContext) {
        c.drawLayer { layer in
            // The polygons reach a little into the sea; the coastline trims them.
            layer.clip(to: base.land.applying(transform), style: FillStyle(eoFill: true))
            for (cls, path) in map.koppen {
                layer.fill(path.applying(transform), with: .color(MapStyle.koppen(cls)), style: FillStyle(eoFill: true))
            }
        }
        c.fill(base.lakes.path(in: visible).applying(transform), with: .color(MapStyle.paper),
               style: FillStyle(eoFill: true))
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
            // Most important first; a label that would overlap one already
            // placed is left out (zooming in makes room for it).
            var placed = LabelSpace()
            if themes.contains(.winds), let air = map.air[season] {
                for b in air.belts {
                    place(&layer, &placed, b.labels, Text(b.belt.name).font(.caption2.weight(.semibold))
                        .foregroundStyle(MapStyle.pressureText(b.belt.kind)))
                }
            }
            if themes.contains(.plates) {
                for l in map.plateLabels {
                    place(&layer, &placed, l, Text(l.text).font(.caption2).foregroundStyle(Color(.secondaryLabel)))
                }
            }
            if themes.contains(.landforms) {
                for (r, _, l) in map.ranges {
                    place(&layer, &placed, l, Text(r.name).font(.caption2.weight(.semibold))
                        .foregroundStyle(MapStyle.range), dy: 10)
                }
            }
            if themes.contains(.currents) {
                for cur in map.currents {
                    place(&layer, &placed, cur.label, Text(cur.current.name).font(.caption2)
                        .foregroundStyle(MapStyle.current(warm: cur.current.warm)), dy: -9)
                }
            }
            if themes.contains(.winds), let air = map.air[season] {
                for (kind, l) in air.windLabels {
                    place(&layer, &placed, l, Text(kind.name).font(.caption2).foregroundStyle(MapStyle.wind(kind)))
                }
            }
            if themes.contains(.landforms) {
                for l in map.riverLabels {
                    place(&layer, &placed, l, Text(l.text).font(.caption2).foregroundStyle(MapStyle.river), dy: -8)
                }
            }
        }
    }

    /// The screen rectangles labels already cover.
    private struct LabelSpace {
        var rects: [CGRect] = []

        mutating func claim(_ r: CGRect) -> Bool {
            guard !rects.contains(where: { $0.intersects(r) }) else { return false }
            rects.append(r)
            return true
        }
    }

    private func place(_ c: inout GraphicsContext, _ space: inout LabelSpace, _ label: PlacedLabel,
                       _ text: Text, dy: CGFloat = 0) {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -20)
        var resolved: GraphicsContext.ResolvedText?
        for p in label.points {
            var v = p.applying(transform)
            guard bounds.contains(v) else { continue }
            v.y += dy
            let r = resolved ?? c.resolve(text)
            resolved = r
            let s = r.measure(in: CGSize(width: 400, height: 200))
            let box = CGRect(x: v.x - s.width / 2, y: v.y - s.height / 2, width: s.width, height: s.height)
                .insetBy(dx: -3, dy: -1)
            if space.claim(box) {
                c.draw(r, at: v, anchor: .center)
            }
        }
    }
}

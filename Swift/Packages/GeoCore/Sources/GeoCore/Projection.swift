import Foundation

/// World map projections. All are (pseudo)cylindrical: for a given latitude,
/// x is linear in the longitude. That lets the projector draw each shape at
/// longitude offsets of ±360° and clip to the map outline instead of
/// cutting shapes at the date line.
public enum Projection: String, CaseIterable, Sendable, Identifiable {
    case robinson
    case mollweide
    case equirectangular

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .robinson: "ロビンソン図法"
        case .mollweide: "モルワイデ図法"
        case .equirectangular: "正距円筒図法"
        }
    }

    /// λ, φ in radians; λ may lie outside ±π (the result then lies outside
    /// the outline at the same height).
    public func project(lambda: Double, phi: Double) -> Vec2 {
        switch self {
        case .robinson:
            let (x, y) = Robinson.factors(abs(phi))
            return Vec2(0.8487 * x * lambda, 1.3523 * y * (phi < 0 ? -1 : 1))
        case .mollweide:
            let theta = Mollweide.theta(phi)
            return Vec2(2 * 2.0.squareRoot() / .pi * lambda * cos(theta), 2.0.squareRoot() * sin(theta))
        case .equirectangular:
            return Vec2(lambda, phi)
        }
    }

    /// Half width and half height of the whole map.
    public var halfExtent: Vec2 {
        Vec2(project(lambda: .pi, phi: 0).x, project(lambda: 0, phi: .pi / 2).y)
    }

    /// The map's edge (λ = ±π), counter-clockwise.
    public func outline(step: Double = 2) -> [Vec2] {
        var ring: [Vec2] = []
        var lat = -90.0
        while lat <= 90 {
            ring.append(project(lambda: .pi, phi: lat * .pi / 180))
            lat += step
        }
        lat = 90
        while lat >= -90 {
            ring.append(project(lambda: -.pi, phi: lat * .pi / 180))
            lat -= step
        }
        return ring
    }
}

enum Robinson {
    // Robinson's table, every 5° from the equator to the pole.
    static let x: [Double] = [
        1.0000, 0.9986, 0.9954, 0.9900, 0.9822, 0.9730, 0.9600, 0.9427, 0.9216, 0.8962,
        0.8679, 0.8350, 0.7986, 0.7597, 0.7186, 0.6732, 0.6213, 0.5722, 0.5322,
    ]
    static let y: [Double] = [
        0.0000, 0.0620, 0.1240, 0.1860, 0.2480, 0.3100, 0.3720, 0.4340, 0.4958, 0.5571,
        0.6176, 0.6769, 0.7346, 0.7903, 0.8435, 0.8936, 0.9394, 0.9761, 1.0000,
    ]

    /// Table values at |φ| (radians), interpolated with a Catmull-Rom spline
    /// so parallels have no kinks at the 5° rows.
    static func factors(_ phi: Double) -> (Double, Double) {
        let deg = Swift.min(Swift.max(phi * 180 / .pi, 0), 90)
        let f = deg / 5
        let i = Swift.min(Int(f), 17)
        let t = f - Double(i)
        func spline(_ v: [Double]) -> Double {
            let p0 = i > 0 ? v[i - 1] : 2 * v[0] - v[1]
            let p1 = v[i], p2 = v[i + 1]
            let p3 = i + 2 < v.count ? v[i + 2] : 2 * v[i + 1] - v[i]
            let t2 = t * t, t3 = t2 * t
            return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)
        }
        return (spline(x), spline(y))
    }
}

enum Mollweide {
    /// Solves 2θ + sin 2θ = π sin φ (Newton).
    static func theta(_ phi: Double) -> Double {
        if abs(abs(phi) - .pi / 2) < 1e-9 { return phi }
        let target = Double.pi * sin(phi)
        var t = phi
        for _ in 0..<20 {
            let f = 2 * t + sin(2 * t) - target
            let d = 2 + 2 * cos(2 * t)
            if abs(d) < 1e-12 { break }
            let step = f / d
            t -= step
            if abs(step) < 1e-12 { break }
        }
        return t
    }
}

/// Projects geographic shapes for one projection and central meridian.
public struct MapProjector: Sendable, Hashable {
    public var projection: Projection
    /// Degrees east.
    public var centralMeridian: Double

    public init(projection: Projection, centralMeridian: Double) {
        self.projection = projection
        self.centralMeridian = centralMeridian
    }

    public func project(_ p: GeoPoint, copy k: Int = 0) -> Vec2 {
        let lambda = (p.lon - centralMeridian + 360 * Double(k)) * .pi / 180
        return projection.project(lambda: lambda, phi: p.lat * .pi / 180)
    }

    /// The ±360° copies of a shape spanning `minLon...maxLon` that reach the
    /// visible ±180° around the central meridian.
    public func copies(minLon: Double, maxLon: Double) -> [Int] {
        (-2...2).filter { k in
            let lo = minLon - centralMeridian + 360 * Double(k)
            let hi = maxLon - centralMeridian + 360 * Double(k)
            return hi >= -180 && lo <= 180
        }
    }

    /// Every visible copy of each line, in map units. Clip the result to
    /// `projection.outline()`.
    public func lines(_ lines: [[GeoPoint]], maxStep: Double = 2) -> [[Vec2]] {
        var out: [[Vec2]] = []
        for line in lines where line.count > 1 {
            let dense = line.densified(maxStep: maxStep)
            var lo = Double.infinity, hi = -Double.infinity
            for p in dense {
                lo = Swift.min(lo, p.lon)
                hi = Swift.max(hi, p.lon)
            }
            for k in copies(minLon: lo, maxLon: hi) {
                out.append(dense.map { project($0, copy: k) })
            }
        }
        return out
    }

    /// Every visible copy of each polygon (outer ring first, then holes),
    /// in map units. A polygon's rings stay together, copy by copy, so
    /// even-odd filling still leaves its holes open.
    public func polygons(_ polygons: [[[GeoPoint]]], maxStep: Double = 2) -> [[[Vec2]]] {
        var out: [[[Vec2]]] = []
        for rings in polygons {
            guard let outer = rings.first, outer.count > 2 else { continue }
            let dense = rings.map { $0.densified(maxStep: maxStep) }
            var lo = Double.infinity, hi = -Double.infinity
            for p in dense[0] {
                lo = Swift.min(lo, p.lon)
                hi = Swift.max(hi, p.lon)
            }
            for k in copies(minLon: lo, maxLon: hi) {
                out.append(dense.map { ring in ring.map { project($0, copy: k) } })
            }
        }
        return out
    }

    /// Every visible copy of a point (for labels).
    public func points(_ p: GeoPoint) -> [Vec2] {
        copies(minLon: p.lon, maxLon: p.lon).map { project(p, copy: $0) }
    }
}

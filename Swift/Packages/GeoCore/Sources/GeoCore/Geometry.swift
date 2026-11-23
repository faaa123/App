import Foundation

/// A place on the globe in degrees. Longitudes may run past ±180 so a line
/// that crosses the date line stays continuous (170 → 190 rather than
/// 170 → -170); the projector folds them back.
public struct GeoPoint: Sendable, Hashable {
    public var lon: Double
    public var lat: Double

    public init(_ lon: Double, _ lat: Double) {
        self.lon = lon
        self.lat = lat
    }
}

/// A point in projected map units (y grows north).
public struct Vec2: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

extension Array where Element == GeoPoint {
    /// Inserts points so no step is longer than `maxStep` degrees: straight
    /// lines in lon/lat (parallels, meridians, belts) curve correctly once
    /// projected.
    public func densified(maxStep: Double) -> [GeoPoint] {
        guard count > 1 else { return self }
        var out: [GeoPoint] = [self[0]]
        out.reserveCapacity(count)
        for (a, b) in zip(self, dropFirst()) {
            let span = Swift.max(abs(b.lon - a.lon), abs(b.lat - a.lat))
            let n = Swift.max(1, Int((span / maxStep).rounded(.up)))
            for i in 1...n {
                let t = Double(i) / Double(n)
                out.append(GeoPoint(a.lon + (b.lon - a.lon) * t, a.lat + (b.lat - a.lat) * t))
            }
        }
        return out
    }

    /// A smooth curve through the points (centripetal-free Catmull-Rom),
    /// `samples` points per span. Used for the schematic arrows.
    public func smoothed(samples: Int = 8) -> [GeoPoint] {
        guard count > 2 else { return densified(maxStep: 1) }
        var out: [GeoPoint] = [self[0]]
        for i in 0..<(count - 1) {
            let p0 = self[Swift.max(i - 1, 0)], p1 = self[i]
            let p2 = self[i + 1], p3 = self[Swift.min(i + 2, count - 1)]
            for s in 1...samples {
                let t = Double(s) / Double(samples)
                let t2 = t * t, t3 = t2 * t
                func cr(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
                }
                out.append(GeoPoint(cr(p0.lon, p1.lon, p2.lon, p3.lon), cr(p0.lat, p1.lat, p2.lat, p3.lat)))
            }
        }
        return out
    }
}

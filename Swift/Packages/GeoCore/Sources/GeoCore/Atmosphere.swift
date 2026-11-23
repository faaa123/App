import Foundation

public enum Season: String, CaseIterable, Sendable, Identifiable {
    case january
    case july

    public var id: String { rawValue }
    public var name: String { self == .january ? "1月" : "7月" }

    /// How far the belts sit north of their yearly mean (degrees).
    var shift: Double { self == .january ? -5 : 5 }
}

public enum PressureKind: Sendable {
    case low
    case high
}

/// A pressure belt as a band between two latitude curves.
public struct PressureBelt: Sendable {
    public var name: String
    public var kind: PressureKind
    /// The band's edges, west to east over 360°.
    public var north: [GeoPoint]
    public var south: [GeoPoint]
    public var labels: [GeoPoint]

    /// The band as one closed ring.
    public var ring: [GeoPoint] { north + south.reversed() }
}

public enum WindKind: Sendable {
    case trade
    case westerly
    case polarEasterly
    case monsoon

    public var name: String {
        switch self {
        case .trade: "貿易風"
        case .westerly: "偏西風"
        case .polarEasterly: "極偏東風"
        case .monsoon: "季節風（モンスーン）"
        }
    }
}

/// A wind arrow from `from` to `to`.
public struct WindArrow: Sendable {
    public var kind: WindKind
    public var from: GeoPoint
    public var to: GeoPoint
}

/// Textbook-level schematic of the planetary winds and pressure belts.
public enum Atmosphere {
    /// The equatorial low (ITCZ): latitude by longitude, every 15°, with the
    /// land-sea contrast a textbook shows (far south over the southern
    /// continents in January, far north over South Asia in July).
    static let itcz: [Season: [Double]] = [
        //            -180 -165 -150 -135 -120 -105  -90  -75  -60  -45  -30  -15    0   15   30   45   60   75   90  105  120  135  150  165  180
        .january: [-4, 2, 4, 5, 5, 4, 3, -4, -12, -10, -2, 2, 3, -4, -12, -15, -11, -8, -8, -9, -11, -15, -13, -9, -4],
        .july: [8, 9, 9, 10, 10, 11, 12, 9, 6, 7, 8, 12, 17, 18, 17, 15, 19, 25, 25, 22, 18, 15, 12, 10, 8],
    ]

    /// Latitude of the equatorial low at a longitude (any value; wraps).
    public static func itczLatitude(at lon: Double, season: Season) -> Double {
        let table = itcz[season] ?? []
        var x = (lon + 180).truncatingRemainder(dividingBy: 360)
        if x < 0 { x += 360 }
        let f = x / 15
        let i = Swift.min(Int(f), table.count - 2)
        let t = f - Double(i)
        return table[i] + (table[i + 1] - table[i]) * t
    }

    static let halfWidth = 4.0
    static let lons = Array(stride(from: -180.0, through: 180.0, by: 5))

    public static func belts(_ season: Season) -> [PressureBelt] {
        let s = season.shift
        func band(_ name: String, _ kind: PressureKind, center: (Double) -> Double,
                  half: Double = halfWidth, labelLons: [Double]) -> PressureBelt {
            PressureBelt(
                name: name, kind: kind,
                north: lons.map { GeoPoint($0, Swift.min(center($0) + half, 90)) },
                south: lons.map { GeoPoint($0, Swift.max(center($0) - half, -90)) },
                labels: labelLons.map { GeoPoint($0, center($0)) })
        }
        return [
            band("極高圧帯", .high, center: { _ in 86 }, labelLons: [-60, 120]),
            band("亜寒帯低圧帯", .low, center: { _ in 60 + s }, labelLons: [-150, -20, 100]),
            band("亜熱帯高圧帯", .high, center: { _ in 30 + s }, labelLons: [-150, -30, 150]),
            band("赤道低圧帯（熱帯収束帯）", .low, center: { itczLatitude(at: $0, season: season) },
                 labelLons: [-140, -20, 160]),
            band("亜熱帯高圧帯", .high, center: { _ in -30 + s }, labelLons: [-120, 0, 90]),
            band("亜寒帯低圧帯", .low, center: { _ in -60 + s }, labelLons: [-150, -30, 90]),
            band("極高圧帯", .high, center: { _ in -86 }, labelLons: [-60, 120]),
        ]
    }

    /// Planetary-wind arrows every 30° of longitude, plus the Asian monsoon.
    public static func winds(_ season: Season) -> [WindArrow] {
        let s = season.shift
        var out: [WindArrow] = []
        let dx = 5.0, dy = 2.2
        for lon in stride(from: -165.0, through: 165.0, by: 30) {
            let eq = itczLatitude(at: lon, season: season)
            // Northern hemisphere: NE trades, SW westerlies, NE polar easterlies.
            let nTrade = (eq + 30 + s) / 2
            out.append(WindArrow(kind: .trade, from: GeoPoint(lon + dx, nTrade + dy), to: GeoPoint(lon - dx, nTrade - dy)))
            let nWest = 45 + s
            out.append(WindArrow(kind: .westerly, from: GeoPoint(lon - dx, nWest - dy), to: GeoPoint(lon + dx, nWest + dy)))
            let nPolar = 73 + s / 2
            out.append(WindArrow(kind: .polarEasterly, from: GeoPoint(lon + dx, nPolar + dy), to: GeoPoint(lon - dx, nPolar - dy)))
            // Southern hemisphere: the mirror image.
            let sTrade = (eq - 30 + s) / 2
            out.append(WindArrow(kind: .trade, from: GeoPoint(lon + dx, sTrade - dy), to: GeoPoint(lon - dx, sTrade + dy)))
            let sWest = -45 + s
            out.append(WindArrow(kind: .westerly, from: GeoPoint(lon - dx, sWest + dy), to: GeoPoint(lon + dx, sWest - dy)))
            let sPolar = -73 + s / 2
            out.append(WindArrow(kind: .polarEasterly, from: GeoPoint(lon + dx, sPolar - dy), to: GeoPoint(lon - dx, sPolar + dy)))
        }
        let monsoon: [((Double, Double), (Double, Double))] = season == .january
            ? [((112, 50), (128, 38)), ((128, 45), (142, 36)), ((92, 27), (80, 14)), ((100, 22), (88, 8))]
            : [((140, 22), (124, 34)), ((150, 28), (138, 40)), ((58, 4), (74, 20)), ((72, 2), (88, 20))]
        for (a, b) in monsoon {
            out.append(WindArrow(kind: .monsoon, from: GeoPoint(a.0, a.1), to: GeoPoint(b.0, b.1)))
        }
        return out
    }

    /// One label per wind belt, placed beside an arrow.
    public static func windLabels(_ season: Season) -> [(WindKind, GeoPoint)] {
        let s = season.shift
        let lon = -135.0
        let eq = itczLatitude(at: lon, season: season)
        let monsoon = season == .january ? GeoPoint(100, 34) : GeoPoint(110, 24)
        return [
            (.trade, GeoPoint(lon, (eq + 30 + s) / 2 - 6)),
            (.westerly, GeoPoint(lon, 45 + s - 6)),
            (.polarEasterly, GeoPoint(lon, 73 + s / 2 - 6)),
            (.trade, GeoPoint(lon, (eq - 30 + s) / 2 + 6)),
            (.westerly, GeoPoint(lon, -45 + s + 6)),
            (.polarEasterly, GeoPoint(lon, -73 + s / 2 + 6)),
            (.monsoon, monsoon),
        ]
    }
}

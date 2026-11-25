import Foundation
import Testing
@testable import GeoCore

@Suite struct ProjectionTests {
    @Test func originMapsToOrigin() {
        for p in Projection.allCases {
            let v = p.project(lambda: 0, phi: 0)
            #expect(abs(v.x) < 1e-12 && abs(v.y) < 1e-12)
        }
    }

    @Test func robinsonMatchesTableRows() {
        let at45 = Projection.robinson.project(lambda: .pi, phi: 45 * .pi / 180)
        #expect(abs(at45.x - 0.8487 * 0.8962 * .pi) < 1e-9)
        #expect(abs(at45.y - 1.3523 * 0.5571) < 1e-9)
        let pole = Projection.robinson.project(lambda: .pi, phi: .pi / 2)
        #expect(abs(pole.y - 1.3523) < 1e-9)
        #expect(abs(pole.x - 0.8487 * 0.5322 * .pi) < 1e-9)
    }

    @Test func robinsonIsMonotonicInLatitude() {
        var last = -1.0
        for d in stride(from: 0.0, through: 90, by: 0.5) {
            let y = Projection.robinson.project(lambda: 0, phi: d * .pi / 180).y
            #expect(y > last)
            last = y
        }
    }

    @Test func mollweideIsAnEllipse() {
        let e = Projection.mollweide.halfExtent
        #expect(abs(e.x - 2 * 2.0.squareRoot()) < 1e-9)
        #expect(abs(e.y - 2.0.squareRoot()) < 1e-9)
        // Points on the edge satisfy x²/a² + y²/b² = 1.
        for d in stride(from: -85.0, through: 85, by: 17) {
            let v = Projection.mollweide.project(lambda: .pi, phi: d * .pi / 180)
            #expect(abs(v.x * v.x / (e.x * e.x) + v.y * v.y / (e.y * e.y) - 1) < 1e-9)
        }
    }

    @Test func southIsMirrored() {
        for p in Projection.allCases {
            let n = p.project(lambda: 1, phi: 0.7)
            let s = p.project(lambda: 1, phi: -0.7)
            #expect(abs(n.x - s.x) < 1e-12 && abs(n.y + s.y) < 1e-12)
        }
    }
}

@Suite struct ProjectorTests {
    @Test func centralMeridianShiftsTheMap() {
        let pj = MapProjector(projection: .equirectangular, centralMeridian: 150)
        let tokyo = pj.project(GeoPoint(140, 35))
        #expect(abs(tokyo.x - (-10 * .pi / 180)) < 1e-12)
    }

    @Test func linesAreCopiedAcrossTheSeam() {
        let pj = MapProjector(projection: .equirectangular, centralMeridian: 0)
        // A line from 170°E to 190°E (= 170°W) shows on both edges.
        let out = pj.lines([[GeoPoint(170, 0), GeoPoint(190, 0)]])
        #expect(out.count == 2)
        // A line well inside needs one copy.
        #expect(pj.lines([[GeoPoint(-10, 0), GeoPoint(10, 0)]]).count == 1)
    }

    @Test func densifyLimitsTheStep() {
        let d = [GeoPoint(0, 0), GeoPoint(10, 0)].densified(maxStep: 2)
        #expect(d.count == 6)
        #expect(d.last == GeoPoint(10, 0))
    }

    @Test func smoothingPassesThroughControlPoints() {
        let pts = [GeoPoint(0, 0), GeoPoint(10, 5), GeoPoint(20, 0)]
        let s = pts.smoothed(samples: 4)
        #expect(s.first == pts[0])
        #expect(s.contains(pts[1]))
        #expect(s.last == pts[2])
    }
}

@Suite struct GeoJSONTests {
    @Test func decodesTheBundledShapes() throws {
        let json = """
        {"type":"FeatureCollection","features":[
          {"type":"Feature","properties":{"name":"長江","rank":3},
           "geometry":{"type":"LineString","coordinates":[[100,30],[120,31.5]]}},
          {"type":"Feature","properties":null,
           "geometry":{"type":"MultiPolygon","coordinates":[[[[0,0],[1,0],[1,1],[0,0]]],[[[5,5],[6,5],[6,6],[5,5]]]]}}
        ]}
        """
        let f = try GeoJSON.decode(Data(json.utf8))
        #expect(f.count == 2)
        #expect(f[0].properties == ["name": "長江"])
        #expect(f[0].parts == [[GeoPoint(100, 30), GeoPoint(120, 31.5)]])
        #expect(f[1].parts.count == 2)
    }

    @Test func rejectsPoints() {
        let json = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{},"geometry":{"type":"Point","coordinates":[0,0]}}]}"#
        #expect(throws: GeoJSON.DecodeError.unsupportedGeometry("Point")) {
            try GeoJSON.decode(Data(json.utf8))
        }
    }
}

@Suite struct AtlasDataTests {
    @Test func itczWrapsAndShiftsWithTheSeason() {
        for s in Season.allCases {
            #expect(abs(Atmosphere.itczLatitude(at: -180, season: s) - Atmosphere.itczLatitude(at: 180, season: s)) < 1e-9)
            #expect(abs(Atmosphere.itczLatitude(at: 30, season: s) - Atmosphere.itczLatitude(at: 390, season: s)) < 1e-9)
        }
        // South Asia: far north in July, south of the equator in January.
        #expect(Atmosphere.itczLatitude(at: 80, season: .july) > 20)
        #expect(Atmosphere.itczLatitude(at: 80, season: .january) < 0)
    }

    @Test func beltsAreOrderedNorthToSouth() {
        for s in Season.allCases {
            let belts = Atmosphere.belts(s)
            #expect(belts.count == 7)
            for (a, b) in zip(belts, belts.dropFirst()) {
                for (pa, pb) in zip(a.south, b.north) {
                    #expect(pa.lat >= pb.lat)
                }
            }
        }
    }

    @Test func tradeWindsBlowTowardTheEquator() {
        for s in Season.allCases {
            for w in Atmosphere.winds(s) where w.kind == .trade {
                #expect(w.to.lon < w.from.lon) // easterly
                // north of the equatorial low it blows south, and vice versa
                let north = w.from.lat > Atmosphere.itczLatitude(at: w.from.lon, season: s)
                #expect(north ? w.to.lat < w.from.lat : w.to.lat > w.from.lat)
            }
        }
    }

    @Test func schematicShapesAreValid() {
        let all = OceanCurrents.all.map(\.path) + Landforms.belts.map(\.path) + Landforms.ranges.map(\.path)
        for path in all {
            #expect(path.count >= 2)
            for (a, b) in zip(path, path.dropFirst()) {
                #expect(abs(a.lat) <= 90)
                // continuous: no jump across the date line
                #expect(abs(b.lon - a.lon) < 60)
            }
        }
        #expect(OceanCurrents.all.contains { $0.warm })
        #expect(OceanCurrents.all.contains { !$0.warm })
    }
}

@Suite struct BundledDataTests {
    static let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Geo")

    func load(_ name: String) throws -> [GeoFeature] {
        try GeoJSON.decode(Data(contentsOf: Self.dir.appendingPathComponent("\(name).geojson")))
    }

    @Test func everyFileDecodes() throws {
        for name in ["ocean", "coastline", "borders", "lakes", "rivers"] {
            #expect(try !load(name).isEmpty, "\(name)")
        }
    }

    @Test func platesHaveTheThreeKinds() throws {
        let kinds = try load("plates").compactMap { $0.properties["kind"].flatMap(PlateBoundaryKind.init(rawValue:)) }
        #expect(Set(kinds) == Set(PlateBoundaryKind.allCases))
    }

    @Test func koppenHasEveryClass() throws {
        let classes = try load("koppen").compactMap { $0.properties["class"].flatMap(KoppenClass.init(rawValue:)) }
        #expect(Set(classes) == Set(KoppenClass.allCases))
    }

    @Test func riversAreNamedInJapanese() throws {
        let names = try load("rivers").compactMap { $0.properties["name"] }
        #expect(names.contains("ナイル川"))
        #expect(names.contains("長江"))
    }
}

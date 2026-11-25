import Foundation
import GeoCore
import SwiftUI

/// How detailed the coastline, borders and lakes are. Like a web map's
/// zoom levels: the map switches to finer data as it is zoomed in.
enum MapDetail: Int, CaseIterable, Comparable, Sendable {
    /// Natural Earth 1:110m (the whole world at a glance).
    case coarse
    /// 1:50m.
    case medium
    /// 1:10m (a region filling the screen).
    case fine

    static func < (a: MapDetail, b: MapDetail) -> Bool { a.rawValue < b.rawValue }

    /// The level for a zoom, given on-screen points per degree of latitude.
    static func forPointsPerDegree(_ ppd: CGFloat) -> MapDetail {
        if ppd < 9 { return .coarse }
        if ppd < 30 { return .medium }
        return .fine
    }

    /// Grid cell size for culling, in degrees.
    var cellDegrees: Double {
        switch self {
        case .coarse: 30
        case .medium: 15
        case .fine: 6
        }
    }
}

/// Lines or polygons in map units, cut into grid cells, so a frame draws
/// only the cells on screen. Each cell is one prebuilt Path.
struct TiledPath: Sendable {
    struct Cell: Sendable {
        var bounds: CGRect
        var path: Path
    }

    var cells: [Cell] = []

    /// Lines, split into short runs so each run's cell is close to it.
    init(lines: [[Vec2]], cellSize: CGFloat, run: Int = 64) {
        var builder = Builder(cellSize: cellSize)
        for line in lines where line.count > 1 {
            var start = 0
            while start < line.count - 1 {
                let end = min(start + run, line.count - 1)
                builder.add([Array(line[start...end])], closed: false)
                start = end
            }
        }
        cells = builder.cells()
    }

    /// Polygons (outer ring, then holes), each kept whole in one cell.
    init(polygons: [[[Vec2]]], cellSize: CGFloat) {
        var builder = Builder(cellSize: cellSize)
        for rings in polygons {
            builder.add(rings, closed: true)
        }
        cells = builder.cells()
    }

    /// The cells that reach `rect` (map units), as one path.
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for cell in cells where cell.bounds.intersects(rect) {
            p.addPath(cell.path)
        }
        return p
    }

    private struct Key: Hashable {
        var x: Int
        var y: Int
    }

    private struct Builder {
        var cellSize: CGFloat
        var paths: [Key: (bounds: CGRect, path: Path)] = [:]

        mutating func add(_ rings: [[Vec2]], closed: Bool) {
            guard let first = rings.first, !first.isEmpty else { return }
            var minX = CGFloat.infinity, minY = CGFloat.infinity
            var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
            for v in first {
                let x = CGFloat(v.x), y = CGFloat(v.y)
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
            // Never empty, so a straight horizontal run still intersects.
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -1e-4, dy: -1e-4)
            let key = Key(x: Int((bounds.midX / cellSize).rounded(.down)),
                          y: Int((bounds.midY / cellSize).rounded(.down)))
            var entry = paths[key] ?? (bounds, Path())
            entry.bounds = entry.bounds.union(bounds)
            for ring in rings where ring.count > 1 {
                entry.path.move(to: CGPoint(x: ring[0].x, y: ring[0].y))
                for v in ring.dropFirst() {
                    entry.path.addLine(to: CGPoint(x: v.x, y: v.y))
                }
                if closed { entry.path.closeSubpath() }
            }
            paths[key] = entry
        }

        func cells() -> [Cell] {
            paths.values.map { Cell(bounds: $0.bounds, path: $0.path) }
        }
    }
}

/// Coastline, borders and lakes at one detail level, in geographic
/// coordinates.
struct BaseData: Sendable {
    var coastline: [[GeoPoint]] = []
    var borders: [[GeoPoint]] = []
    /// Polygons: outer ring, then holes.
    var lakes: [[[GeoPoint]]] = []
    /// Land polygons, to trim the climate fills to the coast.
    var land: [[[GeoPoint]]] = []
}

/// One detail level of the base map, projected and cut into cells.
struct BaseLayers: Sendable {
    var coastline: TiledPath
    var borders: TiledPath
    /// Closed rings, filled even-odd.
    var lakes: TiledPath
    /// Whole, since it is used as a clip.
    var land: Path

    static func build(_ data: BaseData, detail: MapDetail, projector pj: MapProjector) -> BaseLayers {
        let cell = CGFloat(pj.projection.project(lambda: 0, phi: .pi / 180).y * detail.cellDegrees)
        var land = Path()
        for rings in pj.polygons(data.land) {
            for ring in rings where ring.count > 2 {
                land.addLines(ring.map { CGPoint(x: $0.x, y: $0.y) })
                land.closeSubpath()
            }
        }
        return BaseLayers(
            coastline: TiledPath(lines: pj.lines(data.coastline), cellSize: cell),
            borders: TiledPath(lines: pj.lines(data.borders), cellSize: cell),
            lakes: TiledPath(polygons: pj.polygons(data.lakes), cellSize: cell),
            land: land)
    }
}

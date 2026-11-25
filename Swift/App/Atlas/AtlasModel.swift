import GeoCore
import Observation
import SwiftUI

/// What the map shows and where it is looking. Shared by all themes, so
/// switching themes keeps the zoom.
@MainActor @Observable
final class MapSettings {
    var projection: Projection = .robinson
    /// 0 (Atlantic in the middle) or 150 (Pacific in the middle, as in
    /// Japanese atlases).
    var centralMeridian: Double = 0
    var season: Season = .january
    /// Themes drawn on top of each tab's own theme.
    var overlays: Set<Theme> = []
    var showLabels = true
    var showLegend = true

    /// Zoom (1 = whole map) and pan in points.
    var scale: CGFloat = 1
    var offset: CGSize = .zero

    var projector: MapProjector {
        MapProjector(projection: projection, centralMeridian: centralMeridian)
    }

    func themes(primary: Theme) -> Set<Theme> {
        overlays.union([primary])
    }
}

/// One detail level of the base map for one projection.
struct BaseKey: Hashable, Sendable {
    var projector: MapProjector
    var detail: MapDetail
}

/// Loads the bundled data and keeps one projected map per projection, plus
/// the base map at each detail level reached so far.
@MainActor @Observable
final class AtlasModel {
    private(set) var maps: [MapProjector: ProjectedMap] = [:]
    private(set) var bases: [BaseKey: BaseLayers] = [:]
    private(set) var failed = false
    @ObservationIgnored private var data: AtlasData?
    @ObservationIgnored private var details: [MapDetail: BaseData] = [:]
    @ObservationIgnored private var building: Set<MapProjector> = []
    @ObservationIgnored private var buildingBases: Set<BaseKey> = []

    /// The finest base map ready for `detail` or coarser.
    func base(_ projector: MapProjector, upTo detail: MapDetail) -> BaseLayers? {
        for d in MapDetail.allCases.reversed() where d <= detail {
            if let b = bases[BaseKey(projector: projector, detail: d)] { return b }
        }
        return nil
    }

    func prepare(_ projector: MapProjector) async {
        guard maps[projector] == nil, !building.contains(projector) else { return }
        building.insert(projector)
        defer { building.remove(projector) }
        do {
            let loaded: AtlasData
            if let data {
                loaded = data
            } else {
                loaded = try await Task.detached(priority: .userInitiated) { try AtlasData.loadBundled() }.value
                data = loaded
            }
            let (map, base) = await Task.detached(priority: .userInitiated) {
                (ProjectedMap.build(loaded, projector: projector),
                 BaseLayers.build(loaded.base, detail: .coarse, projector: projector))
            }.value
            bases[BaseKey(projector: projector, detail: .coarse)] = base
            maps[projector] = map
        } catch {
            print("Atlas: could not load map data: \(error)")
            failed = true
        }
    }

    /// Loads and projects a finer base map (the coarse one comes with
    /// `prepare`). On failure the map keeps the coarser level.
    func prepareBase(_ detail: MapDetail, _ projector: MapProjector) async {
        let key = BaseKey(projector: projector, detail: detail)
        guard detail > .coarse, bases[key] == nil, !buildingBases.contains(key) else { return }
        buildingBases.insert(key)
        defer { buildingBases.remove(key) }
        do {
            let raw: BaseData
            if let cached = details[detail] {
                raw = cached
            } else {
                raw = try await Task.detached(priority: .userInitiated) { try AtlasData.loadDetail(detail) }.value
                details[detail] = raw
            }
            bases[key] = await Task.detached(priority: .userInitiated) {
                BaseLayers.build(raw, detail: detail, projector: projector)
            }.value
        } catch {
            print("Atlas: could not load \(detail) detail: \(error)")
        }
    }
}

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

/// Loads the bundled data and keeps one projected map per projection.
@MainActor @Observable
final class AtlasModel {
    private(set) var maps: [MapProjector: ProjectedMap] = [:]
    private(set) var failed = false
    @ObservationIgnored private var data: AtlasData?
    @ObservationIgnored private var building: Set<MapProjector> = []

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
            let map = await Task.detached(priority: .userInitiated) {
                ProjectedMap.build(loaded, projector: projector)
            }.value
            maps[projector] = map
        } catch {
            print("Atlas: could not load map data: \(error)")
            failed = true
        }
    }
}

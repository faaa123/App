import GeoCore
import Observation

/// What the map shows. Shared by all themes, so switching themes keeps the
/// overlays and the season.
@MainActor @Observable
final class MapSettings {
    var season: Season = .january
    /// Themes drawn on top of the selected theme.
    var overlays: Set<Theme> = []
    var showLabels = true
    var showLegend = true
    /// Bumped by 全体を表示: the map flies back to the whole world.
    var resetRequests = 0

    func themes(primary: Theme) -> Set<Theme> {
        overlays.union([primary])
    }
}

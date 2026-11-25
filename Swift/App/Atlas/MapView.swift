import GeoCore
import MapLibre
import SwiftUI

/// The white map, drawn by MapLibre: vector tiles cut from the bundled
/// data per zoom, rendered with Metal, with the gestures of a maps app
/// (pinch, drag and fling, double tap, two-finger tap, trackpad and mouse
/// wheel). North stays up and the map stays flat, as in an atlas.
struct MapView: UIViewRepresentable {
    var primary: Theme
    /// The bars drawn over the map: the whole world is fitted below them.
    var insets: EdgeInsets
    @Environment(MapSettings.self) private var settings

    /// Deepest zoom: a region fills the screen (the 1:10m data has no
    /// more detail).
    static let maxZoom = 9.0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MLNMapView {
        let styleURL: URL?
        do {
            styleURL = try AtlasStyle.write()
        } catch {
            print("Atlas: could not write the map style: \(error)")
            styleURL = nil
        }
        let map = MLNMapView(frame: .zero, styleURL: styleURL)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.maximumZoomLevel = Self.maxZoom
        map.compassView.isHidden = true
        map.automaticallyAdjustsContentInset = false
        map.backgroundColor = UIColor(MapStyle.paper)
        map.accessibilityLabel = "白地図"
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.state = .init(themes: settings.themes(primary: primary), season: settings.season,
                        labels: settings.showLabels)
        let inset = UIEdgeInsets(top: insets.top, left: insets.leading,
                                 bottom: insets.bottom, right: insets.trailing)
        if map.contentInset != inset {
            map.setContentInset(inset, animated: false, completionHandler: nil)
        }
        c.applyVisibility(map)
        c.placeIfNeeded(map)
        if c.resetRequests != settings.resetRequests {
            c.resetRequests = settings.resetRequests
            c.showWholeWorld(map, animated: true)
        }
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        struct State: Equatable {
            var themes: Set<Theme> = []
            var season: Season = .january
            var labels = true
        }

        var state = State()
        var resetRequests = 0
        private var applied: State?
        private var placed = false

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            style.setImage(AtlasStyle.arrowheadImage(), forName: AtlasStyle.arrowhead)
            applied = nil
            applyVisibility(mapView)
            placeIfNeeded(mapView)
        }

        /// Starts on the whole world, once the map has a size.
        func placeIfNeeded(_ map: MLNMapView) {
            guard !placed, map.style != nil else { return }
            placed = showWholeWorld(map, animated: false)
        }

        /// Shows the layers of the selected and overlaid themes.
        func applyVisibility(_ map: MLNMapView) {
            guard let style = map.style, applied != state else { return }
            applied = state
            for layer in style.layers {
                guard let tag = AtlasStyle.LayerTag(id: layer.identifier) else { continue }
                let visible = tag.isVisible(themes: state.themes, season: state.season, labels: state.labels)
                if layer.isVisible != visible { layer.isVisible = visible }
            }
        }

        /// The whole world across the visible width, Pacific in the middle
        /// as in Japanese atlases.
        @discardableResult
        func showWholeWorld(_ map: MLNMapView, animated: Bool) -> Bool {
            let width = map.bounds.width - map.contentInset.left - map.contentInset.right
            guard width > 0 else { return false }
            // MapLibre's world is 512 points wide at zoom 0.
            let zoom = log2(width / 512)
            map.minimumZoomLevel = max(zoom - 0.5, 0)
            map.setCenter(CLLocationCoordinate2D(latitude: 20, longitude: 150), zoomLevel: zoom,
                          animated: animated)
            return true
        }
    }
}

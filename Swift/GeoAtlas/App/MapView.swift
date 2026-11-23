import GeoCore
import SwiftUI

/// The zoomable, pannable white map for one tab.
struct MapView: View {
    var primary: Theme
    @Environment(MapSettings.self) private var settings
    @Environment(AtlasModel.self) private var atlas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // In-flight gesture, applied on top of the settings' zoom and pan.
    @State private var pinch: CGFloat = 1
    @State private var pinchAnchor: CGPoint = .zero
    @State private var drag: CGSize = .zero
    @State private var pinching = false

    static let maxScale: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if let map = atlas.maps[settings.projector] {
                let view = liveView(size: size, map: map)
                MapCanvas(map: map, themes: settings.themes(primary: primary), season: settings.season,
                          showLabels: settings.showLabels, scale: view.scale, offsetX: view.offset.width,
                          offsetY: view.offset.height)
                    .contentShape(Rectangle())
                    .gesture(zoomAndPan(size: size, map: map))
                    .gesture(SpatialTapGesture(count: 2).onEnded { tap in
                        zoomIn(at: tap.location, size: size, map: map)
                    })
                    .accessibilityElement()
                    .accessibilityLabel("\(primary.title)の白地図")
                    .accessibilityHint("ピンチで拡大・縮小、ドラッグで移動、ダブルタップで拡大します")
                    .accessibilityAddTraits(.allowsDirectInteraction)
            } else if atlas.failed {
                ContentUnavailableView("地図データを読み込めませんでした", systemImage: "exclamationmark.triangle",
                                       description: Text("アプリを再インストールしてください。"))
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MapStyle.surround)
        .environment(\.colorScheme, .light)
        .task(id: settings.projector) { await atlas.prepare(settings.projector) }
    }

    // MARK: Gestures

    private func liveView(size: CGSize, map: ProjectedMap) -> (scale: CGFloat, offset: CGSize) {
        let base = settings.scale
        let target = min(max(base * pinch, 1), Self.maxScale)
        let k = target / base
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var o = settings.offset
        // Keep the point under the fingers fixed while zooming.
        o.width = (pinchAnchor.x - center.x) - (pinchAnchor.x - center.x - o.width) * k
        o.height = (pinchAnchor.y - center.y) - (pinchAnchor.y - center.y - o.height) * k
        o.width += drag.width
        o.height += drag.height
        return (target, clamp(o, scale: target, size: size, map: map))
    }

    /// Keeps some of the map on screen.
    private func clamp(_ o: CGSize, scale: CGFloat, size: CGSize, map: ProjectedMap) -> CGSize {
        let fit = MapCanvas.fit(size: size, map: map)
        let hx = map.halfExtent.width * fit * scale
        let hy = map.halfExtent.height * fit * scale
        return CGSize(width: min(max(o.width, -hx), hx), height: min(max(o.height, -hy), hy))
    }

    /// Pinch and drag as one gesture, committed when every finger lifts.
    private func zoomAndPan(size: CGSize, map: ProjectedMap) -> some Gesture {
        MagnifyGesture()
            .simultaneously(with: DragGesture(minimumDistance: 2))
            .onChanged { v in
                if let m = v.first {
                    if !pinching {
                        pinching = true
                        pinchAnchor = m.startLocation
                    }
                    pinch = m.magnification
                }
                if let d = v.second {
                    drag = d.translation
                }
            }
            .onEnded { _ in commit(size: size, map: map) }
    }

    private func commit(size: CGSize, map: ProjectedMap) {
        let v = liveView(size: size, map: map)
        settings.scale = v.scale
        settings.offset = v.offset
        pinch = 1
        drag = .zero
        pinching = false
    }

    private func zoomIn(at point: CGPoint, size: CGSize, map: ProjectedMap) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let animation: Animation? = reduceMotion ? nil : .snappy(duration: 0.3)
        withAnimation(animation) {
            if settings.scale >= Self.maxScale {
                settings.scale = 1
                settings.offset = .zero
                return
            }
            let target = min(settings.scale * 2, Self.maxScale)
            let k = target / settings.scale
            let o = CGSize(width: (point.x - center.x) - (point.x - center.x - settings.offset.width) * k,
                           height: (point.y - center.y) - (point.y - center.y - settings.offset.height) * k)
            settings.scale = target
            settings.offset = clamp(o, scale: target, size: size, map: map)
        }
    }
}

/// The drawing itself. Animatable, so zoom changes made with
/// `withAnimation` (double tap, "show whole map") glide.
struct MapCanvas: View, Animatable {
    var map: ProjectedMap
    var themes: Set<Theme>
    var season: Season
    var showLabels: Bool
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat

    nonisolated var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(scale, AnimatablePair(offsetX, offsetY)) }
        set {
            scale = newValue.first
            offsetX = newValue.second.first
            offsetY = newValue.second.second
        }
    }

    /// Points per map unit at zoom 1: the whole map with a margin.
    nonisolated static func fit(size: CGSize, map: ProjectedMap) -> CGFloat {
        0.94 * min(size.width / (2 * map.halfExtent.width), size.height / (2 * map.halfExtent.height))
    }

    var body: some View {
        Canvas { [map, themes, season, showLabels, scale, offsetX, offsetY] ctx, size in
            let s = Self.fit(size: size, map: map) * scale
            let t = CGAffineTransform(a: s, b: 0, c: 0, d: -s,
                                      tx: size.width / 2 + offsetX, ty: size.height / 2 + offsetY)
            MapPainter(map: map, themes: themes, season: season, showLabels: showLabels,
                       transform: t, size: size).draw(&ctx)
        }
    }
}

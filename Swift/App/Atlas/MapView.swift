import GeoCore
import SwiftUI
import UIKit

/// The zoomable, pannable white map, handled like a maps app: the map
/// stays under the fingers while pinching and dragging, a fling glides on,
/// a double tap zooms in and a two-finger tap zooms out. A trackpad pans
/// with two fingers and pinches to zoom; a mouse wheel zooms at the
/// pointer.
struct MapView: View {
    var primary: Theme
    /// The bars drawn over the map: it is fitted and centered in the rest,
    /// but still drawn under them.
    var insets = EdgeInsets()
    @Environment(MapSettings.self) private var settings
    @Environment(AtlasModel.self) private var atlas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let maxScale: CGFloat = 20
    /// A pinch may go a little past the whole map, then springs back.
    static let minLiveScale: CGFloat = 0.8

    /// Rectangular projections repeat east and west, so panning never
    /// runs out of map.
    private var wraps: Bool { settings.projection == .equirectangular }

    var body: some View {
        GeometryReader { geo in
            let focus = CGRect(x: insets.leading, y: insets.top,
                               width: max(geo.size.width - insets.leading - insets.trailing, 1),
                               height: max(geo.size.height - insets.top - insets.bottom, 1))
            if let map = atlas.maps[settings.projector] {
                let camera = MapCamera(focus: focus, map: map, wraps: wraps)
                let offset = camera.clamp(settings.offset, scale: settings.scale)
                MapCanvas(map: map, themes: settings.themes(primary: primary), season: settings.season,
                          showLabels: settings.showLabels, wraps: wraps, focus: focus, scale: settings.scale,
                          offsetX: offset.width, offsetY: offset.height)
                    .overlay { MapGestureSurface(handlers: handlers(camera)) }
                    .accessibilityElement()
                    .accessibilityLabel("\(primary.title)の白地図")
                    .accessibilityHint("ピンチで拡大・縮小、ドラッグで移動、ダブルタップで拡大、2本指タップで縮小します")
                    .accessibilityAddTraits(.allowsDirectInteraction)
                    .accessibilityAdjustableAction { direction in
                        let middle = CGPoint(x: focus.midX, y: focus.midY)
                        switch direction {
                        case .increment: zoomAnimated(by: 2, at: middle, camera: camera)
                        case .decrement: zoomAnimated(by: 0.5, at: middle, camera: camera)
                        @unknown default: break
                        }
                    }
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

    private func handlers(_ camera: MapCamera) -> MapGestureHandlers {
        MapGestureHandlers(
            pan: { delta in
                var o = settings.offset
                o.width += delta.width
                o.height += delta.height
                settings.offset = camera.clamp(o, scale: settings.scale, normalize: true)
            },
            zoom: { factor, point in
                let old = settings.scale
                let new = min(max(old * factor, Self.minLiveScale), Self.maxScale)
                guard new != old else { return }
                let o = camera.zoom(settings.offset, by: new / old, at: point)
                settings.scale = new
                settings.offset = camera.clamp(o, scale: new, normalize: true)
            },
            zoomEnded: {
                // Spring back from a pinch past the whole map.
                guard settings.scale < 1 else { return }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
                    settings.scale = 1
                    settings.offset = camera.clamp(settings.offset, scale: 1)
                }
            },
            doubleTap: { point in zoomAnimated(by: 2, at: point, camera: camera) },
            twoFingerTap: { point in zoomAnimated(by: 0.5, at: point, camera: camera) })
    }

    private func zoomAnimated(by factor: CGFloat, at point: CGPoint, camera: MapCamera) {
        let old = settings.scale
        let new = min(max(old * factor, 1), Self.maxScale)
        guard new != old else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) {
            settings.scale = new
            settings.offset = camera.clamp(camera.zoom(settings.offset, by: new / old, at: point), scale: new)
        }
    }
}

/// Zoom and pan math for one view size and map. Offsets are from the
/// middle of `focus`, the part of the view not under the bars.
struct MapCamera {
    var focus: CGRect
    var halfExtent: CGSize
    /// Points per map unit at zoom 1.
    var fit: CGFloat
    var wraps: Bool

    init(focus: CGRect, map: ProjectedMap, wraps: Bool) {
        self.focus = focus
        halfExtent = map.halfExtent
        fit = MapCanvas.fit(size: focus.size, map: map)
        self.wraps = wraps
    }

    /// The offset after zooming by `k`, keeping `point` (view coordinates)
    /// over the same place on the map.
    func zoom(_ o: CGSize, by k: CGFloat, at point: CGPoint) -> CGSize {
        let dx = point.x - focus.midX, dy = point.y - focus.midY
        return CGSize(width: dx - (dx - o.width) * k, height: dy - (dy - o.height) * k)
    }

    /// Keeps the map filling the view along each axis it is larger than the
    /// view, and centered along the others. With `normalize`, a wrapping
    /// map's offset is brought within one world width (invisible, since
    /// the copies look alike; skipped while animating so nothing sweeps).
    func clamp(_ o: CGSize, scale: CGFloat, normalize: Bool = false) -> CGSize {
        func axis(_ v: CGFloat, half: CGFloat, view: CGFloat) -> CGFloat {
            // 0.94: the margin the whole map has at zoom 1.
            let slack = max(half - view / 2 * 0.94, 0)
            return min(max(v, -slack), slack)
        }
        let hx = halfExtent.width * fit * scale
        let hy = halfExtent.height * fit * scale
        var x = o.width
        if !wraps {
            x = axis(x, half: hx, view: focus.width)
        } else if normalize, hx > 0 {
            x = x.remainder(dividingBy: 2 * hx)
        }
        return CGSize(width: x, height: axis(o.height, half: hy, view: focus.height))
    }
}

/// The drawing itself. Animatable, so zoom changes made with
/// `withAnimation` (double tap, "show whole map") glide.
struct MapCanvas: View, Animatable {
    var map: ProjectedMap
    var themes: Set<Theme>
    var season: Season
    var showLabels: Bool
    var wraps: Bool
    /// Where the whole map is fitted (the view minus the bars).
    var focus: CGRect
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
        Canvas { [map, themes, season, showLabels, wraps, focus, scale, offsetX, offsetY] ctx, size in
            let s = Self.fit(size: focus.size, map: map) * scale
            let t = CGAffineTransform(a: s, b: 0, c: 0, d: -s,
                                      tx: focus.midX + offsetX, ty: focus.midY + offsetY)
            MapPainter(map: map, themes: themes, season: season, showLabels: showLabels,
                       transform: t, size: size, wraps: wraps).draw(&ctx)
        }
    }
}

// MARK: - UIKit gesture layer

/// What the gesture layer reports, in view points.
struct MapGestureHandlers {
    var pan: @MainActor (CGSize) -> Void
    /// Zoom by a factor, keeping a point still.
    var zoom: @MainActor (CGFloat, CGPoint) -> Void
    var zoomEnded: @MainActor () -> Void
    var doubleTap: @MainActor (CGPoint) -> Void
    var twoFingerTap: @MainActor (CGPoint) -> Void
}

/// A transparent view over the map whose UIKit recognizers run together
/// (pinch and pan at once, with the fingers' midpoint as the anchor), and
/// which keeps a fling gliding.
struct MapGestureSurface: UIViewRepresentable {
    var handlers: MapGestureHandlers

    func makeUIView(context: Context) -> MapGestureView {
        MapGestureView(handlers: handlers)
    }

    func updateUIView(_ view: MapGestureView, context: Context) {
        view.handlers = handlers
    }
}

final class MapGestureView: UIView, UIGestureRecognizerDelegate {
    var handlers: MapGestureHandlers

    private var touchCount = 0
    private var pinchedDuringPan = false
    private var momentum: CGPoint = .zero
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    init(handlers: MapGestureHandlers) {
        self.handlers = handlers
        super.init(frame: .zero)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        // Fingers, and two-finger trackpad scrolling.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 2
        pan.allowedScrollTypesMask = .continuous
        pan.delegate = self
        addGestureRecognizer(pan)

        // Mouse wheel: zoom at the pointer.
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(handleWheel))
        wheel.maximumNumberOfTouches = 0
        wheel.allowedScrollTypesMask = .discrete
        wheel.delegate = self
        addGestureRecognizer(wheel)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        addGestureRecognizer(twoFingerTap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        g.view === other.view
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Touching the map catches a glide, as in a scroll view.
        stopMomentum()
        super.touchesBegan(touches, with: event)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopMomentum() }
    }

    // MARK: Recognizers

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopMomentum()
            touchCount = g.numberOfTouches
            pinchedDuringPan = false
            g.setTranslation(.zero, in: self)
        case .changed:
            // Lifting or adding a finger moves the midpoint; skip that jump.
            if g.numberOfTouches != touchCount {
                touchCount = g.numberOfTouches
                g.setTranslation(.zero, in: self)
                return
            }
            let t = g.translation(in: self)
            g.setTranslation(.zero, in: self)
            handlers.pan(CGSize(width: t.x, height: t.y))
        case .ended:
            if !pinchedDuringPan { startMomentum(g.velocity(in: self)) }
        default:
            break
        }
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            stopMomentum()
            pinchedDuringPan = true
            // With one finger lifted the anchor jumps; wait for two again.
            // (A trackpad pinch has no touches and always counts.)
            if g.numberOfTouches != 1 {
                handlers.zoom(g.scale, g.location(in: self))
            }
            g.scale = 1
        case .ended, .cancelled, .failed:
            handlers.zoomEnded()
        default:
            break
        }
    }

    @objc private func handleWheel(_ g: UIPanGestureRecognizer) {
        guard g.state == .began || g.state == .changed else { return }
        stopMomentum()
        let dy = g.translation(in: self).y
        g.setTranslation(.zero, in: self)
        // Wheel up zooms in, about 2× per 170 points of scrolling.
        handlers.zoom(exp(dy / 250), g.location(in: self))
    }

    @objc private func handleDoubleTap(_ g: UITapGestureRecognizer) {
        handlers.doubleTap(g.location(in: self))
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        handlers.twoFingerTap(g.location(in: self))
    }

    // MARK: Momentum

    private func startMomentum(_ velocity: CGPoint) {
        let speed = hypot(velocity.x, velocity.y)
        guard speed > 150 else { return }
        let cap: CGFloat = 6000
        momentum = speed > cap ? CGPoint(x: velocity.x * cap / speed, y: velocity.y * cap / speed) : velocity
        let link = CADisplayLink(target: self, selector: #selector(stepMomentum))
        link.add(to: .main, forMode: .common)
        displayLink = link
        lastFrame = 0
    }

    @objc private func stepMomentum(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastFrame == 0 ? link.duration : now - lastFrame
        lastFrame = now
        // UIScrollView's normal deceleration: 0.998 per millisecond.
        let decay = pow(0.998, dt * 1000)
        momentum.x *= decay
        momentum.y *= decay
        handlers.pan(CGSize(width: momentum.x * dt, height: momentum.y * dt))
        if hypot(momentum.x, momentum.y) < 20 { stopMomentum() }
    }

    private func stopMomentum() {
        displayLink?.invalidate()
        displayLink = nil
        momentum = .zero
    }
}

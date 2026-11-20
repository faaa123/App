import Flutter
import PencilKit
import UIKit

public class PencilCanvasPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // DoNotBlockGesture: touches go straight to PencilKit without waiting for
    // Flutter's gesture arena (no added input latency).
    registrar.register(
      PencilCanvasViewFactory(messenger: registrar.messenger()),
      withId: "pencil_canvas/view",
      gestureRecognizersBlockingPolicy:
        FlutterPlatformViewGestureRecognizersBlockingPolicyDoNotBlockGesture)
  }
}

final class PencilCanvasViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    PencilCanvasPlatformView(frame: frame, viewId: viewId, messenger: messenger)
  }
}

/// Temporary whiteboard. Apple Pencil draws, fingers pan/zoom. Nothing is persisted.
///
/// Squeeze (Apple Pencil Pro) and double-tap are handled by PKToolPicker itself:
/// with the "show contextual palette" setting, squeezing shows the tool palette
/// right at the hovering pencil tip. We deliberately install no UIPencilInteraction
/// of our own, because a custom squeeze handler would override that built-in behavior.
final class PencilCanvasPlatformView: NSObject, FlutterPlatformView {
  /// Board size relative to the visible area.
  private static let boardScale: CGFloat = 3

  private let container: BoardContainerView
  private let canvas = PKCanvasView()
  private let toolPicker = PKToolPicker()
  private let channel: FlutterMethodChannel
  private let initialTool = PKInkingTool(.pen, color: .black, width: 3)

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = BoardContainerView(frame: frame)
    channel = FlutterMethodChannel(name: "pencil_canvas/\(viewId)", binaryMessenger: messenger)
    super.init()

    canvas.drawingPolicy = .pencilOnly
    canvas.tool = initialTool
    canvas.backgroundColor = .white
    canvas.overrideUserInterfaceStyle = .light  // black ink on white even in dark mode
    canvas.isOpaque = true
    canvas.minimumZoomScale = 1 / Self.boardScale
    canvas.maximumZoomScale = 5
    canvas.bouncesZoom = true
    canvas.showsVerticalScrollIndicator = false
    canvas.showsHorizontalScrollIndicator = false
    canvas.frame = container.bounds
    canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(canvas)
    container.onFirstLayout = { [weak self] size in self?.setUpBoard(viewSize: size) }

    toolPicker.colorUserInterfaceStyle = .light
    toolPicker.selectedTool = initialTool
    toolPicker.addObserver(canvas)
    // Associate the picker with the canvas (hidden until squeezed / tools button).
    toolPicker.setVisible(false, forFirstResponder: canvas)

    addButtons()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "clear": self.clear()
      case "undo": self.canvas.undoManager?.undo()
      case "toggleTools": self.toggleToolPicker()
      default: return result(FlutterMethodNotImplemented)
      }
      result(nil)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    toolPicker.setVisible(false, forFirstResponder: canvas)
    toolPicker.removeObserver(canvas)
  }

  func view() -> UIView { container }

  // MARK: - Board

  private func setUpBoard(viewSize: CGSize) {
    canvas.contentSize = CGSize(
      width: viewSize.width * Self.boardScale, height: viewSize.height * Self.boardScale)
    // Start in the middle of the board.
    canvas.contentOffset = CGPoint(
      x: (canvas.contentSize.width - viewSize.width) / 2,
      y: (canvas.contentSize.height - viewSize.height) / 2)
    canvas.becomeFirstResponder()
  }

  private func clear() {
    canvas.drawing = PKDrawing()
  }

  // MARK: - Tool picker

  private func toggleToolPicker() {
    canvas.becomeFirstResponder()
    toolPicker.setVisible(!toolPicker.isVisible, forFirstResponder: canvas)
  }

  // MARK: - Native buttons (avoid Flutter overlays above the canvas)

  private func addButtons() {
    // Top-left: app menu (the Flutter side shows/hides its navigation).
    addToolbar(
      [
        makeButton("sidebar.left", label: "メニュー") { [weak self] in
          self?.channel.invokeMethod("menu", arguments: nil)
        }
      ], leading: true)
    // Top-right: drawing controls.
    addToolbar(
      [
        makeButton("pencil.tip.crop.circle", label: "ツール") { [weak self] in
          self?.toggleToolPicker()
        },
        makeButton("arrow.uturn.backward", label: "元に戻す") { [weak self] in
          self?.canvas.undoManager?.undo()
        },
        makeButton("trash", label: "全消去") { [weak self] in self?.clear() },
      ], leading: false)
  }

  private func addToolbar(_ buttons: [UIButton], leading: Bool) {
    let stack = UIStackView(arrangedSubviews: buttons)
    stack.axis = .horizontal
    stack.spacing = 4
    stack.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    stack.isLayoutMarginsRelativeArrangement = true
    stack.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
    stack.layer.cornerRadius = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    let guide = container.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
      leading
        ? stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12)
        : stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
    ])
  }

  private func makeButton(_ symbol: String, label: String, action: @escaping () -> Void)
    -> UIButton
  {
    let button = UIButton(
      type: .system, primaryAction: UIAction(image: UIImage(systemName: symbol)) { _ in action() })
    button.accessibilityLabel = label
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    return button
  }
}

/// Hosts the canvas. Reports its first non-zero size, and stops Flutter from
/// mirroring every pencil sample into Dart.
final class BoardContainerView: UIView {
  var onFirstLayout: ((CGSize) -> Void)?

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override init(frame: CGRect) {
    super.init(frame: frame)
  }

  override func didMoveToSuperview() {
    super.didMoveToSuperview()
    stopFlutterTouchForwarding()
  }

  /// Flutter recreates its forwarding recognizer after each gesture, so the cut is
  /// re-applied here: UIKit hit-tests before any recognizer sees touchesBegan, so
  /// the new recognizer is disabled before it can forward the pen-down.
  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    stopFlutterTouchForwarding()
    return super.hitTest(point, with: event)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, let callback = onFirstLayout else { return }
    onFirstLayout = nil
    callback(bounds.size)
  }

  /// Flutter wraps platform views in a view whose "ForwardingGestureRecognizer"
  /// re-sends every touch (up to 240 Hz for Apple Pencil) to the Dart side, on the
  /// main thread PencilKit also uses. No Flutter widget lives inside the board, so
  /// that work is pure overhead: disable it. Matching by class name is deliberate;
  /// if Flutter renames it, this silently does nothing and the board still works.
  private func stopFlutterTouchForwarding() {
    guard let host = superview else { return }
    for recognizer in host.gestureRecognizers ?? []
    where recognizer.isEnabled
      && NSStringFromClass(type(of: recognizer)).contains("ForwardingGestureRecognizer")
    {
      recognizer.isEnabled = false
    }
  }
}

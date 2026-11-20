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
/// Squeezing Apple Pencil Pro (or tapping the tools button) toggles the system tool picker.
final class PencilCanvasPlatformView: NSObject, FlutterPlatformView, UIPencilInteractionDelegate {
  /// Board size relative to the visible area.
  private static let boardScale: CGFloat = 3

  private let container: BoardContainerView
  private let canvas = PKCanvasView()
  private let toolPicker = PKToolPicker()
  private let channel: FlutterMethodChannel
  private var lastInkingTool: PKTool = PKInkingTool(.pen, color: .black, width: 3)

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = BoardContainerView(frame: frame)
    channel = FlutterMethodChannel(name: "pencil_canvas/\(viewId)", binaryMessenger: messenger)
    super.init()

    canvas.drawingPolicy = .pencilOnly
    canvas.tool = lastInkingTool
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
    toolPicker.selectedTool = lastInkingTool
    toolPicker.addObserver(canvas)
    toolPicker.setVisible(false, forFirstResponder: canvas)

    let pencil = UIPencilInteraction()
    pencil.delegate = self
    container.addInteraction(pencil)

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

  private func toggleEraser() {
    if canvas.tool is PKEraserTool {
      canvas.tool = lastInkingTool
    } else {
      lastInkingTool = canvas.tool
      canvas.tool = PKEraserTool(.vector)
    }
    toolPicker.selectedTool = canvas.tool
  }

  // MARK: - Apple Pencil

  @available(iOS 17.5, *)
  func pencilInteraction(
    _ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze
  ) {
    guard squeeze.phase == .ended else { return }
    switch UIPencilInteraction.preferredSqueezeAction {
    case .ignore: break
    case .switchEraser, .switchPrevious: toggleEraser()
    default: toggleToolPicker()  // .showContextualPalette etc.
    }
  }

  // MARK: - Native buttons (avoid Flutter overlays above the canvas)

  private func addButtons() {
    let stack = UIStackView(arrangedSubviews: [
      makeButton("pencil.tip.crop.circle", label: "ツール") { [weak self] in
        self?.toggleToolPicker()
      },
      makeButton("arrow.uturn.backward", label: "元に戻す") { [weak self] in
        self?.canvas.undoManager?.undo()
      },
      makeButton("trash", label: "全消去") { [weak self] in self?.clear() },
    ])
    stack.axis = .horizontal
    stack.spacing = 4
    stack.layoutMargins = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
    stack.isLayoutMarginsRelativeArrangement = true
    stack.backgroundColor = UIColor.secondarySystemBackground.withAlphaComponent(0.9)
    stack.layer.cornerRadius = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 12),
      stack.trailingAnchor.constraint(
        equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -12),
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

/// Reports its first non-zero size so the board can be sized to the view.
final class BoardContainerView: UIView {
  var onFirstLayout: ((CGSize) -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0, let callback = onFirstLayout else { return }
    onFirstLayout = nil
    callback(bounds.size)
  }
}

import Flutter
import PencilKit
import UIKit

public class PencilCanvasPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    registrar.register(
      PencilCanvasViewFactory(messenger: registrar.messenger()),
      withId: "pencil_canvas/view")
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

/// Pen-only, Apple Pencil-only canvas. Nothing is persisted.
final class PencilCanvasPlatformView: NSObject, FlutterPlatformView {
  private let canvas: PKCanvasView
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    canvas = PKCanvasView(frame: frame)
    canvas.drawingPolicy = .pencilOnly
    canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
    canvas.backgroundColor = .white
    canvas.overrideUserInterfaceStyle = .light  // keep black ink on white in dark mode
    canvas.isOpaque = true
    canvas.isScrollEnabled = false
    canvas.alwaysBounceVertical = false

    channel = FlutterMethodChannel(
      name: "pencil_canvas/\(viewId)", binaryMessenger: messenger)
    super.init()

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "clear":
        self.canvas.drawing = PKDrawing()
        result(nil)
      case "undo":
        self.canvas.undoManager?.undo()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView { canvas }
}

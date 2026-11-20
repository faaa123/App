import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Controls a [PencilCanvas] once its native view has been created.
class PencilCanvasController {
  PencilCanvasController._(int viewId, VoidCallback? onMenu)
      : _channel = MethodChannel('pencil_canvas/$viewId') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'menu') onMenu?.call();
    });
  }

  final MethodChannel _channel;

  /// Erases everything on the board.
  Future<void> clear() => _channel.invokeMethod<void>('clear');

  /// Undoes the last stroke.
  Future<void> undo() => _channel.invokeMethod<void>('undo');

  /// Shows or hides the system tool picker.
  Future<void> toggleTools() => _channel.invokeMethod<void>('toggleTools');
}

/// A PencilKit whiteboard (iOS only).
///
/// Apple Pencil draws, fingers pan and pinch-zoom. Squeezing Apple Pencil Pro
/// toggles the tool picker. Tool / undo / clear buttons are drawn natively on
/// top of the canvas so no Flutter overlay sits above it. Nothing is saved.
/// With the system squeeze setting "contextual palette", PencilKit shows the
/// tool palette at the hovering pencil tip.
///
/// On other platforms a placeholder is shown.
class PencilCanvas extends StatelessWidget {
  const PencilCanvas({super.key, this.onCreated, this.onMenu});

  final ValueChanged<PencilCanvasController>? onCreated;

  /// Called when the native menu button (top-left) is tapped.
  final VoidCallback? onMenu;

  static const _viewType = 'pencil_canvas/view';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(child: Text('この機能は iPad でのみ利用できます'));
    }
    return UiKitView(
      viewType: _viewType,
      onPlatformViewCreated: (id) {
        // Always create it: it also listens for the native menu button.
        final controller = PencilCanvasController._(id, onMenu);
        onCreated?.call(controller);
      },
    );
  }
}

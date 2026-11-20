import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Controls a [PencilCanvas] once its native view has been created.
class PencilCanvasController {
  PencilCanvasController._(int viewId)
      : _channel = MethodChannel('pencil_canvas/$viewId');

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
///
/// On other platforms a placeholder is shown.
class PencilCanvas extends StatelessWidget {
  const PencilCanvas({super.key, this.onCreated});

  final ValueChanged<PencilCanvasController>? onCreated;

  static const _viewType = 'pencil_canvas/view';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const Center(child: Text('この機能は iPad でのみ利用できます'));
    }
    return UiKitView(
      viewType: _viewType,
      onPlatformViewCreated: (id) =>
          onCreated?.call(PencilCanvasController._(id)),
    );
  }
}

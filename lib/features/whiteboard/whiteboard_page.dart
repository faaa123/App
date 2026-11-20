import 'package:material_ui/material_ui.dart';
import 'package:pencil_canvas/pencil_canvas.dart';

/// Temporary whiteboard: Apple Pencil, pen only, nothing is saved.
class WhiteboardPage extends StatefulWidget {
  const WhiteboardPage({super.key});

  @override
  State<WhiteboardPage> createState() => _WhiteboardPageState();
}

class _WhiteboardPageState extends State<WhiteboardPage> {
  PencilCanvasController? _controller;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      children: [
        Positioned.fill(
          child: PencilCanvas(
            onCreated: (c) => setState(() => _controller = c),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Card(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '元に戻す',
                  icon: const Icon(Icons.undo),
                  onPressed: controller?.undo,
                ),
                IconButton(
                  tooltip: '全消去',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: controller?.clear,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

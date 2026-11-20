import 'package:material_ui/material_ui.dart';
import 'package:pencil_canvas/pencil_canvas.dart';

/// Temporary whiteboard: nothing is saved.
/// Controls (tools / undo / clear) are native, inside [PencilCanvas].
class WhiteboardPage extends StatelessWidget {
  const WhiteboardPage({super.key});

  @override
  Widget build(BuildContext context) => const PencilCanvas();
}

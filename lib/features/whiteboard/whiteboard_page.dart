import 'package:material_ui/material_ui.dart';
import 'package:pencil_canvas/pencil_canvas.dart';

import '../../app/shell.dart';

/// Temporary whiteboard: nothing is saved. Full screen; the native menu
/// button (top-left) toggles the app navigation. Tools / undo / clear are
/// native too, inside [PencilCanvas].
class WhiteboardPage extends StatelessWidget {
  const WhiteboardPage({super.key});

  @override
  Widget build(BuildContext context) =>
      PencilCanvas(onMenu: ShellScope.maybeOf(context)?.toggleNavigation);
}

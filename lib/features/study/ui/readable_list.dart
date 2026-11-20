import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// A [ListView] whose content is capped at [maxWidth] and centered, so cards
/// do not stretch across a large landscape iPad. The side gutter never drops
/// below [gutter], and the list still scrolls from the full width.
class ReadableListView extends StatelessWidget {
  const ReadableListView({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.gutter = 24,
    this.top = 8,
    this.bottom = 48,
  });

  final List<Widget> children;
  final double maxWidth;
  final double gutter;
  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = max(gutter, (box.maxWidth - maxWidth) / 2);
      return ListView(
        padding: EdgeInsets.fromLTRB(side, top, side, bottom),
        children: children,
      );
    },
  );
}

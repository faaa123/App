import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/block.dart';
import '../core/logical_day.dart';
import 'study_scope.dart';

/// Today's blocks as one horizontal band: past = filled, current = partly
/// filled, future = outlined, free time = empty gap, rest = half height. [blocks] must be sorted
/// by start (as `StudyController.blocks` is).
class DayBand extends StatelessWidget {
  const DayBand({super.key, required this.blocks, required this.nowOffset});

  final List<Block> blocks;
  final int nowOffset;

  @override
  Widget build(BuildContext context) {
    final s = blocks;
    final from = s.first.start, to = s.last.end;
    final text = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label:
              '本日 ${LogicalDay.clock(from)}〜${LogicalDay.clock(to)}、'
              '${s.length}ブロック',
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: _BandPainter(
                blocks: s,
                from: from,
                to: to,
                now: nowOffset,
                nowColor: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(LogicalDay.clock(from), style: text),
            const Spacer(),
            Text(LogicalDay.clock(to), style: text),
          ],
        ),
      ],
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({
    required this.blocks,
    required this.from,
    required this.to,
    required this.now,
    required this.nowColor,
  });

  final List<Block> blocks;
  final int from;
  final int to;
  final int now;
  final Color nowColor;

  @override
  void paint(Canvas canvas, Size size) {
    final span = (to - from).toDouble();
    double x(int o) => (o - from) / span * size.width;
    for (final b in blocks) {
      final color = BlockStyle.of(b.type).mark;
      // Shape tells study and rest apart too: rest is drawn half height.
      final rest = b.type == BlockType.rest;
      final top = rest ? size.height * 0.25 : 0.0;
      final bottom = rest ? size.height * 0.75 : size.height;
      final rect = Rect.fromLTRB(x(b.start) + 1, top, x(b.end) - 1, bottom);
      final r = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      // Future part: faint fill + outline.
      canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.18));
      canvas.drawRRect(
        r.deflate(1),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      // Done part.
      final doneEnd = now >= b.end ? b.end : (now > b.start ? now : b.start);
      if (doneEnd > b.start) {
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, top, x(doneEnd), bottom));
        canvas.drawRRect(r, Paint()..color = color);
        canvas.restore();
      }
    }
    if (now >= from && now <= to) {
      canvas.drawLine(
        Offset(x(now), -4),
        Offset(x(now), size.height + 4),
        Paint()
          ..color = nowColor
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BandPainter old) =>
      // The list is rebuilt every second but holds the same Block instances
      // between edits; repaint only when the minute or the blocks change.
      old.now != now ||
      old.nowColor != nowColor ||
      !listEquals(old.blocks, blocks);
}

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
        LayoutBuilder(
          builder: (context, box) {
            final small = Theme.of(context).textTheme.labelSmall;
            final w = box.maxWidth;
            // Clock labels every 2 or 3 hours, dropped where they would
            // crowd a neighbour or the start / end labels.
            final step = (to - from) > 12 * 60 ? 3 : 2;
            final marks = <(double, int)>[];
            var last = 0.0;
            for (final h in _hourOffsets(from, to)) {
              if (LogicalDay.clockParts(h).$1 % step != 0) continue;
              final x = (h - from) / (to - from) * w;
              if (x - last < _minLabelGap || w - x < _minLabelGap) continue;
              marks.add((x, h));
              last = x;
            }
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  children: [
                    Text(LogicalDay.clock(from), style: text),
                    const Spacer(),
                    Text(LogicalDay.clock(to), style: text),
                  ],
                ),
                for (final (x, h) in marks)
                  Positioned(
                    left: x,
                    top: 0,
                    child: ExcludeSemantics(
                      child: FractionalTranslation(
                        translation: const Offset(-0.5, 0),
                        child: Text(LogicalDay.clock(h), style: small),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Distance kept between label centres (and from the end labels).
  static const _minLabelGap = 56.0;
}

/// Offsets of the full hours strictly between [from] and [to]. The logical
/// day starts at 4:00, so full hours are the multiples of 60.
Iterable<int> _hourOffsets(int from, int to) sync* {
  for (var h = (from ~/ 60 + 1) * 60; h < to; h += 60) {
    yield h;
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
    // Faint hour ticks behind the blocks.
    final tick = Paint()
      ..color = nowColor.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    for (final h in _hourOffsets(from, to)) {
      canvas.drawLine(Offset(x(h), 0), Offset(x(h), size.height), tick);
    }
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

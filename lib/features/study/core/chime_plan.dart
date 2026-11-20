import 'block.dart';
import 'logical_day.dart';

/// A study⇄rest switch moment.
class Chime {
  const Chime(this.at, this.next);
  final DateTime at;
  final Block next;
}

/// Switch moments after [now], over [days] logical days starting today.
///
/// A chime happens only where one block ends exactly when a block of the other
/// type starts: the start/end of free time and the end of the day are silent.
/// [scheduleFor] returns the schedule in effect on a logical date, so weekday
/// presets on future days are taken into account.
List<Chime> planChimes({
  required DateTime now,
  required int days,
  required List<Block> Function(DateTime logicalDate) scheduleFor,
  int limit = 60,
}) {
  final out = <Chime>[];
  final today = LogicalDay.dateOf(now);
  Block? prevDayLast;
  for (var i = 0; i < days; i++) {
    final date = LogicalDay.addDays(today, i);
    final s = sortedByStart(scheduleFor(date));
    // 4:00 boundary between the previous day's last block and today's first.
    if (s.isNotEmpty &&
        prevDayLast != null &&
        prevDayLast.end == LogicalDay.minutesPerDay &&
        s.first.start == 0 &&
        prevDayLast.type != s.first.type) {
      _add(out, LogicalDay.toDateTime(date, 0), s.first, now);
    }
    for (var j = 0; j < s.length - 1; j++) {
      if (s[j].end == s[j + 1].start && s[j].type != s[j + 1].type) {
        _add(out, LogicalDay.toDateTime(date, s[j + 1].start), s[j + 1], now);
      }
    }
    prevDayLast = s.lastOrNull;
    if (out.length >= limit) break;
  }
  return out.length > limit ? out.sublist(0, limit) : out;
}

void _add(List<Chime> out, DateTime at, Block next, DateTime now) {
  if (at.isAfter(now)) out.add(Chime(at, next));
}

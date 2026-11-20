import 'block.dart';
import 'logical_day.dart';

/// Planned study minutes for the whole day.
int totalStudyMinutes(List<Block> blocks) =>
    blocks.where((b) => b.isStudy).fold(0, (sum, b) => sum + b.duration);

/// Study minutes elapsed by [offset]: finished blocks fully, the running one
/// partially, future ones not at all.
int elapsedStudyMinutes(List<Block> blocks, int offset) =>
    blocks.where((b) => b.isStudy).fold(0, (sum, b) {
      if (offset >= b.end) return sum + b.duration;
      if (offset > b.start) return sum + offset - b.start;
      return sum;
    });

/// Consecutive achieved days ending today. Today not yet achieved does not
/// break the streak (the day isn't over). Missing days count as not achieved.
int calculateStreak({
  required DateTime today,
  required Map<String, int> minutesByDate,
  required int threshold,
}) {
  if (threshold <= 0) throw ArgumentError('threshold must be > 0');
  var streak =
      (minutesByDate[LogicalDay.dateKey(today)] ?? 0) >= threshold ? 1 : 0;
  var d = LogicalDay.addDays(today, -1);
  while ((minutesByDate[LogicalDay.dateKey(d)] ?? 0) >= threshold) {
    streak++;
    d = LogicalDay.addDays(d, -1);
  }
  return streak;
}

import 'block.dart';
import 'logical_day.dart';

/// What the main screen shows for "now".
sealed class NowStatus {
  const NowStatus();
}

class InBlock extends NowStatus {
  const InBlock({
    required this.block,
    required this.remainingSeconds,
    required this.progress,
    this.next,
    this.secondsUntilNext,
  });
  final Block block;
  final int remainingSeconds;
  final double progress;
  final Block? next;
  final int? secondsUntilNext;
}

class Free extends NowStatus {
  const Free({required this.next, required this.secondsUntilNext});
  final Block next;
  final int secondsUntilNext;
}

class DayEnded extends NowStatus {
  const DayEnded({this.secondsUntilTomorrowFirst});

  /// Null when there is no schedule at all.
  final int? secondsUntilTomorrowFirst;
}

/// Resolve the status at [now] for today's [blocks]. Block membership is
/// decided by the minute (like the Android app); countdowns use seconds.
NowStatus resolveNow(List<Block> blocks, DateTime now) {
  final offset = LogicalDay.offsetOf(now);
  final nowSec = offset * 60 + now.second;
  final s = sortedByStart(blocks);
  final current = s.where((b) => b.contains(offset)).firstOrNull;
  if (current != null) {
    final next = s.where((b) => b.start >= current.end).firstOrNull;
    final elapsed = nowSec - current.start * 60;
    return InBlock(
      block: current,
      remainingSeconds: current.end * 60 - nowSec,
      progress: (elapsed / (current.duration * 60)).clamp(0.0, 1.0),
      next: next,
      secondsUntilNext: next == null ? null : next.start * 60 - nowSec,
    );
  }
  final next = s.where((b) => b.start > offset).firstOrNull;
  if (next != null) {
    return Free(next: next, secondsUntilNext: next.start * 60 - nowSec);
  }
  final first = s.firstOrNull;
  return DayEnded(
    secondsUntilTomorrowFirst: first == null
        ? null
        : LogicalDay.minutesPerDay * 60 - nowSec + first.start * 60,
  );
}

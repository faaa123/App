import 'block.dart';
import 'logical_day.dart';

/// Returns an error message, or null when [blocks] don't overlap. Gaps are fine.
String? validateSchedule(List<Block> blocks) {
  final s = sortedByStart(blocks);
  for (var i = 0; i < s.length - 1; i++) {
    if (s[i].end > s[i + 1].start) {
      final a = s[i], b = s[i + 1];
      return '「${a.name}」(${_range(a)})と「${b.name}」(${_range(b)})の時間が重なっています';
    }
  }
  return null;
}

String _range(Block b) => '${LogicalDay.clock(b.start)}〜${LogicalDay.clock(b.end)}';

/// Result of an edit: the whole new schedule, or an error.
class EditResult {
  const EditResult.ok(List<Block> this.blocks) : error = null;
  const EditResult.fail(String this.error) : blocks = null;
  final List<Block>? blocks;
  final String? error;
  bool get isOk => blocks != null;
}

String _rangeError(String name) => '「$name」が1日の区切り（翌朝4:00）を越えるか、不正な時刻です';

bool _validRange(int s, int e) =>
    s >= 0 && e <= LogicalDay.minutesPerDay && e > s;

/// Change only the target block's time.
EditResult applySingleChange(
  List<Block> blocks,
  String id,
  int newStart,
  int newEnd,
) {
  final target = blocks.where((b) => b.id == id).firstOrNull;
  if (target == null) return const EditResult.fail('対象ブロックが見つかりません');
  if (!_validRange(newStart, newEnd)) {
    return EditResult.fail(_rangeError(target.name));
  }
  final updated = [
    for (final b in blocks)
      b.id == id ? b.copyWith(start: newStart, end: newEnd) : b,
  ];
  final err = validateSchedule(updated);
  return err == null ? EditResult.ok(updated) : EditResult.fail(err);
}

/// Change the target and shift every later block by (new end − old end).
/// Never clamps: overlap or crossing 4:00 is an error.
EditResult applyCascadeShift(
  List<Block> blocks,
  String id,
  int newStart,
  int newEnd,
) {
  final target = blocks.where((b) => b.id == id).firstOrNull;
  if (target == null) return const EditResult.fail('対象ブロックが見つかりません');
  if (!_validRange(newStart, newEnd)) {
    return EditResult.fail(_rangeError(target.name));
  }
  final shift = newEnd - target.end;
  final updated = <Block>[];
  for (final b in blocks) {
    var s = b.start, e = b.end;
    if (b.id == id) {
      s = newStart;
      e = newEnd;
    } else if (b.start >= target.start && shift != 0) {
      s += shift;
      e += shift;
    }
    if (!_validRange(s, e)) {
      return EditResult.fail('「${b.name}」が1日の区切り（翌朝4:00）を越えるか、開始前になります');
    }
    updated.add(b.copyWith(start: s, end: e));
  }
  final err = validateSchedule(updated);
  return err == null ? EditResult.ok(updated) : EditResult.fail(err);
}

/// Drag reorder: gaps stay at their slot positions, blocks keep their
/// durations and are laid out in [newOrder]. Null if it would pass 4:00.
List<Block>? reorderSchedule(List<Block> blocks, List<String> newOrder) {
  final s = sortedByStart(blocks);
  if (s.isEmpty) return const [];
  final gaps = [
    for (var i = 0; i < s.length - 1; i++) s[i + 1].start - s[i].end,
  ];
  final byId = {for (final b in s) b.id: b};
  var t = s.first.start;
  final out = <Block>[];
  for (var i = 0; i < newOrder.length; i++) {
    final b = byId[newOrder[i]]!;
    final end = t + b.duration;
    if (end > LogicalDay.minutesPerDay) return null;
    out.add(b.copyWith(start: t, end: end));
    t = end + (i < gaps.length ? gaps[i] : 0);
  }
  return out;
}

/// Fill [start, end) with study/rest repeats. The last block is truncated at
/// [end]. [restMinutes] == 0 means study blocks only.
List<Block> pomodoroFill({
  required int start,
  required int end,
  required int studyMinutes,
  required int restMinutes,
  required String Function() newId,
}) {
  if (studyMinutes <= 0 || restMinutes < 0 || end <= start) return const [];
  final out = <Block>[];
  var cursor = start, studyN = 0, restN = 0;
  var studyTurn = true;
  while (cursor < end) {
    final want = studyTurn ? studyMinutes : restMinutes;
    if (want <= 0) {
      studyTurn = true;
      continue;
    }
    final blockEnd = cursor + want < end ? cursor + want : end;
    out.add(
      Block(
        id: newId(),
        name: studyTurn ? '勉強${++studyN}' : '休憩${++restN}',
        type: studyTurn ? BlockType.study : BlockType.rest,
        start: cursor,
        end: blockEnd,
      ),
    );
    cursor = blockEnd;
    studyTurn = !studyTurn;
  }
  return out;
}

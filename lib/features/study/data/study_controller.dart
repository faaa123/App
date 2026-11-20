import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/block.dart';
import '../core/chime_plan.dart';
import '../core/logical_day.dart';
import '../core/schedule_rules.dart';
import '../core/stats.dart';
import 'chime_scheduler.dart';
import 'study_data.dart';
import 'study_store.dart';

/// State and operations of the study feature. There is a single schedule:
/// edits are permanent. Weekday presets replace it when their day arrives.
class StudyController extends ChangeNotifier {
  StudyController({
    required this._store,
    required this._chimes,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  final StudyStore _store;
  final ChimeScheduler _chimes;

  /// Single source of the current time (swap in tests).
  final DateTime Function() now;

  StudyData _data = StudyData();
  DateTime? _currentDay;
  Timer? _dayTimer;
  final _rand = Random();

  static const _keepSummaryDays = 120;
  static const _backfillDays = 90;
  static const _chimeDays = 7;

  List<Block> get blocks => sortedByStart(_data.blocks);
  List<Preset> get presets => List.unmodifiable(_data.presets);
  int get threshold => _data.threshold;
  DateTime get today => LogicalDay.dateOf(now());

  String newId() =>
      '${now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rand.nextInt(1 << 30).toRadixString(36)}';

  /// Loads the data and rolls over to today; only this is awaited before the
  /// first frame. Notification setup, saving and chime planning follow in the
  /// background (the scheduler runs them after its own init).
  Future<void> init() async {
    try {
      final json = await _store.load();
      if (json != null) {
        _data = StudyData.fromJson(json);
        // Keep the original before any save drops what could not be parsed.
        if (_data.lossy) {
          await _store.keepCopy('partial').catchError((Object e) {
            debugPrint('study backup failed: $e');
          });
        }
      }
    } catch (e) {
      debugPrint('study data unreadable, starting fresh: $e');
      _data = StudyData();
    }
    final day = today;
    _currentDay = day;
    final changed = _rollOver(day);
    _armDayTimer();
    unawaited(
      _chimes.init().catchError((Object e) {
        debugPrint('chime init failed: $e');
      }),
    );
    if (changed) unawaited(_save().catchError(_logSaveError));
    unawaited(_replanChimes());
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _dayTimer?.cancel();
    super.dispose();
  }

  /// Fires just after the next 4:00 so the new day shows without delay.
  void _armDayTimer() {
    _dayTimer?.cancel();
    if (_disposed) return;
    final next = LogicalDay.toDateTime(LogicalDay.addDays(today, 1), 0);
    final wait = next.difference(now()) + const Duration(seconds: 1);
    _dayTimer = Timer(wait.isNegative ? Duration.zero : wait, () async {
      await refresh();
      _armDayTimer();
    });
  }

  /// Call on resume (and from the 4:00 timer). Finalizes past days, applies
  /// today's weekday preset and re-plans chimes when the logical day changed.
  Future<void> refresh({bool force = false}) async {
    final day = today;
    if (!force && day == _currentDay) return;
    _currentDay = day;
    final changed = _rollOver(day);
    _armDayTimer();
    notifyListeners();
    unawaited(_replanChimes());
    if (changed) await _save();
  }

  // ---------------------------------------------------------------- schedule

  /// Replace the schedule (already validated by the caller).
  Future<void> setBlocks(List<Block> blocks) async {
    _data.blocks = sortedByStart(blocks);
    await _commit();
  }

  /// Adds [block]; returns an error message or null.
  Future<String?> addBlock(Block block) => _tryApply([..._data.blocks, block]);

  Future<String?> addBlocks(List<Block> added) =>
      _tryApply([..._data.blocks, ...added]);

  Future<void> deleteBlock(String id) =>
      setBlocks(_data.blocks.where((b) => b.id != id).toList());

  Future<void> deleteAll() => setBlocks(const []);

  /// Returns an error message or null.
  Future<String?> reorder(List<String> newOrder) async {
    final r = reorderSchedule(_data.blocks, newOrder);
    if (r == null) return '並び替えると1日の区切り（翌朝4:00）を越えます';
    await setBlocks(r);
    return null;
  }

  Future<String?> _tryApply(List<Block> next) async {
    final err = validateSchedule(next);
    if (err != null) return err;
    await setBlocks(next);
    return null;
  }

  // ----------------------------------------------------------------- presets

  Future<void> saveAsPreset(String name) async {
    _data.presets.add(
      Preset(
        id: newId(),
        name: name,
        blocks: [for (final b in _data.blocks) b],
        updatedAt: now(),
      ),
    );
    // A new preset has no weekdays, so the chime plan is unchanged.
    notifyListeners();
    await _save();
  }

  Future<void> applyPreset(String id) async {
    final p = _data.presets.firstWhere((p) => p.id == id);
    await setBlocks(_freshIds(p.blocks));
  }

  Future<void> deletePreset(String id) async {
    _data.presets.removeWhere((p) => p.id == id);
    await _commit();
  }

  Future<void> setPresetWeekdays(String id, Set<int> weekdays) async {
    final i = _data.presets.indexWhere((p) => p.id == id);
    // "The preset linked later wins" (D-2): only adding a weekday counts as
    // linking, so removing one does not take over other shared weekdays.
    final added = weekdays.difference(_data.presets[i].weekdays).isNotEmpty;
    _data.presets[i] = _data.presets[i].copyWith(
      weekdays: weekdays,
      updatedAt: added ? now() : null,
    );
    await _commit();
  }

  Preset? presetForWeekday(int weekday) {
    Preset? best;
    for (final p in _data.presets) {
      if (p.weekdays.contains(weekday) &&
          (best == null || p.updatedAt.isAfter(best.updatedAt))) {
        best = p;
      }
    }
    return best;
  }

  // ------------------------------------------------------------------- stats

  Future<void> setThreshold(int minutes) async {
    _data.threshold = max(10, minutes);
    notifyListeners();
    await _save();
  }

  /// Planned study minutes per logical date, including today (live).
  Map<String, int> minutesByDate() => {
    ..._data.summaries,
    LogicalDay.dateKey(today): totalStudyMinutes(_data.blocks),
  };

  int streak() => calculateStreak(
    today: today,
    minutesByDate: minutesByDate(),
    threshold: _data.threshold,
  );

  // -------------------------------------------------------------- internals

  List<Block> _freshIds(List<Block> blocks) => [
    for (final b in blocks) b.copyWith(id: newId()),
  ];

  /// Schedule in effect on [date] (today or later), simulating weekday presets.
  List<Block> scheduleFor(DateTime date) {
    var sched = _data.blocks;
    var d = LogicalDay.addDays(today, 1);
    while (!d.isAfter(date)) {
      final p = presetForWeekday(LogicalDay.weekdayOf(d));
      if (p != null) sched = p.blocks;
      d = LogicalDay.addDays(d, 1);
    }
    return sched;
  }

  /// Finalizes days before [day] and, once per logical day, applies [day]'s
  /// weekday preset. Returns whether anything changed.
  bool _rollOver(DateTime day) {
    final yesterday = LogicalDay.addDays(day, -1);
    final last = _data.lastRecorded == null
        ? null
        : LogicalDay.parseDateKey(_data.lastRecorded!);
    var advanced = false;
    var changed = false;
    if (last == null) {
      // First run: no history to invent.
      _data.lastRecorded = LogicalDay.dateKey(yesterday);
      advanced = true;
    } else if (last.isBefore(yesterday)) {
      // Finalize the missing days. The stored schedule is the one in effect on
      // the last-used day (its preset was applied when that day began, then
      // possibly edited), so presets are only replayed for later days.
      final lastUsed = LogicalDay.addDays(last, 1);
      var sched = _data.blocks;
      var d = lastUsed;
      final floor = LogicalDay.addDays(yesterday, -_backfillDays);
      while (!d.isAfter(yesterday)) {
        if (d.isAfter(lastUsed)) {
          final p = presetForWeekday(LogicalDay.weekdayOf(d));
          if (p != null) sched = p.blocks;
        }
        if (d.isAfter(floor)) {
          _data.summaries[LogicalDay.dateKey(d)] = totalStudyMinutes(sched);
        }
        d = LogicalDay.addDays(d, 1);
      }
      if (!identical(sched, _data.blocks)) _data.blocks = _freshIds(sched);
      _data.lastRecorded = LogicalDay.dateKey(yesterday);
      advanced = true;
    } else if (last.isAfter(yesterday)) {
      // The clock went back (it was ahead, or a time-zone move): forget
      // summaries of days that have not finished yet, so rollover resumes
      // tomorrow. No preset apply: today may already have been edited.
      final todayKey = LogicalDay.dateKey(day);
      _data.summaries.removeWhere((k, _) => k.compareTo(todayKey) >= 0);
      _data.lastRecorded = LogicalDay.dateKey(yesterday);
      changed = true;
    }
    if (advanced) {
      // Today's weekday preset, only when the day begins (D-12): same-day
      // edits and manual applies survive restarts.
      final p = presetForWeekday(LogicalDay.weekdayOf(day));
      if (p != null && !sameSchedule(p.blocks, _data.blocks)) {
        _data.blocks = _freshIds(p.blocks);
      }
    }
    final cutoff = LogicalDay.dateKey(
      LogicalDay.addDays(day, -_keepSummaryDays),
    );
    final before = _data.summaries.length;
    _data.summaries.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    return advanced || changed || _data.summaries.length != before;
  }

  /// The in-memory data is already updated: show it first, then persist.
  Future<void> _commit() async {
    notifyListeners();
    unawaited(_replanChimes());
    await _save();
  }

  Future<void> _save() => _store.save(_data.toJson());

  static void _logSaveError(Object e) => debugPrint('study save failed: $e');

  Future<void> _replanChimes() => _chimes.replaceAll(
    planChimes(now: now(), days: _chimeDays, scheduleFor: scheduleFor),
  );
}

import 'dart:async';

import 'package:app/features/study/core/block.dart';
import 'package:app/features/study/core/chime_plan.dart';
import 'package:app/features/study/core/logical_day.dart';
import 'package:app/features/study/data/chime_scheduler.dart';
import 'package:app/features/study/data/study_controller.dart';
import 'package:app/features/study/data/study_store.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingChimes implements ChimeScheduler {
  List<Chime> last = const [];
  int calls = 0;
  @override
  Future<void> init() async {}
  @override
  Future<void> replaceAll(List<Chime> chimes) async {
    calls++;
    last = chimes;
  }
}

int o(int h, int m) => LogicalDay.toOffset(h, m);

void main() {
  late DateTime clock;
  late MemoryStudyStore store;
  late RecordingChimes chimes;

  StudyController make() =>
      StudyController(store: store, chimes: chimes, clock: () => clock);

  setUp(() {
    clock = DateTime(2026, 11, 20, 8); // Friday
    store = MemoryStudyStore();
    chimes = RecordingChimes();
  });

  Block blk(StudyController c, String name, BlockType t, int s, int e) =>
      Block(id: c.newId(), name: name, type: t, start: s, end: e);

  test('edits persist and re-plan chimes', () async {
    final c = make();
    await c.init();
    expect(await c.addBlock(blk(c, '勉強', BlockType.study, o(9, 0), o(10, 0))), isNull);
    expect(await c.addBlock(blk(c, '休憩', BlockType.rest, o(10, 0), o(10, 10))), isNull);
    expect(chimes.last.first.at, DateTime(2026, 11, 20, 10));
    expect(
      await c.addBlock(blk(c, '重複', BlockType.study, o(9, 30), o(9, 40))),
      isNotNull,
    );
    c.dispose();

    final reopened = make();
    await reopened.init();
    expect(reopened.blocks.map((b) => b.name), ['勉強', '休憩']);
    reopened.dispose();
  });

  test('resume on the same day re-plans chimes', () async {
    final c = make();
    await c.init();
    await c.addBlock(blk(c, '勉強', BlockType.study, o(9, 0), o(10, 0)));
    await c.addBlock(blk(c, '休憩', BlockType.rest, o(10, 0), o(10, 10)));
    final before = chimes.calls;
    clock = DateTime(2026, 11, 20, 8, 30); // same logical day
    await c.refresh();
    expect(chimes.calls, before + 1);
    expect(chimes.last.first.at, DateTime(2026, 11, 20, 10));
    c.dispose();
  });

  test('first run does not invent history; later days are finalized', () async {
    final c = make();
    await c.init();
    await c.addBlock(blk(c, 'a', BlockType.study, o(9, 0), o(10, 0)));
    expect(c.minutesByDate().length, 1); // only today

    clock = DateTime(2026, 11, 23, 9); // three days later
    await c.refresh();
    final m = c.minutesByDate();
    expect(m['2026-11-20'], 60);
    expect(m['2026-11-21'], 60);
    expect(m['2026-11-22'], 60);
    expect(c.streak(), 4); // 3 finished days + today (60 ≥ 30)
    c.dispose();
  });

  test('weekday preset applies on its day and in the chime plan', () async {
    final c = make();
    await c.init();
    await c.addBlock(blk(c, 'normal', BlockType.study, o(9, 0), o(10, 0)));
    await c.saveAsPreset('normal');
    await c.setBlocks([
      blk(c, 'sat', BlockType.study, o(13, 0), o(14, 0)),
      blk(c, 'satRest', BlockType.rest, o(14, 0), o(14, 30)),
    ]);
    await c.saveAsPreset('weekend');
    final weekend = c.presets.firstWhere((p) => p.name == 'weekend');
    await c.setPresetWeekdays(weekend.id, {6}); // Saturday
    await c.applyPreset(c.presets.firstWhere((p) => p.name == 'normal').id);

    // Friday's plan already contains Saturday's 14:00 switch.
    expect(chimes.last.map((x) => x.at), contains(DateTime(2026, 11, 21, 14)));

    clock = DateTime(2026, 11, 21, 4, 1); // Saturday
    await c.refresh();
    expect(c.blocks.map((b) => b.name), ['sat', 'satRest']);
    c.dispose();
  });

  test('unlinking a weekday does not take over shared weekdays', () async {
    final c = make();
    await c.init();
    await c.saveAsPreset('A');
    await c.saveAsPreset('B');
    final a = c.presets.firstWhere((p) => p.name == 'A').id;
    final b = c.presets.firstWhere((p) => p.name == 'B').id;
    await c.setPresetWeekdays(a, {1, 2});
    clock = clock.add(const Duration(minutes: 1));
    await c.setPresetWeekdays(b, {2}); // linked later: B wins Tuesday
    expect(c.presetForWeekday(2)?.name, 'B');

    clock = clock.add(const Duration(minutes: 1));
    await c.setPresetWeekdays(a, {2}); // only Monday removed
    expect(c.presetForWeekday(2)?.name, 'B');

    clock = clock.add(const Duration(minutes: 1));
    await c.setPresetWeekdays(a, {2, 3}); // adding links A again
    expect(c.presetForWeekday(2)?.name, 'A');
    c.dispose();
  });

  Future<StudyController> withSaturdayPreset() async {
    final c = make();
    await c.init();
    await c.setBlocks([blk(c, 'sat', BlockType.study, o(13, 0), o(14, 0))]);
    await c.saveAsPreset('weekend');
    await c.setPresetWeekdays(c.presets.single.id, {6}); // Saturday
    await c.setBlocks([blk(c, 'fri', BlockType.study, o(9, 0), o(10, 0))]);
    return c;
  }

  test('resuming after several days replays presets in between', () async {
    clock = DateTime(2026, 11, 19, 8); // Thursday
    final c = make();
    await c.init();
    await c.setBlocks([blk(c, 'sat', BlockType.study, o(13, 0), o(14, 0))]);
    await c.saveAsPreset('weekend');
    await c.setPresetWeekdays(c.presets.single.id, {6}); // Saturday
    await c.setBlocks([blk(c, 'normal', BlockType.study, o(9, 0), o(10, 30))]);

    clock = DateTime(2026, 11, 23, 8); // the following Monday
    await c.refresh();
    final m = c.minutesByDate();
    expect(m['2026-11-19'], 90);
    expect(m['2026-11-20'], 90);
    expect(m['2026-11-21'], 60);
    expect(m['2026-11-22'], 60); // Saturday's schedule carries over
    expect(c.blocks.map((b) => b.name), ['sat']);
    c.dispose();
  });

  test('edits on a preset day carry over and are recorded', () async {
    final c = await withSaturdayPreset();
    clock = DateTime(2026, 11, 21, 8); // Saturday
    await c.refresh();
    expect(c.blocks.map((b) => b.name), ['sat']);
    await c.setBlocks([blk(c, 'satEdited', BlockType.study, o(13, 0), o(15, 0))]);

    clock = DateTime(2026, 11, 22, 8); // Sunday, no preset
    await c.refresh();
    expect(c.minutesByDate()['2026-11-21'], 120);
    expect(c.blocks.map((b) => b.name), ['satEdited']);
    c.dispose();
  });

  test('same-day edits on a preset day survive a restart', () async {
    final c = await withSaturdayPreset();
    clock = DateTime(2026, 11, 21, 8); // Saturday
    await c.refresh();
    await c.setBlocks([blk(c, 'satEdited', BlockType.study, o(13, 0), o(15, 0))]);
    c.dispose();

    clock = DateTime(2026, 11, 21, 12);
    final reopened = make();
    await reopened.init();
    expect(reopened.blocks.map((b) => b.name), ['satEdited']);
    reopened.dispose();
  });

  test('a clock that went back resumes rollover and drops future days', () async {
    final c = make();
    await c.init();
    await c.addBlock(blk(c, 'a', BlockType.study, o(9, 0), o(10, 0)));
    clock = DateTime(2026, 11, 30, 8); // clock briefly ahead
    await c.refresh();
    expect(c.minutesByDate()['2026-11-25'], 60);

    clock = DateTime(2026, 11, 20, 12); // corrected
    await c.refresh(force: true);
    expect(
      c.minutesByDate().keys.where((k) => k.compareTo('2026-11-20') > 0),
      isEmpty,
    );

    await c.setBlocks([blk(c, 'sat', BlockType.study, o(13, 0), o(14, 0))]);
    await c.saveAsPreset('weekend');
    await c.setPresetWeekdays(c.presets.single.id, {6}); // Saturday
    await c.setBlocks([blk(c, 'fri', BlockType.study, o(9, 0), o(10, 0))]);

    clock = DateTime(2026, 11, 21, 8); // Saturday
    await c.refresh();
    expect(c.blocks.map((b) => b.name), ['sat']);
    expect(c.minutesByDate()['2026-11-20'], 60);
    expect(
      c.minutesByDate().keys.where((k) => k.compareTo('2026-11-21') > 0),
      isEmpty,
    );
    c.dispose();
  });

  test('malformed stored data does not block init', () async {
    store = MemoryStudyStore({
      'blocks': [
        {'id': 'x', 'name': 'a', 'type': 'study', 'start': 10, 'end': 5},
        {'id': 'y', 'name': 'b', 'type': 'nap', 'start': 10, 'end': 20},
        {'id': 'z', 'name': 'ok', 'type': 'study', 'start': 30, 'end': 60},
        {'id': 'w', 'name': 'overlap', 'type': 'rest', 'start': 40, 'end': 70},
        'garbage',
      ],
      'presets': [
        {'id': 'p', 'name': 3},
        {
          'id': 'q',
          'name': 'good',
          'blocks': [
            {'id': 'a', 'name': 'a', 'type': 'rest', 'start': 0, 'end': 9999},
          ],
          'weekdays': [1, 9],
          'updatedAt': 0,
        },
      ],
      'summaries': {'2026-11-01': 'many', '2026-11-02': 45, 'x': 5},
      'lastRecorded': 12,
      'threshold': 'x',
    });
    final c = make();
    await c.init();
    expect(c.blocks.map((b) => b.name), ['ok']);
    expect(c.presets.map((p) => p.name), ['good']);
    expect(c.presets.single.blocks, isEmpty);
    expect(c.presets.single.weekdays, {1});
    expect(c.threshold, 30);
    expect(c.minutesByDate().containsKey('x'), isFalse);
    expect(store.copies, ['partial']);
    c.dispose();
  });

  test('a cleanly parsed file is not copied aside', () async {
    final c = make();
    await c.init();
    await c.addBlock(blk(c, 'a', BlockType.study, o(9, 0), o(10, 0)));
    await c.saveAsPreset('p');
    await c.setPresetWeekdays(c.presets.single.id, {1});
    c.dispose();

    final reopened = make();
    await reopened.init();
    expect(store.copies, isEmpty);
    reopened.dispose();
  });

  test('a newer file version is copied aside before saving', () async {
    store = MemoryStudyStore({'version': 2, 'blocks': []});
    final c = make();
    await c.init();
    expect(store.copies, ['partial']);
    c.dispose();
  });

  test('a stored threshold of 0 or less falls back and stats still build', () async {
    for (final t in [0, -5]) {
      store = MemoryStudyStore({
        'threshold': t,
        'summaries': {'x': 10, '2026-11-19': -3, '2026-11-18': 40},
      });
      final c = make();
      await c.init();
      expect(c.threshold, 30);
      expect(() => c.streak(), returnsNormally);
      expect(c.minutesByDate().keys, isNot(contains('x')));
      expect(c.minutesByDate().containsKey('2026-11-19'), isFalse);
      expect(c.minutesByDate()['2026-11-18'], 40);
      c.dispose();
    }
  });

  test('init does not wait for notification permission', () async {
    final c = StudyController(
      store: store,
      chimes: _NeverReadyChimes(),
      clock: () => clock,
    );
    await c.init();
    expect(await c.addBlock(blk(c, 'a', BlockType.study, o(9, 0), o(10, 0))), isNull);
    c.dispose();
  });

  test('chime init failure does not block init', () async {
    final c = StudyController(
      store: store,
      chimes: _ThrowingChimes(),
      clock: () => clock,
    );
    await c.init();
    expect(c.blocks, isEmpty);
    c.dispose();
  });
}

class _NeverReadyChimes implements ChimeScheduler {
  @override
  Future<void> init() => Completer<void>().future;
  @override
  Future<void> replaceAll(List<Chime> chimes) async {}
}

class _ThrowingChimes implements ChimeScheduler {
  @override
  Future<void> init() async => throw StateError('no notifications');
  @override
  Future<void> replaceAll(List<Chime> chimes) async {}
}

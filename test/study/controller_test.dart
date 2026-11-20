import 'package:app/features/study/core/block.dart';
import 'package:app/features/study/core/chime_plan.dart';
import 'package:app/features/study/core/logical_day.dart';
import 'package:app/features/study/data/chime_scheduler.dart';
import 'package:app/features/study/data/study_controller.dart';
import 'package:app/features/study/data/study_store.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingChimes implements ChimeScheduler {
  List<Chime> last = const [];
  @override
  Future<void> init() async {}
  @override
  Future<void> replaceAll(List<Chime> chimes) async => last = chimes;
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
}

import 'package:app/app/app.dart';
import 'package:app/features/study/core/block.dart';
import 'package:app/features/study/core/logical_day.dart';
import 'package:app/features/study/data/chime_scheduler.dart';
import 'package:app/features/study/data/study_controller.dart';
import 'package:app/features/study/data/study_store.dart';
import 'package:app/features/study/ui/block_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shell switches between features', (tester) async {
    final study = StudyController(
      store: MemoryStudyStore(),
      chimes: NoopChimeScheduler(),
      clock: () => DateTime(2026, 11, 20, 12),
    );
    await tester.runAsync(study.init);
    await tester.pumpWidget(App(study: study));

    expect(find.text('スケジュールがありません'), findsOneWidget);

    await tester.tap(find.text('スケジュール').first);
    await tester.pumpAndSettle();
    expect(find.text('ブロックを追加'), findsOneWidget);

    await tester.tap(find.text('統計'));
    await tester.pumpAndSettle();
    expect(find.text('直近7日'), findsOneWidget);

    await tester.tap(find.text('ボード'));
    await tester.pumpAndSettle();
    // Test host is not iOS, so the canvas shows its placeholder.
    expect(find.text('この機能は iPad でのみ利用できます'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    study.dispose();
  });

  testWidgets('now page fits a narrow, short Split View window', (tester) async {
    tester.view.physicalSize = const Size(590, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final study = StudyController(
      store: MemoryStudyStore(),
      chimes: NoopChimeScheduler(),
      clock: () => DateTime(2026, 11, 20, 12, 10),
    );
    await tester.runAsync(study.init);
    await tester.runAsync(
      () => study.setBlocks([
        Block(
          id: 'a',
          name: '数学の過去問演習',
          type: BlockType.study,
          start: LogicalDay.toOffset(12, 0),
          end: LogicalDay.toOffset(13, 30),
        ),
        Block(
          id: 'b',
          name: '休憩',
          type: BlockType.rest,
          start: LogicalDay.toOffset(13, 30),
          end: LogicalDay.toOffset(13, 45),
        ),
      ]),
    );
    await tester.pumpWidget(App(study: study));
    expect(tester.takeException(), isNull);
    expect(find.text('勉強　数学の過去問演習'), findsOneWidget);
    expect(find.text('次：休憩・このあとすぐ'), findsOneWidget);

    await tester.tap(find.text('統計'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    study.dispose();
  });

  testWidgets('deleting a block can be undone', (tester) async {
    final study = StudyController(
      store: MemoryStudyStore(),
      chimes: NoopChimeScheduler(),
      clock: () => DateTime(2026, 11, 20, 8),
    );
    await tester.runAsync(study.init);
    await tester.runAsync(
      () => study.setBlocks([
        Block(
          id: 'a',
          name: '英語',
          type: BlockType.study,
          start: LogicalDay.toOffset(9, 0),
          end: LogicalDay.toOffset(10, 0),
        ),
      ]),
    );
    await tester.pumpWidget(App(study: study));
    await tester.tap(find.text('スケジュール').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    expect(study.blocks, isEmpty);
    expect(find.text('「英語」を削除しました'), findsOneWidget);

    await tester.tap(find.text('元に戻す'));
    await tester.pump();
    expect(study.blocks.map((b) => b.name), ['英語']);

    await tester.pumpWidget(const SizedBox());
    study.dispose();
  });

  testWidgets('an edit dialog left open over 4:00 does not undo the preset', (
    tester,
  ) async {
    var clock = DateTime(2026, 11, 20, 20); // Friday
    final study = StudyController(
      store: MemoryStudyStore(),
      chimes: NoopChimeScheduler(),
      clock: () => clock,
    );
    Block blk(String id, String name, int h) => Block(
      id: id,
      name: name,
      type: BlockType.study,
      start: LogicalDay.toOffset(h, 0),
      end: LogicalDay.toOffset(h + 1, 0),
    );
    await tester.runAsync(study.init);
    await tester.runAsync(() => study.setBlocks([blk('s', 'sat', 13)]));
    await tester.runAsync(() => study.saveAsPreset('weekend'));
    await tester.runAsync(
      () => study.setPresetWeekdays(study.presets.single.id, {6}),
    );
    await tester.runAsync(() => study.setBlocks([blk('f', 'fri', 9)]));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showBlockDialog(context, study, editing: study.blocks.single),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    clock = DateTime(2026, 11, 21, 4, 1); // Saturday
    await tester.runAsync(study.refresh);
    await tester.pump();
    expect(study.blocks.map((b) => b.name), ['sat']);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(study.blocks.map((b) => b.name), ['sat']);

    await tester.pumpWidget(const SizedBox());
    study.dispose();
  });
}

import 'package:app/app/app.dart';
import 'package:app/features/study/data/chime_scheduler.dart';
import 'package:app/features/study/data/study_controller.dart';
import 'package:app/features/study/data/study_store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

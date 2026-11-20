import 'package:app/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shell switches between features', (tester) async {
    await tester.pumpWidget(const App());

    expect(find.text('ホーム'), findsWidgets);

    await tester.tap(find.text('ボード'));
    await tester.pumpAndSettle();

    // Test host is not iOS, so the canvas shows its placeholder.
    expect(find.text('この機能は iPad でのみ利用できます'), findsOneWidget);
    expect(find.byTooltip('全消去'), findsOneWidget);
  });
}

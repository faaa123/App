import 'package:app/features/study/core/block.dart';
import 'package:app/features/study/core/chime_plan.dart';
import 'package:app/features/study/data/chime_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

Chime chime(int hour, String name) => Chime(
  DateTime(2026, 11, 20, hour),
  Block(id: name, name: name, type: BlockType.rest, start: 0, end: 10),
);

void main() {
  final a = chime(10, 'a'), b = chime(11, 'b'), c = chime(12, 'c');

  test('ids are stable and content-based', () {
    expect(chimeId(a), chimeId(chime(10, 'a')));
    expect(chimeId(a), isNot(chimeId(b)));
    expect(chimeId(a), greaterThanOrEqualTo(0));
  });

  test('resume after a chime fired only adds the new tail', () {
    // a already fired (gone from iOS), b is still pending, c is new.
    final d = diffChimes({chimeId(b)}, [b, c]);
    expect(d.cancel, isEmpty);
    expect(d.add.map((e) => e.$2), [c]);
  });

  test('unchanged plan touches nothing', () {
    final d = diffChimes({chimeId(a), chimeId(b)}, [a, b]);
    expect(d.cancel, isEmpty);
    expect(d.add, isEmpty);
  });

  test('stale and legacy ids are cancelled; dropped ones re-added', () {
    final d = diffChimes({0, 1, chimeId(a)}, [a, b]);
    expect(d.cancel, unorderedEquals([0, 1]));
    expect(d.add.map((e) => e.$2), [b]);
  });
}

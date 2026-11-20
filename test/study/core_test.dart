import 'package:app/features/study/core/block.dart';
import 'package:app/features/study/core/chime_plan.dart';
import 'package:app/features/study/core/logical_day.dart';
import 'package:app/features/study/core/now_status.dart';
import 'package:app/features/study/core/schedule_rules.dart';
import 'package:app/features/study/core/stats.dart';
import 'package:flutter_test/flutter_test.dart';

int o(int h, int m) => LogicalDay.toOffset(h, m);

Block b(String id, BlockType t, int s, int e) =>
    Block(id: id, name: id, type: t, start: s, end: e);

Block study(String id, int s, int e) => b(id, BlockType.study, s, e);
Block rest(String id, int s, int e) => b(id, BlockType.rest, s, e);

void main() {
  group('LogicalDay', () {
    test('4:00 is offset 0, 3:59 is the last minute', () {
      expect(o(4, 0), 0);
      expect(o(3, 59), 1439);
      expect(o(23, 0), 1140);
      expect(o(1, 0), 1260);
    });
    test('end at 4:00 is the end of the day', () {
      expect(LogicalDay.toEndOffset(4, 0), 1440);
    });
    test('0:00–3:59 belongs to the previous logical day', () {
      expect(LogicalDay.dateOf(DateTime(2026, 11, 21, 3, 59)), DateTime(2026, 11, 20));
      expect(LogicalDay.dateOf(DateTime(2026, 11, 21, 4)), DateTime(2026, 11, 21));
    });
    test('clock label round-trips', () {
      expect(LogicalDay.clock(o(9, 5)), '9:05');
      expect(LogicalDay.clock(1440), '4:00');
    });
  });

  group('Block', () {
    test('rejects crossing 4:00 and zero length', () {
      expect(() => study('x', 100, 100), throwsArgumentError);
      expect(() => study('x', 1430, 1450), throwsArgumentError);
    });
  });

  group('resolveNow', () {
    final blocks = [
      study('s1', o(9, 0), o(11, 0)),
      rest('r1', o(11, 0), o(11, 30)),
      study('late', o(23, 0), o(1, 0)),
    ];
    test('inside a block', () {
      final s = resolveNow(blocks, DateTime(2026, 1, 1, 10, 0, 30)) as InBlock;
      expect(s.block.id, 's1');
      expect(s.remainingSeconds, 59 * 60 + 30);
      expect(s.next!.id, 'r1');
    });
    test('exactly at a boundary the next block starts (half-open)', () {
      final s = resolveNow(blocks, DateTime(2026, 1, 1, 11, 0)) as InBlock;
      expect(s.block.id, 'r1');
    });
    test('free time shows the next block', () {
      final s = resolveNow(blocks, DateTime(2026, 1, 1, 12, 0)) as Free;
      expect(s.next.id, 'late');
      expect(s.secondsUntilNext, 11 * 3600);
    });
    test('block crossing midnight', () {
      final s = resolveNow(blocks, DateTime(2026, 1, 2, 0, 30)) as InBlock;
      expect(s.block.id, 'late');
      expect(s.remainingSeconds, 30 * 60);
    });
    test('day ended → until tomorrow first block', () {
      final s = resolveNow(blocks, DateTime(2026, 1, 2, 2, 0)) as DayEnded;
      expect(s.secondsUntilTomorrowFirst, 7 * 3600);
    });
    test('day ended → tomorrow may have a different (preset) schedule', () {
      final s = resolveNow(
        blocks,
        DateTime(2026, 1, 2, 2, 0),
        tomorrow: [study('t', o(6, 0), o(7, 0))],
      ) as DayEnded;
      expect(s.secondsUntilTomorrowFirst, 4 * 3600);
      final e = resolveNow(
        const [],
        DateTime(2026, 1, 1, 12),
        tomorrow: [study('t', o(6, 0), o(7, 0))],
      ) as DayEnded;
      expect(e.secondsUntilTomorrowFirst, 18 * 3600);
      final none = resolveNow(
        blocks,
        DateTime(2026, 1, 2, 2, 0),
        tomorrow: const [],
      ) as DayEnded;
      expect(none.secondsUntilTomorrowFirst, isNull);
    });
    test('no schedule', () {
      final s = resolveNow(const [], DateTime(2026, 1, 1, 12)) as DayEnded;
      expect(s.secondsUntilTomorrowFirst, isNull);
    });
  });

  group('validation & edits', () {
    final blocks = [
      study('a', o(9, 0), o(10, 0)),
      rest('b', o(10, 0), o(10, 15)),
      study('c', o(10, 30), o(11, 30)),
    ];
    test('overlap is rejected, gaps allowed', () {
      expect(validateSchedule(blocks), isNull);
      expect(validateSchedule([...blocks, study('d', o(9, 30), o(9, 45))]), isNotNull);
    });
    test('single change only moves the target', () {
      final r = applySingleChange(blocks, 'b', o(10, 0), o(10, 20));
      expect(r.isOk, isTrue);
      expect(r.blocks!.firstWhere((x) => x.id == 'c').start, o(10, 30));
    });
    test('single change that overlaps fails', () {
      expect(applySingleChange(blocks, 'b', o(10, 0), o(10, 45)).isOk, isFalse);
    });
    test('cascade shifts later blocks by the end delta', () {
      final r = applyCascadeShift(blocks, 'a', o(9, 0), o(10, 30));
      expect(r.isOk, isTrue);
      final m = {for (final x in r.blocks!) x.id: x};
      expect(m['b']!.start, o(10, 30));
      expect(m['c']!.start, o(11, 0));
    });
    test('cascade past 4:00 fails instead of clamping', () {
      final late = [study('x', o(2, 0), o(3, 0)), rest('y', o(3, 0), o(3, 50))];
      expect(applyCascadeShift(late, 'x', o(2, 0), o(3, 30)).isOk, isFalse);
    });
  });

  group('reorder', () {
    // Total length (durations + fixed gaps) never changes, so the end of the
    // day is preserved; reorderSchedule's null path is only a safety net.
    test('keeps gaps in their slots and durations per block', () {
      final blocks = [
        study('a', 0, 60),
        rest('b', 70, 80), // gap 10 after slot 0
        study('c', 80, 110),
      ];
      final r = reorderSchedule(blocks, ['c', 'a', 'b'])!;
      final m = {for (final x in r) x.id: x};
      expect((m['c']!.start, m['c']!.end), (0, 30));
      expect((m['a']!.start, m['a']!.end), (40, 100));
      expect((m['b']!.start, m['b']!.end), (100, 110));
    });
    test('returns null instead of passing 4:00', () {
      // Only reachable with overlapping input (a negative gap).
      final blocks = [
        study('a', 0, 10),
        study('b', 100, 1440),
        rest('c', 200, 300),
      ];
      expect(reorderSchedule(blocks, ['b', 'c', 'a']), isNull);
    });
  });

  group('pomodoro', () {
    test('alternates and truncates the last block', () {
      var n = 0;
      final r = pomodoroFill(
        start: 0,
        end: 70,
        studyMinutes: 25,
        restMinutes: 5,
        newId: () => '${n++}',
      );
      expect([for (final x in r) (x.name, x.start, x.end)], [
        ('勉強1', 0, 25),
        ('休憩1', 25, 30),
        ('勉強2', 30, 55),
        ('休憩2', 55, 60),
        ('勉強3', 60, 70),
      ]);
    });
    test('rest 0 means study only', () {
      final r = pomodoroFill(
        start: 0,
        end: 50,
        studyMinutes: 25,
        restMinutes: 0,
        newId: () => 'x',
      );
      expect(r.length, 2);
      expect(r.every((x) => x.isStudy), isTrue);
    });
  });

  group('stats', () {
    final blocks = [study('a', 0, 60), rest('b', 60, 70), study('c', 70, 100)];
    test('total and elapsed', () {
      expect(totalStudyMinutes(blocks), 90);
      expect(elapsedStudyMinutes(blocks, 80), 70);
      expect(elapsedStudyMinutes(blocks, 0), 0);
    });
    test('streak: today unmet does not break, missing day breaks', () {
      final today = DateTime(2026, 1, 10);
      String k(int d) => LogicalDay.dateKey(LogicalDay.addDays(today, -d));
      expect(
        calculateStreak(
          today: today,
          minutesByDate: {k(0): 0, k(1): 30, k(2): 40, k(4): 60},
          threshold: 30,
        ),
        2,
      );
      expect(
        calculateStreak(today: today, minutesByDate: {k(0): 30, k(1): 30}, threshold: 30),
        2,
      );
    });
  });

  group('chimes', () {
    test('only on study⇄rest switches, not around free time', () {
      final blocks = [
        study('a', o(9, 0), o(10, 0)),
        rest('b', o(10, 0), o(10, 10)),
        study('c', o(10, 10), o(11, 0)),
        study('d', o(11, 0), o(12, 0)), // same type: silent
        rest('e', o(13, 0), o(13, 10)), // after a gap: silent
      ];
      final chimes = planChimes(
        now: DateTime(2026, 1, 1, 8, 0),
        days: 1,
        scheduleFor: (_) => blocks,
      );
      expect([for (final c in chimes) c.next.id], ['b', 'c']);
      expect(chimes.first.at, DateTime(2026, 1, 1, 10, 0));
    });
    test('skips the past and spans days', () {
      final blocks = [study('a', o(9, 0), o(10, 0)), rest('b', o(10, 0), o(10, 10))];
      final chimes = planChimes(
        now: DateTime(2026, 1, 1, 11, 0),
        days: 3,
        scheduleFor: (_) => blocks,
      );
      expect([for (final c in chimes) c.at], [
        DateTime(2026, 1, 2, 10, 0),
        DateTime(2026, 1, 3, 10, 0),
      ]);
    });
    test('at 4:00 between days only when the type changes', () {
      List<Chime> plan(BlockType nextType) => planChimes(
        now: DateTime(2026, 1, 1, 8, 0),
        days: 2,
        scheduleFor: (d) => d.day == 1
            ? [rest('late', o(3, 0), LogicalDay.minutesPerDay)]
            : [b('early', nextType, 0, 60)],
      );
      final switched = plan(BlockType.study);
      expect([for (final c in switched) c.at], [DateTime(2026, 1, 2, 4, 0)]);
      expect(switched.single.next.id, 'early');
      expect(plan(BlockType.rest), isEmpty);
    });
  });
}

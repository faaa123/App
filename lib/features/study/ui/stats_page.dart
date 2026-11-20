import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../core/logical_day.dart';
import 'readable_list.dart';
import 'study_scope.dart';
import 'time_picking.dart';

/// Weekly / monthly planned study time and the streak.
class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = StudyScope.of(context);
    final byDate = c.minutesByDate();
    final today = c.today;
    final text = Theme.of(context).textTheme;

    List<(DateTime, int)> lastDays(int n) => [
      for (var i = n - 1; i >= 0; i--)
        (
          LogicalDay.addDays(today, -i),
          byDate[LogicalDay.dateKey(LogicalDay.addDays(today, -i))] ?? 0,
        ),
    ];

    final week = lastDays(7), month = lastDays(30);
    // Same frame as スケジュール: fixed AppBar title, 24pt gutter.
    return Scaffold(
      appBar: AppBar(title: const Text('統計')),
      body: ReadableListView(
        maxWidth: 900,
        children: [
          Text('スケジュール上の勉強時間（予定ベース）です。今日の値は暫定です。', style: text.bodySmall),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              // Wraps the stepper below the streak in narrow windows.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department, size: 48),
                      const SizedBox(width: 16),
                      Text('${c.streak()}', style: text.displayMedium),
                      const SizedBox(width: 8),
                      Text('日連続', style: text.titleLarge),
                    ],
                  ),
                  MinuteStepper(
                    label: '達成の基準（1日）',
                    value: c.threshold,
                    min: 10,
                    max: 720,
                    step: 10,
                    onChanged: c.setThreshold,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _PeriodCard(title: '直近7日', days: week, threshold: c.threshold),
          const SizedBox(height: 16),
          _PeriodCard(title: '直近30日', days: month, threshold: c.threshold),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({
    required this.title,
    required this.days,
    required this.threshold,
  });

  final String title;
  final List<(DateTime, int)> days;
  final int threshold;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = days.fold(0, (s, d) => s + d.$2);
    final peak = max(threshold, days.fold(0, (m, d) => max(m, d.$2)));
    final showLabels = days.length <= 7;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 4,
              children: [
                Text(title, style: text.titleLarge),
                Text(
                  '合計 ${formatMinutes(total)}　平均 ${formatMinutes(total ~/ days.length)}',
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final (_, minutes) in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        // The bar takes what the one-line label leaves, so
                        // narrow columns or large text never overflow.
                        child: LayoutBuilder(
                          builder: (context, box) => Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (showLabels && minutes > 0)
                                SizedBox(
                                  height: 16,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      formatMinutes(minutes),
                                      maxLines: 1,
                                      style: text.labelSmall,
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 4),
                              Container(
                                height: max(
                                  2,
                                  min(120.0, box.maxHeight - 20) *
                                      minutes /
                                      peak,
                                ),
                                // Missed days: same hue, outlined, so they
                                // differ by shape as well as by color.
                                decoration: BoxDecoration(
                                  color: minutes >= threshold
                                      ? BlockStyle.study.mark
                                      : BlockStyle.study.mark.withValues(
                                          alpha: 0.3,
                                        ),
                                  border: minutes >= threshold
                                      ? null
                                      : Border.all(
                                          color: BlockStyle.study.mark,
                                        ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (showLabels) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final (date, _) in days)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${date.month}/${date.day}',
                          maxLines: 1,
                          style: text.labelSmall,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

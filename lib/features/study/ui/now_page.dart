import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/logical_day.dart';
import '../core/now_status.dart';
import '../core/stats.dart';
import 'day_band.dart';
import 'study_scope.dart';

/// The app's main screen: what to do now and how long is left.
class NowPage extends StatefulWidget {
  const NowPage({super.key});

  @override
  State<NowPage> createState() => _NowPageState();
}

class _NowPageState extends State<NowPage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Only this page ticks; other features stay idle (no frames).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyScope.of(context);
    final now = c.now();
    final blocks = c.blocks;
    final status = resolveNow(blocks, now);
    final offset = LogicalDay.offsetOf(now);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(_dateLabel(c.today), style: text.titleMedium),
              const Spacer(),
              if (blocks.isNotEmpty)
                Text(
                  '本日の勉強 ${formatMinutes(elapsedStudyMinutes(blocks, offset))}'
                  ' / ${formatMinutes(totalStudyMinutes(blocks))}',
                  style: text.titleMedium,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(child: _StatusPanel(status: status)),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 24),
            DayBand(blocks: blocks, nowOffset: offset),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    const w = ['日', '月', '火', '水', '木', '金', '土'];
    return '${d.month}月${d.day}日（${w[LogicalDay.weekdayOf(d)]}）';
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.status});

  final NowStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      InBlock s => _InBlockPanel(status: s),
      Free s => _Panel(
        color: scheme.surfaceContainerHigh,
        onColor: scheme.onSurface,
        icon: Icons.hourglass_empty,
        title: '予定なし',
        big: formatCountdown(s.secondsUntilNext),
        caption: '「${s.next.name}」が始まるまで',
      ),
      DayEnded(:final secondsUntilTomorrowFirst) =>
        secondsUntilTomorrowFirst == null
            ? _Panel(
                color: scheme.surfaceContainerHigh,
                onColor: scheme.onSurface,
                icon: Icons.edit_calendar_outlined,
                title: 'スケジュールがありません',
                caption: '「スケジュール」から勉強・休憩のブロックを作りましょう',
              )
            : _Panel(
                color: scheme.surfaceContainerHigh,
                onColor: scheme.onSurface,
                icon: Icons.nights_stay_outlined,
                title: '本日の予定は終了',
                big: formatCountdown(secondsUntilTomorrowFirst),
                caption: '明日の最初のブロックまで',
              ),
    };
  }
}

class _InBlockPanel extends StatelessWidget {
  const _InBlockPanel({required this.status});

  final InBlock status;

  @override
  Widget build(BuildContext context) {
    final b = status.block;
    final style = BlockStyle.of(b.type);
    final next = status.next;
    return _Panel(
      color: style.color,
      onColor: style.onColor,
      icon: style.icon,
      title: '${style.label}　${b.name}',
      big: formatCountdown(status.remainingSeconds),
      caption: '〜${LogicalDay.clock(b.end)}',
      progress: status.progress,
      footer: next == null
          ? '本日最後のブロックです'
          : '次：${next.name}'
                '（${BlockStyle.of(next.type).label}・'
                '${status.secondsUntilNext! <= status.remainingSeconds ? 'このあとすぐ' : 'あと${formatUntil(status.secondsUntilNext!)}'}）',
    );
  }
}

/// Big status card. The countdown is the hero.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.color,
    required this.onColor,
    required this.icon,
    required this.title,
    this.big,
    this.caption,
    this.progress,
    this.footer,
  });

  final Color color;
  final Color onColor;
  final IconData icon;
  final String title;
  final String? big;
  final String? caption;
  final double? progress;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: onColor),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: onColor, size: 40),
                  const SizedBox(width: 16),
                  Flexible(
                    child: Text(
                      title,
                      style: text.headlineMedium?.copyWith(color: onColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (big != null)
                FittedBox(
                  child: Text(
                    big!,
                    style: TextStyle(
                      color: onColor,
                      fontSize: 160,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.2,
                    ),
                  ),
                ),
              if (caption != null)
                Text(
                  caption!,
                  style: text.titleLarge?.copyWith(color: onColor),
                  textAlign: TextAlign.center,
                ),
              if (progress != null) ...[
                const SizedBox(height: 24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 12,
                    color: onColor,
                    backgroundColor: onColor.withValues(alpha: 0.2),
                  ),
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 24),
                Text(footer!, style: text.titleMedium?.copyWith(color: onColor)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}


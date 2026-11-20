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
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Only this page ticks; other features stay idle (no frames).
    _schedule();
    _lifecycle = AppLifecycleListener(
      onHide: () => _ticker?.cancel(),
      onShow: () {
        setState(() {});
        _schedule();
      },
    );
  }

  /// Ticks just after each wall-clock second, so the countdown changes in
  /// step with the clock (and the chimes) instead of up to 1s late.
  void _schedule() {
    _ticker?.cancel();
    final n = DateTime.now();
    _ticker = Timer(Duration(milliseconds: 1000 - n.millisecond + 5), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = StudyScope.of(context);
    final now = c.now();
    final blocks = c.blocks;
    final status = resolveNow(
      blocks,
      now,
      tomorrow: c.scheduleFor(LogicalDay.addDays(c.today, 1)),
    );
    final offset = LogicalDay.offsetOf(now);
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wraps instead of overflowing in Split View.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text(_dateLabel(c.today), style: text.titleMedium),
              if (blocks.isNotEmpty)
                Text(
                  '勉強 ${formatMinutes(elapsedStudyMinutes(blocks, offset))}'
                  ' / ${formatMinutes(totalStudyMinutes(blocks))}',
                  style: text.titleMedium,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _StatusPanel(status: status, hasToday: blocks.isNotEmpty),
          ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 24),
            RepaintBoundary(
              child: DayBand(blocks: blocks, nowOffset: offset),
            ),
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
  const _StatusPanel({required this.status, required this.hasToday});

  final NowStatus status;
  final bool hasToday;

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
        seconds: s.secondsUntilNext,
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
                title: hasToday ? '本日の予定は終了' : '本日は予定なし',
                seconds: secondsUntilTomorrowFirst,
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
    // Default names equal the type label; don't show them twice.
    final title = b.name == style.label
        ? style.label
        : '${style.label}　${b.name}';
    final String? nextName;
    if (next == null) {
      nextName = null;
    } else {
      final label = BlockStyle.of(next.type).label;
      nextName = next.name == label ? label : '${next.name}（$label）';
    }
    return _Panel(
      color: style.color,
      onColor: style.onColor,
      icon: style.icon,
      title: title,
      seconds: status.remainingSeconds,
      caption: '〜${LogicalDay.clock(b.end)}',
      progress: status.progress,
      footer: next == null
          ? '本日最後のブロックです'
          : '次：$nextName・'
                '${status.secondsUntilNext! <= status.remainingSeconds ? 'このあとすぐ' : 'あと${formatUntil(status.secondsUntilNext!)}'}',
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
    this.seconds,
    this.caption,
    this.progress,
    this.footer,
  });

  final Color color;
  final Color onColor;
  final IconData icon;
  final String title;

  /// Countdown shown as the hero number.
  final int? seconds;
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
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: EdgeInsets.all(constraints.maxHeight < 500 ? 20 : 40),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // The countdown gives up height first in short windows or
                // with large text.
                if (seconds != null)
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      // VoiceOver reads "あと25分" instead of a bare "25:00".
                      child: Text(
                        formatCountdown(seconds!),
                        semanticsLabel: 'あと${formatUntil(seconds!)}',
                        style: TextStyle(
                          color: onColor,
                          fontSize: 160,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                if (caption != null)
                  Text(
                    caption!,
                    style: text.titleLarge?.copyWith(color: onColor),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
                  Text(
                    footer!,
                    style: text.titleMedium?.copyWith(color: onColor),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

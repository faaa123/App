import 'package:material_ui/material_ui.dart';

import '../core/block.dart';
import '../data/study_controller.dart';

/// Provides the [StudyController] to the study screens.
class StudyScope extends InheritedNotifier<StudyController> {
  const StudyScope({
    super.key,
    required StudyController controller,
    required super.child,
  }) : super(notifier: controller);

  static StudyController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudyScope>()!.notifier!;
}

/// Study = deep, calm; rest = bright. Shape (icon) differs too, not only color.
class BlockStyle {
  const BlockStyle._(this.color, this.onColor, this.icon, this.label);

  final Color color;
  final Color onColor;
  final IconData icon;
  final String label;

  static const study = BlockStyle._(
    Color(0xFF2E3A8C),
    Color(0xFFE8EAFF),
    Icons.menu_book,
    '勉強',
  );
  static const rest = BlockStyle._(
    Color(0xFFFFC857),
    Color(0xFF3A2A00),
    Icons.local_cafe_outlined,
    '休憩',
  );

  static BlockStyle of(BlockType t) => t == BlockType.study ? study : rest;
}

/// 5400 → "1:30:00", 300 → "5:00".
String formatCountdown(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// 95 → "1時間35分", 30 → "30分".
String formatMinutes(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m分';
  return m == 0 ? '$h時間' : '$h時間$m分';
}

/// Rounded-up minutes for "あと○分" style labels.
String formatUntil(int seconds) => formatMinutes((seconds + 59) ~/ 60);

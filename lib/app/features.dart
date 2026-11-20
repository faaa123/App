import 'package:material_ui/material_ui.dart';

import '../features/study/ui/now_page.dart';
import '../features/study/ui/schedule_page.dart';
import '../features/study/ui/stats_page.dart';
import '../features/whiteboard/whiteboard_page.dart';
import 'app_feature.dart';

/// Registry of top-level features. Add new features here.
const appFeatures = <AppFeature>[
  AppFeature(id: 'now', label: '今', icon: Icons.timer_outlined, builder: _now),
  AppFeature(
    id: 'schedule',
    label: 'スケジュール',
    icon: Icons.view_agenda_outlined,
    builder: _schedule,
  ),
  AppFeature(
    id: 'stats',
    label: '統計',
    icon: Icons.insights_outlined,
    builder: _stats,
  ),
  AppFeature(
    id: 'whiteboard',
    label: 'ボード',
    icon: Icons.draw_outlined,
    builder: _whiteboard,
    immersive: true,
  ),
];

Widget _now(BuildContext context) => const NowPage();
Widget _schedule(BuildContext context) => const SchedulePage();
Widget _stats(BuildContext context) => const StatsPage();
Widget _whiteboard(BuildContext context) => const WhiteboardPage();

import 'package:material_ui/material_ui.dart';

import '../features/home/home_page.dart';
import '../features/whiteboard/whiteboard_page.dart';
import 'app_feature.dart';

/// Registry of top-level features. Add new features here.
const appFeatures = <AppFeature>[
  AppFeature(
    id: 'home',
    label: 'ホーム',
    icon: Icons.home_outlined,
    builder: _home,
  ),
  AppFeature(
    id: 'whiteboard',
    label: 'ボード',
    icon: Icons.draw_outlined,
    builder: _whiteboard,
  ),
];

Widget _home(BuildContext context) => const HomePage();
Widget _whiteboard(BuildContext context) => const WhiteboardPage();

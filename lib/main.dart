import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'features/study/data/chime_scheduler.dart';
import 'features/study/data/study_controller.dart';
import 'features/study/data/study_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final study = StudyController(
    store: FileStudyStore(),
    chimes: defaultTargetPlatform == TargetPlatform.iOS
        ? NotificationChimeScheduler()
        : NoopChimeScheduler(),
  );
  await study.init();
  runApp(App(study: study));
}

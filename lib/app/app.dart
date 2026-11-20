import 'package:material_ui/material_ui.dart';

import '../features/study/data/study_controller.dart';
import '../features/study/ui/study_scope.dart';
import 'features.dart';
import 'shell.dart';

class App extends StatefulWidget {
  const App({super.key, required this.study});

  final StudyController study;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final _lifecycle = AppLifecycleListener(
    // Day rollover, weekday presets and chimes may be stale after a while.
    onResume: widget.study.refresh,
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      controller: widget.study,
      child: MaterialApp(
        title: 'App',
        // Japanese glyph variants and Japanese text in pickers/dialogs.
        locale: const Locale('ja', 'JP'),
        supportedLocales: const [Locale('ja', 'JP')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const Shell(features: appFeatures),
      ),
    );
  }
}

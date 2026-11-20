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
        theme: _glassTheme(),
        home: const Shell(features: appFeatures),
      ),
    );
  }
}

/// Dark theme whose surfaces are translucent "glass" over the shell's
/// gradient backdrop (see glass.dart).
ThemeData _glassTheme() {
  final base = ThemeData(
    colorSchemeSeed: const Color(0xFF6C7BFF),
    brightness: Brightness.dark,
  );
  final glassFill = Colors.white.withValues(alpha: 0.07);
  final rim = BorderSide(color: Colors.white.withValues(alpha: 0.12));
  return base.copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: glassFill,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: rim,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1B2040).withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: rim,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      width: 520,
      backgroundColor: const Color(0xFF262C52),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: rim,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: const StadiumBorder(),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
        backgroundColor: glassFill,
      ),
    ),
  );
}

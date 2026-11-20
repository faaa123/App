import 'package:material_ui/material_ui.dart';

/// One top-level feature shown in the app shell.
class AppFeature {
  const AppFeature({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.immersive = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// Uses the whole screen: the navigation is hidden until the feature calls
  /// [ShellScope.toggleNavigation] (e.g. from its own menu button).
  final bool immersive;
}

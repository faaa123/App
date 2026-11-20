import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_feature.dart';

/// Lets a feature show/hide the shell's navigation.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.toggleNavigation,
    required super.child,
  });

  final VoidCallback toggleNavigation;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => false;
}

/// Side navigation shell that switches between [features]. Immersive
/// features get the full screen; their navigation is toggled on demand.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.features});

  final List<AppFeature> features;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  bool _navOpen = false;

  void _select(int i) => setState(() {
    _index = i;
    _navOpen = false;
  });

  void _toggleNavigation() => setState(() => _navOpen = !_navOpen);

  @override
  Widget build(BuildContext context) {
    final feature = widget.features[_index];
    final showNav = !feature.immersive || _navOpen;
    return Scaffold(
      // Light status bar text over the dark theme on every page; pages with
      // a light background (the whiteboard) override it with their own region.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Row(
          children: [
            if (showNav)
              SafeArea(
                right: false,
                child: NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -0.9,
                  onDestinationSelected: _select,
                  destinations: [
                    for (final f in widget.features)
                      NavigationRailDestination(
                        icon: Icon(f.icon),
                        label: Text(f.label),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ShellScope(
                toggleNavigation: _toggleNavigation,
                child: SafeArea(
                  left: !showNav,
                  // Immersive features handle their own insets.
                  top: !feature.immersive,
                  bottom: !feature.immersive,
                  right: !feature.immersive,
                  child: KeyedSubtree(
                    key: ValueKey(feature.id),
                    child: feature.builder(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

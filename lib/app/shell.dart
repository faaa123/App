import 'package:material_ui/material_ui.dart';

import 'app_feature.dart';

/// Side navigation shell that switches between [features].
class Shell extends StatefulWidget {
  const Shell({super.key, required this.features});

  final List<AppFeature> features;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final feature = widget.features[_index];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final f in widget.features)
                  NavigationRailDestination(
                    icon: Icon(f.icon),
                    label: Text(f.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(feature.id),
                child: feature.builder(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

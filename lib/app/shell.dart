import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_feature.dart';
import 'glass.dart';

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

/// App shell: a floating glass tab bar at the top center (iPadOS style) over a
/// soft gradient backdrop. Pages get the bar's height as top inset, so their
/// own SafeArea / AppBar sit below it. Immersive features (the whiteboard)
/// get the whole screen and show the bar only on demand.
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
    final immersive = feature.immersive;
    final showBar = !immersive || _navOpen;
    final mq = MediaQuery.of(context);
    // Compact bar in short windows (Split View / Slide Over).
    final compact = mq.size.height < 600;
    final barHeight = compact ? 44.0 : 56.0;
    final barMargin = compact ? 6.0 : 12.0;
    final reserved = barHeight + barMargin * 2;

    Widget page = KeyedSubtree(
      key: ValueKey(feature.id),
      child: feature.builder(context),
    );
    if (!immersive) {
      // Pages lay out below the floating bar.
      page = MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(top: mq.padding.top + reserved),
          viewPadding: mq.viewPadding.copyWith(
            top: mq.viewPadding.top + reserved,
          ),
        ),
        child: SafeArea(child: page),
      );
    }

    return Scaffold(
      backgroundColor: GlassBackground.base,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GlassBackground(
          child: Stack(
            children: [
              Positioned.fill(
                child: ShellScope(
                  toggleNavigation: _toggleNavigation,
                  child: page,
                ),
              ),
              if (showBar)
                Positioned(
                  top: mq.padding.top + barMargin,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: _TabBar(
                      features: widget.features,
                      index: _index,
                      height: barHeight,
                      onSelect: _select,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.features,
    required this.index,
    required this.height,
    required this.onSelect,
  });

  final List<AppFeature> features;
  final int index;
  final double height;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelLarge;
    return Glass(
      blur: true,
      radius: height / 2,
      tint: const Color(0xFF1A1F38).withValues(alpha: 0.55),
      padding: const EdgeInsets.all(5),
      child: SizedBox(
        height: height - 10,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < features.length; i++)
              Semantics(
                selected: i == index,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(height / 2),
                      color: i == index
                          ? Colors.white.withValues(alpha: 0.18)
                          : Colors.transparent,
                      border: i == index
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            )
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          features[i].icon,
                          size: 20,
                          color: i == index ? Colors.white : Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          features[i].label,
                          style: text?.copyWith(
                            color: i == index ? Colors.white : Colors.white70,
                            fontWeight: i == index ? FontWeight.w600 : null,
                          ),
                        ),
                      ],
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

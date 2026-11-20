import 'package:material_ui/material_ui.dart';

/// Placeholder top page. Replace with the app's main content.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('ホーム', style: Theme.of(context).textTheme.headlineMedium),
    );
  }
}

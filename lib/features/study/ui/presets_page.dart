import 'package:material_ui/material_ui.dart';

import '../core/stats.dart';
import 'block_dialogs.dart';
import 'readable_list.dart';
import 'study_scope.dart';

const _weekdayLabels = ['日', '月', '火', '水', '木', '金', '土'];

/// Named schedules, optionally applied automatically on chosen weekdays.
class PresetsPage extends StatelessWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = StudyScope.of(context);
    final presets = c.presets;
    return Scaffold(
      appBar: AppBar(title: const Text('プリセット')),
      body: ReadableListView(
        children: [
          Text(
            '曜日を選ぶと、その曜日になったとき（4:00〜）自動でスケジュールを置き換えます。'
            '同じ曜日に複数ある場合は、後から曜日を設定した方が優先されます。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: const Text('現在のスケジュールを保存'),
              onPressed: c.blocks.isEmpty
                  ? null
                  : () async {
                      final name = await askName(context, title: 'プリセット名');
                      if (name != null) await c.saveAsPreset(name);
                    },
            ),
          ),
          const SizedBox(height: 16),
          if (presets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('プリセットはまだありません')),
            ),
          for (final p in presets)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Wraps the summary under the name in narrow windows.
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          p.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${p.blocks.length}ブロック・勉強${formatMinutes(totalStudyMinutes(p.blocks))}',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (var w = 0; w < 7; w++)
                          FilterChip(
                            label: Text(
                              _weekdayLabels[w],
                              semanticsLabel: '${_weekdayLabels[w]}曜日',
                            ),
                            selected: p.weekdays.contains(w),
                            onSelected: (on) => c.setPresetWeekdays(
                              p.id,
                              on ? {...p.weekdays, w} : ({...p.weekdays}..remove(w)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          child: const Text('削除'),
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              title: '「${p.name}」を削除しますか？',
                              message: '現在のスケジュールは変わりません。',
                              ok: '削除',
                            );
                            if (ok) await c.deletePreset(p.id);
                          },
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          child: const Text('読み込む'),
                          onPressed: () async {
                            final ok = await confirm(
                              context,
                              title: '「${p.name}」を読み込みますか？',
                              message: '現在のスケジュールを置き換えます。',
                              ok: '読み込む',
                            );
                            if (ok) await c.applyPreset(p.id);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../core/block.dart';
import '../core/logical_day.dart';
import '../core/stats.dart';
import 'block_dialogs.dart';
import 'presets_page.dart';
import 'study_scope.dart';

/// Edit the (single, permanent) schedule.
class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = StudyScope.of(context);
    final blocks = c.blocks;
    final text = Theme.of(context).textTheme;

    void showError(String? err) {
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('スケジュール'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('プリセット'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PresetsPage(),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
        children: [
          Text(
            '1日の合計勉強時間：${formatMinutes(totalStudyMinutes(blocks))}',
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            '編集はそのまま翌日以降も引き継がれます。長押しでドラッグして並び替え（時刻は自動で詰め直し）。',
            style: text.bodySmall,
          ),
          const SizedBox(height: 16),
          if (blocks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('ブロックがありません（終日フリー）')),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) async {
                final ids = [for (final b in blocks) b.id];
                ids.insert(to, ids.removeAt(from));
                showError(await c.reorder(ids));
              },
              children: [
                for (var i = 0; i < blocks.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(blocks[i].id),
                    index: i,
                    child: _BlockTile(
                      block: blocks[i],
                      onTap: () => showBlockDialog(context, c, editing: blocks[i]),
                      onDelete: () => c.deleteBlock(blocks[i].id),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('ブロックを追加'),
                onPressed: () => showBlockDialog(context, c),
              ),
              OutlinedButton(
                child: const Text('🍅 ポモドーロで敷き詰める'),
                onPressed: () => showPomodoroDialog(context, c),
              ),
            ],
          ),
          if (blocks.isNotEmpty) ...[
            const SizedBox(height: 48),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.outline,
                ),
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('すべてのブロックを削除'),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'すべて削除しますか？',
                    message: '${blocks.length}個のブロックをすべて削除します。',
                    ok: '削除',
                  );
                  if (ok) await c.deleteAll();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BlockTile extends StatelessWidget {
  const _BlockTile({
    required this.block,
    required this.onTap,
    required this.onDelete,
  });

  final Block block;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final style = BlockStyle.of(block.type);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: style.color,
          child: Icon(style.icon, color: style.onColor),
        ),
        title: Text(block.name),
        subtitle: Text(
          '${LogicalDay.clock(block.start)} – ${LogicalDay.clock(block.end)}'
          '（${formatMinutes(block.duration)}）',
        ),
        trailing: IconButton(
          tooltip: '削除',
          icon: const Icon(Icons.close),
          onPressed: onDelete,
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';

import '../core/block.dart';
import '../core/logical_day.dart';
import '../core/schedule_rules.dart';
import '../core/stats.dart';
import '../data/study_controller.dart';
import 'study_scope.dart';
import 'time_picking.dart';

/// Add a block ([editing] == null) or edit one. Saves through [controller].
Future<void> showBlockDialog(
  BuildContext context,
  StudyController controller, {
  Block? editing,
}) => showDialog<void>(
  context: context,
  builder: (_) => _BlockDialog(controller: controller, editing: editing),
);

class _BlockDialog extends StatefulWidget {
  const _BlockDialog({required this.controller, this.editing});

  final StudyController controller;
  final Block? editing;

  @override
  State<_BlockDialog> createState() => _BlockDialogState();
}

class _BlockDialogState extends State<_BlockDialog> {
  late final _name = TextEditingController(text: widget.editing?.name ?? '');
  late BlockType _type = widget.editing?.type ?? BlockType.study;
  late int _start;
  late int _end;
  bool _cascade = false;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    if (e != null) {
      _start = e.start;
      _end = e.end;
    } else {
      // Default: right after the last block, 30 minutes.
      final blocks = widget.controller.blocks;
      _start = blocks.isEmpty ? LogicalDay.toOffset(9, 0) : blocks.last.end;
      if (_start >= LogicalDay.minutesPerDay) _start = LogicalDay.minutesPerDay - 30;
      _end = (_start + 30).clamp(_start + 1, LogicalDay.minutesPerDay);
    }
    // The schedule can change underneath (4:00 rollover, weekday preset):
    // keep the preview in sync with it.
    widget.controller.addListener(_onScheduleChanged);
  }

  void _onScheduleChanged() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_onScheduleChanged);
    _name.dispose();
    super.dispose();
  }

  String get _effectiveName {
    final n = _name.text.trim();
    return n.isEmpty ? BlockStyle.of(_type).label : n;
  }

  /// The whole schedule after this edit, or an error.
  EditResult _preview() {
    final blocks = widget.controller.blocks;
    final e = widget.editing;
    if (_end <= _start) return const EditResult.fail('終了は開始より後にしてください（翌4:00まで）');
    if (e == null) {
      final added = Block(
        id: widget.controller.newId(),
        name: _effectiveName,
        type: _type,
        start: _start,
        end: _end,
      );
      final next = [...blocks, added];
      final err = validateSchedule(next);
      return err == null ? EditResult.ok(next) : EditResult.fail(err);
    }
    final renamed = [
      for (final b in blocks)
        b.id == e.id ? b.copyWith(name: _effectiveName, type: _type) : b,
    ];
    return _cascade
        ? applyCascadeShift(renamed, e.id, _start, _end)
        : applySingleChange(renamed, e.id, _start, _end);
  }

  @override
  Widget build(BuildContext context) {
    final result = _preview();
    final e = widget.editing;
    final shifted = <String>[];
    if (e != null && _cascade && result.isOk) {
      final before = {for (final b in widget.controller.blocks) b.id: b};
      for (final b in sortedByStart(result.blocks!)) {
        final old = before[b.id]!;
        if (b.id != e.id && old.start != b.start) {
          shifted.add(
            '${b.name}：${LogicalDay.clock(old.start)}–${LogicalDay.clock(old.end)}'
            ' → ${LogicalDay.clock(b.start)}–${LogicalDay.clock(b.end)}',
          );
        }
      }
    }

    return AlertDialog(
      title: Text(e == null ? 'ブロックを追加' : 'ブロックを編集'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<BlockType>(
                segments: [
                  for (final t in BlockType.values)
                    ButtonSegment(
                      value: t,
                      label: Text(BlockStyle.of(t).label),
                      icon: Icon(BlockStyle.of(t).icon),
                    ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '名前',
                  hintText: BlockStyle.of(_type).label,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TimeField(
                      label: '開始',
                      offset: _start,
                      isEnd: false,
                      onChanged: (v) => setState(() => _start = v),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('〜'),
                  ),
                  Expanded(
                    child: TimeField(
                      label: '終了',
                      offset: _end,
                      isEnd: true,
                      onChanged: (v) => setState(() => _end = v),
                    ),
                  ),
                ],
              ),
              if (e != null) ...[
                const SizedBox(height: 16),
                RadioGroup<bool>(
                  groupValue: _cascade,
                  onChanged: (v) => setState(() => _cascade = v ?? false),
                  child: const Column(
                    children: [
                      // Flush with the fields above.
                      RadioListTile(
                        value: false,
                        contentPadding: EdgeInsets.zero,
                        title: Text('このブロックのみ変更'),
                      ),
                      RadioListTile(
                        value: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('以降のブロックも同じ幅だけずらす'),
                      ),
                    ],
                  ),
                ),
              ],
              if (shifted.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('連動して動くブロック', style: Theme.of(context).textTheme.labelLarge),
                for (final s in shifted) Text(s),
              ],
              if (!result.isOk) ...[
                const SizedBox(height: 12),
                Text(
                  result.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: result.isOk
              ? () async {
                  // Recompute against the current schedule, not the one of
                  // the last build.
                  final r = _preview();
                  if (!r.isOk) {
                    setState(() {});
                    return;
                  }
                  await widget.controller.setBlocks(r.blocks!);
                  if (context.mounted) Navigator.pop(context);
                }
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// Fill a time range with study/rest repeats.
Future<void> showPomodoroDialog(BuildContext context, StudyController controller) =>
    showDialog<void>(
      context: context,
      builder: (_) => _PomodoroDialog(controller: controller),
    );

class _PomodoroDialog extends StatefulWidget {
  const _PomodoroDialog({required this.controller});

  final StudyController controller;

  @override
  State<_PomodoroDialog> createState() => _PomodoroDialogState();
}

class _PomodoroDialogState extends State<_PomodoroDialog> {
  late int _start;
  late int _end;
  int _study = 25;
  int _rest = 5;

  @override
  void initState() {
    super.initState();
    final blocks = widget.controller.blocks;
    _start = blocks.isEmpty ? LogicalDay.toOffset(9, 0) : blocks.last.end;
    if (_start >= LogicalDay.minutesPerDay) _start = LogicalDay.minutesPerDay - 60;
    _end = (_start + 120).clamp(_start + 1, LogicalDay.minutesPerDay);
  }

  @override
  Widget build(BuildContext context) {
    final generated = pomodoroFill(
      start: _start,
      end: _end,
      studyMinutes: _study,
      restMinutes: _rest,
      newId: widget.controller.newId,
    );
    final err = _end <= _start
        ? '終了は開始より後にしてください（翌4:00まで）'
        : validateSchedule([...widget.controller.blocks, ...generated]);
    return AlertDialog(
      title: const Text('🍅 ポモドーロで敷き詰める'),
      content: SizedBox(
        width: 440,
        // Scrolls with large text or in a short window.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TimeField(
                      label: '開始',
                      offset: _start,
                      isEnd: false,
                      onChanged: (v) => setState(() => _start = v),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('〜'),
                  ),
                  Expanded(
                    child: TimeField(
                      label: '終了',
                      offset: _end,
                      isEnd: true,
                      onChanged: (v) => setState(() => _end = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              MinuteStepper(
                label: '勉強',
                value: _study,
                min: 5,
                max: 180,
                onChanged: (v) => setState(() => _study = v),
              ),
              MinuteStepper(
                label: '休憩',
                value: _rest,
                max: 60,
                onChanged: (v) => setState(() => _rest = v),
              ),
              const SizedBox(height: 8),
              Text(
                '${generated.length}個のブロック'
                '（勉強${formatMinutes(totalStudyMinutes(generated))}）を追加します',
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: err == null && generated.isNotEmpty
              ? () async {
                  await widget.controller.addBlocks(generated);
                  if (context.mounted) Navigator.pop(context);
                }
              : null,
          child: const Text('追加'),
        ),
      ],
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String ok,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> askName(BuildContext context, {required String title}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(title: title),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title});

  final String title;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _c.text.trim();
    if (v.isNotEmpty) Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _c,
      autofocus: true,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
      decoration: const InputDecoration(labelText: '名前'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('キャンセル'),
      ),
      ValueListenableBuilder(
        valueListenable: _c,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty ? null : _submit,
          child: const Text('保存'),
        ),
      ),
    ],
  );
}

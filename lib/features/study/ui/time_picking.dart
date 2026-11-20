import 'package:material_ui/material_ui.dart';

import '../core/logical_day.dart';

/// Pick a clock time and return it as a logical-day offset. End times map 4:00
/// to the end of the day (1440).
Future<int?> pickOffset(
  BuildContext context,
  int initial, {
  required bool isEnd,
}) async {
  final (h, m) = LogicalDay.clockParts(initial);
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: h, minute: m),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (t == null) return null;
  return isEnd
      ? LogicalDay.toEndOffset(t.hour, t.minute)
      : LogicalDay.toOffset(t.hour, t.minute);
}

/// A tappable "H:MM" field.
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.offset,
    required this.isEnd,
    required this.onChanged,
  });

  final String label;
  final int offset;
  final bool isEnd;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      onPressed: () async {
        final v = await pickOffset(context, offset, isEnd: isEnd);
        if (v != null) onChanged(v);
      },
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(
            LogicalDay.clock(offset),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}

/// Small −/+ number input.
class MinuteStepper extends StatelessWidget {
  const MinuteStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 600,
    this.step = 5,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        IconButton(
          icon: const Icon(Icons.remove),
          onPressed: value - step >= min ? () => onChanged(value - step) : null,
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value分',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add),
          onPressed: value + step <= max ? () => onChanged(value + step) : null,
        ),
      ],
    );
  }
}

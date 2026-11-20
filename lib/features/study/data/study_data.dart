import '../core/block.dart';

/// Parses what can be parsed: entries that fail (bad types, impossible
/// offsets, overlaps with an earlier block) are dropped instead of throwing.
List<Block> _parseBlocks(Object? list) {
  final out = <Block>[];
  for (final b in list is List ? list : const []) {
    try {
      final block = Block.fromJson(b as Map<String, dynamic>);
      if (out.every((o) => block.end <= o.start || block.start >= o.end)) {
        out.add(block);
      }
    } catch (_) {}
  }
  return sortedByStart(out);
}

/// A named schedule, optionally auto-applied on some weekdays.
class Preset {
  const Preset({
    required this.id,
    required this.name,
    required this.blocks,
    this.weekdays = const {},
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<Block> blocks;

  /// 0 = Sunday … 6 = Saturday. Empty = never auto-applied.
  final Set<int> weekdays;

  /// Newer wins when several presets claim the same weekday.
  final DateTime updatedAt;

  Preset copyWith({Set<int>? weekdays, DateTime? updatedAt}) => Preset(
    id: id,
    name: name,
    blocks: blocks,
    weekdays: weekdays ?? this.weekdays,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'blocks': [for (final b in blocks) b.toJson()],
    'weekdays': weekdays.toList()..sort(),
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory Preset.fromJson(Map<String, dynamic> j) => Preset(
    id: j['id'] as String,
    name: j['name'] as String,
    blocks: _parseBlocks(j['blocks']),
    weekdays: {
      for (final w in j['weekdays'] as List? ?? const [])
        if (w is int && w >= 0 && w <= 6) w,
    },
    updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
  );
}

/// Everything the study feature persists.
class StudyData {
  StudyData({
    List<Block>? blocks,
    List<Preset>? presets,
    Map<String, int>? summaries,
    this.lastRecorded,
    this.threshold = 30,
  }) : blocks = blocks ?? [],
       presets = presets ?? [],
       summaries = summaries ?? {};

  List<Block> blocks;
  List<Preset> presets;

  /// Logical date key → planned study minutes of that finished day.
  Map<String, int> summaries;

  /// Last finished logical day already written to [summaries].
  String? lastRecorded;

  /// Streak threshold in minutes.
  int threshold;

  Map<String, Object?> toJson() => {
    'version': 1,
    'blocks': [for (final b in blocks) b.toJson()],
    'presets': [for (final p in presets) p.toJson()],
    'summaries': summaries,
    'lastRecorded': lastRecorded,
    'threshold': threshold,
  };

  factory StudyData.fromJson(Map<String, dynamic> j) => StudyData(
    blocks: _parseBlocks(j['blocks']),
    presets: [
      for (final p in j['presets'] is List ? j['presets'] as List : const [])
        ?_tryParse(() => Preset.fromJson(p as Map<String, dynamic>)),
    ],
    summaries: {
      for (final e in (j['summaries'] is Map ? j['summaries'] as Map : const {})
          .entries)
        if (e.key is String && e.value is int) e.key as String: e.value as int,
    },
    lastRecorded: _validDateKey(j['lastRecorded']),
    threshold: j['threshold'] is int ? j['threshold'] as int : 30,
  );
}

T? _tryParse<T>(T Function() parse) {
  try {
    return parse();
  } catch (_) {
    return null;
  }
}

String? _validDateKey(Object? v) =>
    v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) ? v : null;

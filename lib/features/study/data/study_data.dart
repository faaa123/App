import '../core/block.dart';

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
    blocks: [
      for (final b in j['blocks'] as List) Block.fromJson(b as Map<String, dynamic>),
    ],
    weekdays: {for (final w in j['weekdays'] as List) w as int},
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
    blocks: [
      for (final b in j['blocks'] as List? ?? const [])
        Block.fromJson(b as Map<String, dynamic>),
    ],
    presets: [
      for (final p in j['presets'] as List? ?? const [])
        Preset.fromJson(p as Map<String, dynamic>),
    ],
    summaries: {
      for (final e in (j['summaries'] as Map? ?? const {}).entries)
        e.key as String: e.value as int,
    },
    lastRecorded: j['lastRecorded'] as String?,
    threshold: j['threshold'] as int? ?? 30,
  );
}

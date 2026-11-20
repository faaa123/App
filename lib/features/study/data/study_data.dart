import '../core/block.dart';

/// Parses what can be parsed: entries that fail (bad types, impossible
/// offsets, overlaps with an earlier block) are dropped instead of throwing,
/// and reported through [onDrop].
List<Block> _parseBlocks(Object? list, [void Function()? onDrop]) {
  final out = <Block>[];
  for (final b in list is List ? list : const []) {
    try {
      final block = Block.fromJson(b as Map<String, dynamic>);
      if (out.every((o) => block.end <= o.start || block.start >= o.end)) {
        out.add(block);
        continue;
      }
    } catch (_) {}
    onDrop?.call();
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

  factory Preset.fromJson(Map<String, dynamic> j, [void Function()? onDrop]) {
    final weekdays = j['weekdays'] as List? ?? const [];
    final valid = {
      for (final w in weekdays)
        if (w is int && w >= 0 && w <= 6) w,
    };
    final preset = Preset(
      id: j['id'] as String,
      name: j['name'] as String,
      blocks: _parseBlocks(j['blocks'], onDrop),
      weekdays: valid,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(j['updatedAt'] as int),
    );
    if (valid.length != weekdays.length) onDrop?.call();
    return preset;
  }
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

  /// Set by [StudyData.fromJson] when something stored could not be kept
  /// (dropped entries, an unknown version): the next save would lose it.
  bool lossy = false;

  Map<String, Object?> toJson() => {
    'version': 1,
    'blocks': [for (final b in blocks) b.toJson()],
    'presets': [for (final p in presets) p.toJson()],
    'summaries': summaries,
    'lastRecorded': lastRecorded,
    'threshold': threshold,
  };

  factory StudyData.fromJson(Map<String, dynamic> j) {
    var lossy = j['version'] != 1;
    void drop() => lossy = true;
    final rawPresets = j['presets'] is List ? j['presets'] as List : const [];
    final presets = [
      for (final p in rawPresets)
        ?_tryParse(() => Preset.fromJson(p as Map<String, dynamic>, drop)),
    ];
    final rawSummaries = j['summaries'] is Map
        ? j['summaries'] as Map
        : const {};
    final summaries = {
      for (final e in rawSummaries.entries)
        if (_validDateKey(e.key) != null && e.value is int && e.value >= 0)
          e.key as String: e.value as int,
    };
    final t = j['threshold'];
    // setThreshold keeps it ≥ 10; calculateStreak throws on ≤ 0.
    final validThreshold = t is int && t >= 10 && t <= 1440;
    final lastRecorded = _validDateKey(j['lastRecorded']);
    final data = StudyData(
      blocks: _parseBlocks(j['blocks'], drop),
      presets: presets,
      summaries: summaries,
      lastRecorded: lastRecorded,
      threshold: validThreshold ? t : 30,
    );
    data.lossy =
        lossy ||
        presets.length != rawPresets.length ||
        summaries.length != rawSummaries.length ||
        (t != null && !validThreshold) ||
        (j['lastRecorded'] != null && lastRecorded == null);
    return data;
  }
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

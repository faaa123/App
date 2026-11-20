import 'logical_day.dart';

enum BlockType { study, rest }

/// One schedule block. Offsets are logical-day minutes; the interval is the
/// half-open [start, end). A block never crosses the 4:00 boundary.
class Block {
  Block({
    required this.id,
    required this.name,
    required this.type,
    required this.start,
    required this.end,
  }) {
    if (start < 0 || start >= LogicalDay.minutesPerDay) {
      throw ArgumentError('start out of range: $start');
    }
    if (end <= start || end > LogicalDay.minutesPerDay) {
      throw ArgumentError('invalid end: start=$start end=$end');
    }
  }

  final String id;
  final String name;
  final BlockType type;
  final int start;
  final int end;

  int get duration => end - start;
  bool contains(int offset) => offset >= start && offset < end;
  bool get isStudy => type == BlockType.study;

  Block copyWith({String? id, String? name, BlockType? type, int? start, int? end}) =>
      Block(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        start: start ?? this.start,
        end: end ?? this.end,
      );

  /// Same content, ignoring id.
  bool sameContentAs(Block o) =>
      name == o.name && type == o.type && start == o.start && end == o.end;

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'start': start,
    'end': end,
  };

  factory Block.fromJson(Map<String, dynamic> j) => Block(
    id: j['id'] as String,
    name: j['name'] as String,
    type: BlockType.values.byName(j['type'] as String),
    start: j['start'] as int,
    end: j['end'] as int,
  );
}

List<Block> sortedByStart(Iterable<Block> blocks) =>
    blocks.toList()..sort((a, b) => a.start.compareTo(b.start));

/// Same blocks (ignoring ids and order).
bool sameSchedule(List<Block> a, List<Block> b) {
  if (a.length != b.length) return false;
  final sa = sortedByStart(a), sb = sortedByStart(b);
  for (var i = 0; i < sa.length; i++) {
    if (!sa[i].sameContentAs(sb[i])) return false;
  }
  return true;
}

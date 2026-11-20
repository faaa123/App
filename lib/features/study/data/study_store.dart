import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Loads and saves the study feature's JSON document.
abstract interface class StudyStore {
  Future<Map<String, dynamic>?> load();
  Future<void> save(Map<String, Object?> json);
}

/// One JSON file in Application Support, written atomically.
class FileStudyStore implements StudyStore {
  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/study.json');
  }

  /// Returns null when there is no file or it cannot be read. An unreadable
  /// file is kept aside as `study.json.corrupt-<epochMs>` for recovery.
  @override
  Future<Map<String, dynamic>?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    try {
      final json = jsonDecode(await f.readAsString());
      if (json is Map<String, dynamic>) return json;
      throw const FormatException('study.json is not a JSON object');
    } catch (e) {
      debugPrint('study.json unreadable, starting fresh: $e');
      try {
        await f.rename(
          '${f.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}',
        );
      } catch (_) {}
      return null;
    }
  }

  Future<void> _queue = Future.value();

  /// Writes are serialized, so overlapping calls never share the temp file and
  /// land in call order. The snapshot is encoded at call time.
  @override
  Future<void> save(Map<String, Object?> json) {
    final text = jsonEncode(json);
    final done = _queue.then((_) => _write(text));
    _queue = done.catchError((_) {});
    return done;
  }

  Future<void> _write(String text) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(f.path);
  }
}

class MemoryStudyStore implements StudyStore {
  MemoryStudyStore([this.data]);
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async => data;

  @override
  Future<void> save(Map<String, Object?> json) async =>
      data = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
}

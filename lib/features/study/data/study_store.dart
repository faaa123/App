import 'dart:convert';
import 'dart:io';

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

  @override
  Future<Map<String, dynamic>?> load() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
  }

  @override
  Future<void> save(Map<String, Object?> json) async {
    final f = await _file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
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

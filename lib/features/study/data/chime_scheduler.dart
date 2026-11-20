import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/chime_plan.dart';
import '../core/logical_day.dart';

/// Delivers study⇄rest chimes, even when the app is closed.
abstract interface class ChimeScheduler {
  Future<void> init();

  /// Replaces every pending chime with [chimes].
  Future<void> replaceAll(List<Chime> chimes);
}

class NoopChimeScheduler implements ChimeScheduler {
  @override
  Future<void> init() async {}

  @override
  Future<void> replaceAll(List<Chime> chimes) async {}
}

/// iOS local notifications with sound. iOS keeps at most 64 pending
/// notifications per app, so callers pass a bounded list (see [planChimes]).
class NotificationChimeScheduler implements ChimeScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;

  /// Latest plan not yet applied; earlier unapplied plans are dropped.
  List<Chime>? _pending;
  Future<void>? _draining;

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  /// May wait for the permission prompt; [replaceAll] waits for it too, so
  /// callers need not await this.
  @override
  Future<void> init() => _ready ??= _plugin
      .initialize(
        settings: const InitializationSettings(
          iOS: DarwinInitializationSettings(
            requestAlertPermission: true,
            requestSoundPermission: true,
            requestBadgePermission: false,
          ),
        ),
      )
      .then((_) {});

  @override
  Future<void> replaceAll(List<Chime> chimes) {
    _pending = chimes;
    return _draining ??= _drain();
  }

  /// Applies only the newest pending plan, one at a time.
  Future<void> _drain() async {
    try {
      try {
        await _ready;
      } catch (_) {}
      while (_pending != null) {
        final c = _pending!;
        _pending = null;
        try {
          await _sync(c);
        } catch (_) {}
      }
    } finally {
      // Cleared in the same step the loop sees no pending plan, so a later
      // call always starts a new drain.
      _draining = null;
    }
  }

  /// Makes iOS hold exactly [chimes], touching only what differs. Ids are
  /// derived from each chime's content, so a resume after some chimes fired
  /// only adds the new tail instead of rewriting everything. If iOS dropped
  /// requests (e.g. notifications were off), they are simply added again.
  Future<void> _sync(List<Chime> chimes) async {
    final pending = {
      for (final r in await _plugin.pendingNotificationRequests()) r.id,
    };
    final diff = diffChimes(pending, chimes);
    for (final id in diff.cancel) {
      await _plugin.cancel(id: id);
    }
    for (final (id, c) in diff.add) {
      await _schedule(id, c);
    }
  }

  Future<void> _schedule(int id, Chime c) => _plugin.zonedSchedule(
    id: id,
    // Absolute instant; UTC avoids needing the tz database.
    scheduledDate: tz.TZDateTime.from(c.at.toUtc(), tz.UTC),
    notificationDetails: _details,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    title: c.next.isStudy ? '勉強の時間です' : '休憩の時間です',
    body: '${c.next.name}（〜${LogicalDay.clock(c.next.end)}）',
  );
}

/// Stable 31-bit id for a chime's content (FNV-1a).
int chimeId(Chime c) {
  final key =
      '${c.at.millisecondsSinceEpoch}|${c.next.name}|'
      '${c.next.type.name}|${c.next.end}';
  var h = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    h = ((h ^ unit) * 0x01000193) & 0xFFFFFFFF;
  }
  return h & 0x7FFFFFFF;
}

/// What to cancel and what to add so that [pendingIds] matches [chimes].
({List<int> cancel, List<(int, Chime)> add}) diffChimes(
  Set<int> pendingIds,
  List<Chime> chimes,
) {
  final wanted = <int, Chime>{};
  for (final c in chimes) {
    wanted.putIfAbsent(chimeId(c), () => c);
  }
  return (
    cancel: [
      for (final id in pendingIds)
        if (!wanted.containsKey(id)) id,
    ],
    add: [
      for (final e in wanted.entries)
        if (!pendingIds.contains(e.key)) (e.key, e.value),
    ],
  );
}

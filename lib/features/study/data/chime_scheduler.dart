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

  /// Key of the plan currently registered with iOS.
  String? _appliedKey;

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

  /// Applies only the newest pending plan, one at a time, and skips a plan
  /// identical to the one already registered.
  Future<void> _drain() async {
    try {
      try {
        await _ready;
      } catch (_) {}
      while (_pending != null) {
        final c = _pending!;
        _pending = null;
        final key = _key(c);
        if (key == _appliedKey && await _stillRegistered(c)) continue;
        try {
          _appliedKey = null;
          await _replace(c);
          // iOS silently drops requests while notifications are off, so only
          // remember the plan once they are on (a later resume re-applies).
          if (await _enabled()) _appliedKey = key;
        } catch (_) {}
      }
    } finally {
      // Cleared in the same step the loop sees no pending plan, so a later
      // call always starts a new drain.
      _draining = null;
    }
  }

  /// False when iOS holds fewer requests than the plan's future chimes
  /// (e.g. they were dropped while notifications were disabled).
  Future<bool> _stillRegistered(List<Chime> chimes) async {
    try {
      final now = DateTime.now();
      final future = chimes.where((c) => c.at.isAfter(now)).length;
      return (await _plugin.pendingNotificationRequests()).length >= future;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _enabled() async {
    try {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios == null) return true;
      return (await ios.checkPermissions())?.isEnabled ?? false;
    } catch (_) {
      return false;
    }
  }

  static String _key(List<Chime> chimes) => [
    for (final c in chimes)
      '${c.at.millisecondsSinceEpoch}|${c.next.name}|'
          '${c.next.type.name}|${c.next.end}',
  ].join(',');

  Future<void> _replace(List<Chime> chimes) async {
    await _plugin.cancelAll();
    for (var i = 0; i < chimes.length; i++) {
      final c = chimes[i];
      await _plugin.zonedSchedule(
        id: i,
        // Absolute instant; UTC avoids needing the tz database.
        scheduledDate: tz.TZDateTime.from(c.at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: c.next.isStudy ? '勉強の時間です' : '休憩の時間です',
        body: '${c.next.name}（〜${LogicalDay.clock(c.next.end)}）',
      );
    }
  }
}

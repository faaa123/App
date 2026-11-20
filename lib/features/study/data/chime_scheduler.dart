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
  Future<void> _queue = Future.value();

  static const _details = NotificationDetails(
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
  );

  @override
  Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestSoundPermission: true,
          requestBadgePermission: false,
        ),
      ),
    );
  }

  @override
  Future<void> replaceAll(List<Chime> chimes) {
    // Serialize: a later call must not interleave with an earlier one.
    return _queue = _queue.then((_) => _replace(chimes)).catchError((_) {});
  }

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

import 'package:core/core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The trust mechanism, part 2 (SPEC.md): every skipped alarm leaves a
/// notification saying exactly why — windy, gusty, or no data.
/// A skipped ring must never be confusable with a broken app.
class SkipNotifier {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Don't request here (init runs in background isolates too); the
        // foreground app calls requestPermissionIfNeeded() explicitly.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  /// Request notification permission on BOTH platforms. iOS is essential: the
  /// alarm package never requests it (it only checks and silently drops the
  /// notification), so without this the skip cards never appear on iOS.
  Future<void> requestPermissionIfNeeded() async {
    await ensureInitialized();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true, badge: false);
  }

  Future<void> showSkip(HistoryRecord record, String courtName) async {
    await ensureInitialized();
    // "Sleep in" is a genuine silver lining for a morning game; a later game
    // gets a hopeful, forward-looking sign-off (never one that sounds glad
    // the session is off).
    final signOff = record.at.hour < 12 ? 'sleep in 😴' : 'next time 🏸';
    // Show all four numbers (speed & gust, each vs its cap) so the skip is
    // fully self-explaining, not just the one metric that tripped.
    final body = switch (record.outcome) {
      CheckOutcome.skippedWindy =>
        '$courtName too windy · ${record.windGustSummary} — $signOff',
      CheckOutcome.skippedGusty =>
        '$courtName too gusty · ${record.windGustSummary} — $signOff',
      CheckOutcome.skippedNoData =>
        'Could not check the wind at $courtName — alarm skipped',
      CheckOutcome.rang => '', // never notified; the ring speaks for itself
    };
    if (body.isEmpty) return;

    await _plugin.show(
      // One card per alarm per day; a later skip replaces the older card.
      id: 600000 + record.alarmId,
      title: 'Nivaat skipped ${fmtClock(record.at)}',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          // v2: was a silent low-importance channel; made a normal audible
          // notification 2026-07-12 (user decision). Android freezes a
          // channel's importance at first creation, hence the new id.
          'nivaat_skips_v2',
          'Skipped alarms',
          channelDescription: 'Why an alarm did not ring',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentBadge: false,
        ),
      ),
    );
  }
}

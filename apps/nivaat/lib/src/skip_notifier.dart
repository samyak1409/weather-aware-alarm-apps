import 'package:core/core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The trust mechanism, part 2 (SPEC.md): every skipped alarm leaves a
/// silent notification saying exactly why — windy, gusty, or no data.
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
        iOS: DarwinInitializationSettings(
          // The alarm package already obtains the notification permission;
          // don't double-prompt from here.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  /// Ask for permission on Android 13+ (no-op if already granted / iOS).
  Future<void> requestPermissionIfNeeded() async {
    await ensureInitialized();
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showSkip(HistoryRecord record, String courtName) async {
    await ensureInitialized();
    final body = switch (record.outcome) {
      CheckOutcome.skippedWindy =>
        'Wind ${record.courtSpeedKmh!.toStringAsFixed(1)} km/h at $courtName — sleep in 😴',
      CheckOutcome.skippedGusty =>
        'Gusts ${record.rawGustKmh!.toStringAsFixed(0)} km/h at $courtName — sleep in 😴',
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
          'nivaat_skips',
          'Skipped alarms',
          channelDescription: 'Why an alarm did not ring',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
          enableVibration: false,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: false,
          presentBadge: false,
        ),
      ),
    );
  }
}

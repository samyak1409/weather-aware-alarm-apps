import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Requests notification permission on BOTH platforms — without the grant the
/// bedtime ring's notification is silently suppressed. Android needs the 13+
/// runtime grant; iOS needs it too because the `alarm` package only *checks*
/// authorization and never requests it (the wake alarm rings via AlarmKit's
/// own authorization on iOS 26+). No-op once granted.
///
/// The ring notification itself belongs to the alarm plugin (Stop button
/// only, by plugin design); tapping it opens the still-ringing full screen,
/// where the bedtime "+1h" lives.
Future<void> requestNotificationPermission() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ),
  );
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  await plugin
      .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
      ?.requestPermissions(alert: true, sound: true, badge: false);
}

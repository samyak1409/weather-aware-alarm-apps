import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Set only after [requestNotificationPermission] has completed at least once
/// — i.e. the user has ANSWERED the system prompt. Before that, a "not
/// granted" status means undetermined, not denied.
const String _askedKey = 'arunoday.notifPermissionAsked';

Future<FlutterLocalNotificationsPlugin> _initializedPlugin() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  return plugin;
}

/// Requests notification permission — **Android only** (the 13+ runtime
/// grant): without it the `alarm` package's ring notification (the card, the
/// full-screen UI, the Stop button) is silently suppressed, leaving bare
/// sound.
///
/// iOS deliberately asks nothing (2026-07-20, user decision): since the
/// AlarmKit-only switch (2026-07-16) Arunoday posts NO iOS notifications —
/// both rings are AlarmKit's own full-screen alerts — so the old iOS request
/// (2026-07-13, pre-AlarmKit) had become a prompt for nothing. Nivaat still
/// requests on both platforms; its skip cards are real iOS notifications.
Future<void> requestNotificationPermission() async {
  if (!Platform.isAndroid) return;
  final plugin = await _initializedPlugin();
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();
  // Only now — the request future resolves when the dialog is answered (or
  // was never needed), which is when "denied" becomes a meaningful verdict.
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_askedKey, true);
}

/// True only when the user has answered the permission prompt with no —
/// undetermined (never asked) is NOT "denied", or the home-screen banner
/// would flash behind the first-run dialog. Feeds
/// [NotificationPermissionBanner]; Android-only, like the request above.
Future<bool> notificationsDenied() async {
  if (!Platform.isAndroid) return false;
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(_askedKey) ?? false)) return false;
  final plugin = await _initializedPlugin();
  final enabled = await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.areNotificationsEnabled();
  return enabled == false;
}

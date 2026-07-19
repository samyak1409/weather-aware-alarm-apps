import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  /// Set only after [requestPermissionIfNeeded] has completed at least once —
  /// i.e. the user has ANSWERED the system prompt. Before that, a "not
  /// granted" status means undetermined, not denied.
  static const String _askedKey = 'nivaat.notifPermissionAsked';

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
    // Only now — the request futures resolve when the dialog is answered (or
    // was never needed), which is when "denied" becomes a meaningful verdict.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
  }

  /// True only when the user has answered the permission prompt with no —
  /// undetermined (never asked) is NOT "denied", or the home-screen banner
  /// would flash behind the first-run dialog. Feeds
  /// [NotificationPermissionBanner].
  Future<bool> notificationsDenied() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_askedKey) ?? false)) return false;
    await ensureInitialized();
    if (Platform.isAndroid) {
      final enabled = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return enabled == false;
    }
    final options = await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.checkPermissions();
    return options != null && !options.isEnabled;
  }

  // The "still checking" heads-up (at T) and the final skip card (at the cap)
  // are SEPARATE notifications with distinct ids — so the cap fires a fresh,
  // alerting card and does NOT overwrite the heads-up. Per-alarm ids, so a new
  // day's occurrence replaces its own kind.
  static const int _headsUpId = 600000;
  static const int _skipId = 610000;

  // Shared card style — a normal audible notification.
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      // v2: was a silent low-importance channel; made a normal audible
      // notification 2026-07-12 (user decision). Android freezes a channel's
      // importance at first creation, hence the new id.
      'nivaat_skips_v2',
      'Skipped alarms',
      channelDescription: 'Why an alarm did not ring',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentBadge: false),
  );

  // One reason phrase, shared by both cards (within-notification consistency).
  String _reason(HistoryRecord record, String courtName) =>
      switch (record.outcome) {
        CheckOutcome.skippedWindy => '$courtName too windy',
        CheckOutcome.skippedGusty => '$courtName too gusty',
        CheckOutcome.skippedNoData => "Couldn't reach the wind at $courtName",
        CheckOutcome.rang => '',
      };

  // "· checked HH:MM" (or "· last tried HH:MM" for no-data) — always shown, as
  // reinforcement that the result came from a real check. Same data the history
  // row shows, for notification↔history parity.
  String _checked(HistoryRecord record) {
    final verb =
        record.outcome == CheckOutcome.skippedNoData ? 'last tried' : 'checked';
    return ' · $verb ${fmtCheckTime(record.whenChecked, record.at)}';
  }

  /// Heads-up posted at T for a skipped occurrence: the reason so far, plus a
  /// note that the app keeps checking in the background until [until] and will
  /// ring if it clears. Left in place afterwards (a late ring, or the separate
  /// final card at the cap, follows it — it isn't cleared).
  Future<void> showExtendedCheck(
      HistoryRecord record, String courtName, DateTime until) async {
    await ensureInitialized();
    final nums = record.windGustSummary;
    // No-data can't "calm" — it's a connectivity problem — so its promise is
    // to ring once the wind is reachable again, not once it drops.
    final promise = record.outcome == CheckOutcome.skippedNoData
        ? "will ring once it's reachable"
        : 'will ring if it calms';
    await _plugin.show(
      id: _headsUpId + record.alarmId,
      title: 'Nivaat ${fmtClock(record.at)} · still checking',
      body: '${_reason(record, courtName)}${nums.isEmpty ? '' : ' · $nums'}'
          '${_checked(record)} · '
          'keeping watch until ${fmtClock(until)}, $promise 🏸',
      notificationDetails: _details,
    );
  }

  /// The final "here's why it didn't ring" card, at the +30m cap — a separate,
  /// alerting notification (does not replace the heads-up).
  Future<void> showSkip(HistoryRecord record, String courtName) async {
    await ensureInitialized();
    final body = switch (record.outcome) {
      CheckOutcome.skippedWindy || CheckOutcome.skippedGusty =>
        '${_reason(record, courtName)} · ${record.windGustSummary}'
            '${_checked(record)} — next time 🏸',
      CheckOutcome.skippedNoData =>
        '${_reason(record, courtName)}${_checked(record)}',
      CheckOutcome.rang => '', // never notified; the ring speaks for itself
    };
    if (body.isEmpty) return;

    await _plugin.show(
      id: _skipId + record.alarmId,
      title: 'Nivaat ${fmtClock(record.at)} · skipped',
      body: body,
      notificationDetails: _details,
    );
  }
}

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Title of all three Nivaat cards (MESSAGES.md N1/N2/N3):
/// `{court} · {HH:MM} · {status}` — [kNivaatRing] / [kNivaatStillChecking] /
/// [kNivaatSkipped].
///
/// The app name is deliberately absent (2026-07-22): both OS notification
/// headers already print it above the title, so "Nivaat" spent the scannable
/// head of the line on a repeat. The court leads instead — it's what tells two
/// alarms apart. `at` is always the alarm time the user set, never the ring or
/// check time.
String nivaatNotificationTitle(String courtName, DateTime at, String status) =>
    '$courtName · ${fmtClock(at)} · $status';

/// The three title statuses. Sentence-capitalised: they head a title now, not
/// a mid-sentence clause (2026-07-22). The ring's is the verdict itself — it
/// moved up out of the body, where the numbers now stand alone.
const String kNivaatRing = 'Play! 🏸';
const String kNivaatStillChecking = 'Still checking';
const String kNivaatSkipped = 'Skipped';

// One reason phrase, shared by both cards (within-notification consistency).
// Court-free since 2026-07-22 — the title names it now.
String _reason(HistoryRecord record) => switch (record.outcome) {
      CheckOutcome.skippedWindy => 'Too windy',
      CheckOutcome.skippedGusty => 'Too gusty',
      CheckOutcome.skippedNoData => "Couldn't reach the wind",
      CheckOutcome.rang => '',
    };

/// ` · checked HH:MM` — or ` · last tried HH:MM` when no check ever succeeded.
/// On every card including the ring (2026-07-22), as reinforcement that the
/// result came from a real reading. `alarmAt` only decides whether the date is
/// needed: a ring booked from last night's forecast reads ` · checked 17 Jul
/// 22:00`, never a bare `22:00` that looks like this morning.
///
/// The same value its history row shows — the engine writes `lastCheckAt` on
/// the very branch that schedules the ring, so N1 and N5 always agree.
String nivaatCheckedNote(DateTime whenChecked, DateTime alarmAt,
        {bool tried = false}) =>
    ' · ${tried ? 'last tried' : 'checked'} '
    '${fmtCheckTime(whenChecked, alarmAt)}';

String _checked(HistoryRecord record) => nivaatCheckedNote(
      record.whenChecked,
      record.at,
      tried: record.outcome == CheckOutcome.skippedNoData,
    );

// Reason + numbers + freshness: the whole of the final card, and the head of
// the heads-up. No-data carries no numbers, so its middle drops out.
String _reasonNumsChecked(HistoryRecord record) {
  final nums = record.windGustSummary;
  return '${_reason(record)}${nums.isEmpty ? '' : ' · $nums'}'
      '${_checked(record)}';
}

/// Body of the at-T heads-up (MESSAGES.md N2) — the final card's body plus the
/// deadline still being watched.
String nivaatExtendedCheckBody(HistoryRecord record, DateTime until) =>
    '${_reasonNumsChecked(record)} · watching until ${fmtCheckTime(until, record.at)}';

/// Body of the final skip card (MESSAGES.md N3). Empty for a ring — that
/// occurrence is never notified, the ring speaks for itself.
String nivaatSkipBody(HistoryRecord record) =>
    record.outcome == CheckOutcome.rang ? '' : _reasonNumsChecked(record);

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
  //
  // One channel carries BOTH cards, so it can't be named for only one of them:
  // muting "Skipped alarms" would also have killed the still-checking heads-up,
  // the card that's still worth acting on. Renamed 2026-07-22, id reset to drop
  // the `_v2` (that suffix only existed because Android freezes a channel's
  // importance at creation, and the 2026-07-12 silent→audible switch needed a
  // fresh id; with no installed base there's nothing to migrate).
  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'nivaat_alarm_updates',
      'Alarm updates',
      channelDescription: "Still checking, and why an alarm didn't ring",
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentBadge: false),
  );

  /// Heads-up posted at T for a skipped occurrence: the reason so far, plus a
  /// note that the app keeps checking in the background until [until] and will
  /// ring if it clears. Left in place afterwards (a late ring, or the separate
  /// final card at the cap, follows it — it isn't cleared).
  Future<void> showExtendedCheck(
      HistoryRecord record, String courtName, DateTime until) async {
    await ensureInitialized();
    await _plugin.show(
      id: _headsUpId + record.alarmId,
      title:
          nivaatNotificationTitle(courtName, record.at, kNivaatStillChecking),
      body: nivaatExtendedCheckBody(record, until),
      notificationDetails: _details,
    );
  }

  /// The final "here's why it didn't ring" card, at the +30m cap — a separate,
  /// alerting notification (does not replace the heads-up).
  Future<void> showSkip(HistoryRecord record, String courtName) async {
    await ensureInitialized();
    final body = nivaatSkipBody(record);
    if (body.isEmpty) return;

    await _plugin.show(
      id: _skipId + record.alarmId,
      title: nivaatNotificationTitle(courtName, record.at, kNivaatSkipped),
      body: body,
      notificationDetails: _details,
    );
  }
}

import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ids.dart';

/// Title of every Nivaat card (MESSAGES.md N1/N2):
/// `{court} · {HH:MM} · {status}`.
///
/// The app name is deliberately absent (2026-07-22): both OS notification
/// headers already print it above the title, so "Nivaat" spent the scannable
/// head of the line on a repeat. The court leads instead — it's what tells two
/// alarms apart. `at` is always the alarm time the user set, never the ring or
/// check time.
String nivaatNotificationTitle(String courtName, DateTime at, String status) =>
    '$courtName · ${fmtClock(at)} · $status';

/// The title statuses. Sentence-capitalised: they head a title, not a
/// mid-sentence clause (2026-07-22). The ring's is the verdict itself — it
/// moved up out of the body, where the numbers now stand alone.
///
/// [kNivaatStillChecking] / [kNivaatSkipped] / [kNivaatCancelled] are three
/// states of the SAME card (2026-07-26), not three cards — see [SkipNotifier].
/// `Cancelled` rather than `Stopped` because the ring's own button is literally
/// `Stop`, and "Stopped" on a card would read as "you silenced the alarm".
const String kNivaatRing = 'Play! 🏸';
const String kNivaatStillChecking = 'Still checking';
const String kNivaatSkipped = 'Skipped';
const String kNivaatCancelled = 'Cancelled';

// One reason phrase, shared by both cards (within-notification consistency).
// Court-free since 2026-07-22 — the title names it now.
String _reason(HistoryRecord record) => switch (record.outcome) {
      CheckOutcome.skippedWindy => 'Too windy',
      CheckOutcome.skippedGusty => 'Too gusty',
      CheckOutcome.skippedNoData => "Couldn't reach the wind",
      CheckOutcome.rang => '',
    };

/// ` · last checked HH:MM` — the freshness of the reading behind this row.
/// One helper for every surface, so a card and its history row can't drift.
///
/// Three labels (2026-07-26):
/// * `last checked` — the most recent successful reading. The default,
///   because retries mean there is almost always more than one.
/// * `last tried` — no reading ever succeeded, so this is the last attempt.
/// * `checked` — the ring only. One check approved it; "last" would imply
///   others that never happened.
///
/// `alarmAt` only decides whether the date is needed: a ring booked from last
/// night's forecast reads ` · checked 17 Jul 22:00`, never a bare `22:00` that
/// looks like this morning.
String nivaatCheckedNote(
  DateTime whenChecked,
  DateTime alarmAt, {
  bool tried = false,
  bool ring = false,
}) =>
    ' · ${tried ? 'last tried' : ring ? 'checked' : 'last checked'} '
    '${fmtCheckTime(whenChecked, alarmAt)}';

String _checked(HistoryRecord record) => nivaatCheckedNote(
      record.whenChecked,
      record.at,
      tried: record.outcome == CheckOutcome.skippedNoData,
    );

// Reason + numbers + freshness: the head of every state of the card.
// No-data carries no numbers, so its middle drops out.
String _reasonNumsChecked(HistoryRecord record) {
  final nums = record.windGustSummary;
  return '${_reason(record)}${nums.isEmpty ? '' : ' · $nums'}'
      '${_checked(record)}';
}

/// `watching until 06:30` — the deadline the card is promising. Bare phrase;
/// every caller supplies its own ` · ` joiner (the notification bodies and the
/// history sheet's sub join differently, but must never word it differently).
String nivaatWatchingUntilPhrase(DateTime until, DateTime alarmAt) =>
    'watching until ${fmtCheckTime(until, alarmAt)}';

/// `watched until 06:30` — how far checking actually reached, used ONLY when
/// that differs from the last reading. They match on almost every morning;
/// when they don't, the final attempt failed to reach the network, and this is
/// the one thing separating "we gave up at 06:29" from "we tried at 06:30 and
/// got nothing" (2026-07-26).
String nivaatWatchedUntilPhrase(DateTime endedAt, DateTime alarmAt) =>
    'watched until ${fmtCheckTime(endedAt, alarmAt)}';

/// `stopped 06:05` — when YOU ended the morning.
String nivaatStoppedPhrase(DateTime stoppedAt, DateTime alarmAt) =>
    'stopped ${fmtCheckTime(stoppedAt, alarmAt)}';

/// True when checking outlasted the last successful reading — see
/// [nivaatWatchedUntilPhrase]. Compared at displayed granularity, since a row
/// that prints the same minute twice is noise, not information.
///
/// Compared through [fmtCheckTime] — literally what the row renders — rather
/// than a bare clock, so "displayed granularity" stays true if a window ever
/// spans midnight and the two moments share an HH:MM.
bool nivaatOutlastedLastReading(HistoryRecord record) {
  final endedAt = record.checkingEndedAt;
  return endedAt != null &&
      fmtCheckTime(endedAt, record.at) !=
          fmtCheckTime(record.whenChecked, record.at);
}

/// Body while the retry window runs (MESSAGES.md N2 · still checking).
String nivaatStillCheckingBody(HistoryRecord record, DateTime until) =>
    '${_reasonNumsChecked(record)} · '
    '${nivaatWatchingUntilPhrase(until, record.at)}';

/// Body once the morning ends without a ring (MESSAGES.md N2 · skipped).
/// Empty for a ring — that morning's card is the ring itself.
String nivaatSkippedBody(HistoryRecord record) {
  if (record.outcome == CheckOutcome.rang) return '';
  final reach = nivaatOutlastedLastReading(record)
      ? ' · ${nivaatWatchedUntilPhrase(record.checkingEndedAt!, record.at)}'
      : '';
  return '${_reasonNumsChecked(record)}$reach';
}

/// Body when you stopped the morning yourself (MESSAGES.md N2 · cancelled).
/// Richer than its history row on purpose: the row sits beside the still-
/// checking row that already carries the numbers, the card has no neighbour.
String nivaatCancelledBody(HistoryRecord record) {
  final stoppedAt = record.checkingEndedAt;
  return '${_reasonNumsChecked(record)}'
      '${stoppedAt == null ? '' : ' · ${nivaatStoppedPhrase(stoppedAt, record.at)}'}';
}

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
        // Monochrome silhouette; the launcher icon alpha-masks to a blob.
        android: AndroidInitializationSettings('@drawable/$kNotificationIconRes'),
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

  // ONE CARD PER MORNING (2026-07-26). A single notification id
  // ([NivaatIds.card]) posts at T as "Still checking" and is rewritten in
  // place to "Skipped" or "Cancelled" as the morning resolves. There is no
  // second card: the earlier design left the heads-up standing beside a fresh
  // skip card, so the shade kept a promise ("watching until 06:30") that the
  // morning had already broken.
  //
  // Every push ALERTS. Rewriting is new information every time — even the
  // Keep-checking deadline move, which is a change you made and want
  // confirmed. That is why there is no quiet variant and no `onlyAlertOnce`:
  // one style, no platform-specific presentation flags to reason about.
  //
  // Posting to an id that is not currently showing CREATES it, so a card you
  // swiped away comes back with the outcome — which is the right answer, since
  // the outcome is news you haven't seen.
  //
  // The channel carries every state, so it can't be named for one of them:
  // muting "Skipped alarms" would also have killed the still-checking card,
  // the one that's still worth acting on. Renamed 2026-07-22, id reset to drop
  // the `_v2` (that suffix only existed because Android freezes a channel's
  // importance at creation, and the 2026-07-12 silent→audible switch needed a
  // fresh id; a channel already on a phone is a clear-data problem, not one
  // this repo carries — see CLAUDE.md on the no-migration policy).
  //
  // Public (2026-07-31) so `notification_message_test` can lock them: the name
  // and description are user-visible in Android's notification settings — the
  // one screen where you decide whether to keep hearing this app — and the id
  // is worse than user-visible, it is PERSISTED. Android keeps a channel by id
  // and freezes its importance at creation, so an innocuous rename here
  // orphans the live channel and silently resets the user's choice.
  @visibleForTesting
  static const String channelId = 'nivaat_alarm_updates';
  @visibleForTesting
  static const String channelName = 'Alarm updates';
  @visibleForTesting
  static const String channelDescription =
      "Still checking, and why an alarm didn't ring";

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentBadge: false),
  );

  Future<void> _push(
    HistoryRecord record,
    String courtName,
    String status,
    String body,
  ) async {
    await ensureInitialized();
    if (body.isEmpty) return;
    await _plugin.show(
      id: NivaatIds.card(record.alarmId),
      title: nivaatNotificationTitle(courtName, record.at, status),
      body: body,
      notificationDetails: _details,
    );
  }

  /// Posted at T when the alarm didn't ring: the reason so far, plus the
  /// deadline the app keeps checking toward. Re-posted with a new deadline
  /// whenever Keep checking is edited mid-window.
  Future<void> showStillChecking(
          HistoryRecord record, String courtName, DateTime until) =>
      _push(record, courtName, kNivaatStillChecking,
          nivaatStillCheckingBody(record, until));

  /// The morning ended without a ring. Rewrites the same card.
  Future<void> showSkipped(HistoryRecord record, String courtName) =>
      _push(record, courtName, kNivaatSkipped, nivaatSkippedBody(record));

  /// You ended the morning yourself — toggled the alarm off, or edited its
  /// time or court so today's window was abandoned. Rewrites the same card.
  Future<void> showCancelled(HistoryRecord record, String courtName) =>
      _push(record, courtName, kNivaatCancelled, nivaatCancelledBody(record));

  /// Take [alarmId]'s card down. Used when the alarm is **deleted** or its
  /// court is gone — a card for something that no longer exists is an orphan
  /// no rewrite can fix — and when a late ring lands, where the ring itself
  /// becomes that morning's card.
  ///
  /// Cancelling an id that isn't posted is a no-op, so this is safe on every
  /// pass. History keeps the durable record either way.
  Future<void> cancelForAlarm(int alarmId) async {
    await ensureInitialized();
    await _plugin.cancel(id: NivaatIds.card(alarmId));
  }
}

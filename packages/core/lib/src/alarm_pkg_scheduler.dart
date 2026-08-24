import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_exception.dart';
import 'package:flutter/foundation.dart';

import 'host_alarm_events.dart';
import 'scheduler.dart';

/// The Android status-bar notification icon, by resource name (CLAUDE.md).
///
/// Names a monochrome drawable, never the launcher art — Android alpha-masks
/// small icons. Compiled into core, so **both apps must ship
/// `res/drawable/<this>.xml` plus the `keep.xml` that survives the resource
/// shrinker**; each app's `notification_icon_test` checks both off disk,
/// because a miss is silent on the ring path (falls back to the launcher
/// blob) and a loud `invalid_icon` on the flutter_local_notifications one.
const String kNotificationIconRes = 'ic_notification';

/// [AlarmScheduler] backed by the `alarm` pub package — **Android only**. On
/// iOS `createAlarmScheduler` always picks `AlarmKitScheduler` and there is no
/// `alarm`-package fallback (a denied AlarmKit no-ops + nudges to Settings),
/// so this never runs on iOS.
class AlarmPkgScheduler implements AlarmScheduler {
  AlarmPkgScheduler({
    required String Function(double volume) soundAssetForVolume,
    HostAlarmEventClaims? claims,
    HostAlarmEventSource? eventSource,
  })  : _soundAssetForVolume = soundAssetForVolume,
        _bridge = HostAlarmEventBridge(
          events: eventSource ?? _alarmEventsAsHost,
          claims: claims ?? HostAlarmEventClaims(),
          ensurePluginReady: () async {
            if (!_initialized) {
              await Alarm.init(acknowledgeEventsAutomatically: false);
              _initialized = true;
            }
          },
        );

  /// Resolves the sound at schedule time (user-selectable tone). Receives the
  /// ring volume for parity with AlarmKit's loudness-variant mapping; this
  /// scheduler applies real volume instead, so it is PRIVATE and reachable
  /// only through [ringAsset] — passing a ring volume here is the bug that
  /// getter exists to prevent.
  final String Function(double volume) _soundAssetForVolume;

  final HostAlarmEventBridge _bridge;

  /// Test seam: the claim store the bridge uses.
  @visibleForTesting
  HostAlarmEventClaims get hostEventClaims => _bridge.claims;

  static Stream<HostAlarmEvent> _alarmEventsAsHost() => Alarm.events.map(_toHost);

  static HostAlarmEvent _toHost(AlarmEvent e) => HostAlarmEvent(
        id: e.id,
        kind: switch (e) {
          AlarmMoved() => HostAlarmEventKind.moved,
          AlarmDropped() => HostAlarmEventKind.dropped,
        },
        cause: switch (e.cause) {
          AlarmEventCause.snooze => HostAlarmEventCause.snooze,
          AlarmEventCause.platformRefusal => HostAlarmEventCause.platformRefusal,
          AlarmEventCause.staleAtBoot => HostAlarmEventCause.staleAtBoot,
        },
        recordedAt: e.recordedAt,
        at: switch (e) {
          AlarmMoved(:final nextRingAt) => nextRingAt,
          AlarmDropped(:final scheduledFor) => scheduledFor,
        },
        acknowledge: () => Alarm.acknowledgeEvent(e),
      );

  /// The tone to play, resolved at FULL volume whatever the ring volume is.
  ///
  /// This scheduler sets the real system volume (see [scheduleRing]), so a
  /// pre-attenuated variant would apply Nivaat's wind ramp TWICE — the ramp's
  /// quietest file at the same fraction of system volume landed near 56% of
  /// full, below the ramp's own floor and quieter than the identical ring on
  /// iOS. Resolving at 1.0 yields the user's selected tone, or the
  /// unattenuated master for the default one. iOS keeps the variants —
  /// AlarmKit has no volume knob (2026-07-26).
  ///
  /// The plugin's `VolumeService` quantises to a stream index
  /// (`round(volume × getStreamMaxVolume(STREAM_ALARM))`), which is exactly
  /// why core's `windVolumeSteps` has only three entries: they land on
  /// distinct indices at both common step counts (7 → 7/6/5, 15 → 15/13/11),
  /// so Android now reproduces the same three steps iOS gets from files. Keep
  /// the ramp here rather than on the variants — only the system volume ramps
  /// a user-SELECTED tone, which has no pre-rendered copies. See SPEC.md's
  /// volume rule before changing either side.
  String get ringAsset => _soundAssetForVolume(1);

  static bool _initialized = false;

  @override
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    // Manual acknowledgement — see `HostAlarmEvent.acknowledge` for why. BOTH
    // init sites pass it: the flag is static per isolate, and a background
    // isolate reaches the `ensurePluginReady` closure above first.
    await Alarm.init(acknowledgeEventsAutomatically: false);
    _initialized = true;
    // Start the bridge after init so the replay buffer is already filled;
    // handlers still run only when [applyHostAlarmEvents] is awaited.
    await _bridge.start();
  }

  /// Arms the ring, and reports whether the plugin took it.
  ///
  /// **`true` means armed on Android from alarm 5.9.0** (upstream #420 / #422):
  /// a failed native schedule unsaves and throws `AlarmException`, which this
  /// method catches as `false`. Before 5.9.0 the plugin reported success even
  /// when the platform scheduling failed; that half is closed upstream.
  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    await ensureInitialized();
    try {
      return await Alarm.set(
        alarmSettings: settingsFor(
          id: id,
          at: at,
          title: title,
          body: body,
          volume: volume,
        ),
      );
    } on AlarmException catch (e) {
      // `Alarm.set` already stopped and unsaved the alarm on this path, so
      // there is nothing to undo — only a claim not to make. Letting it
      // propagate (the old behaviour) aborted the whole cascade pass on its
      // way out, which cost the OTHER alarms their evaluation too.
      debugPrint('scheduleRing($id) rejected by the alarm plugin: $e');
      return false;
    }
  }

  /// The alarm as this scheduler configures it — pure, so every decision baked
  /// in here is testable off-device (the rest of [scheduleRing] is plugin
  /// calls), notification settings included.
  ///
  /// **`androidStopAlarmOnDismiss: false`** (alarm 5.9.0 / #421 / #423). A
  /// swipe on an unlocked phone re-posts the notification while the alarm is
  /// still ringing, so the Stop control is never lost. Before 5.9.0 the
  /// opt-out only ignored the swipe and left a sounding alarm with no on-screen
  /// control — which is why this stayed at the plugin's `true` as an interim.
  /// Locked phones already keep the notification pinned (`setOngoing`), so the
  /// swipe case that matters is unlocked-only.
  @visibleForTesting
  AlarmSettings settingsFor({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) =>
      AlarmSettings(
        id: id,
        dateTime: at,
        assetAudioPath: ringAsset,
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        // Android-only path: the ring is a foreground service + AlarmManager
        // alarm that genuinely survives the app being swiped/killed, so the
        // package's "may not ring" warning would be a false alarm here. Off.
        // (The iOS unreliability that warning is for no longer applies — iOS
        // uses AlarmKit, never this scheduler.)
        warningNotificationOnKill: false,
        // Two things, both verified in the plugin's Kotlin (AlarmService.kt):
        //
        // 1. Schedule time — without this, `Alarm.set` stops any alarm landing
        //    on the SAME SECOND even under a different id. A late ring is
        //    `now + 10s` off an arbitrary check instant, so it can coincide
        //    with another alarm's exact minute and silently kill it.
        // 2. Ring time — with `allowAlarmOverlap: false` and this OFF, an
        //    alarm firing while another is still ringing is DROPPED and
        //    unsaved ("Ignoring new alarm with id"). A 06:00 ring you haven't
        //    stopped would swallow the 06:07 one, while history logged "Rang".
        //    ON, it queues instead and rings when the current one is stopped.
        //
        // Same-ID replacement is a separate condition and is unaffected, so
        // re-deciding an occurrence still overwrites its own ring as before.
        allowSameSecondScheduling: true,
        // A null volume leaves the system alarm volume alone — the plugin
        // documents `volume: null` as "use the current system volume", which
        // is the only correct answer for an app with no volume opinion of its
        // own. Arunoday turned the phone up to full and pinned it there, so a
        // deliberately quiet phone rang at maximum (device-caught 2026-08-05).
        //
        // `volumeEnforced` follows the same fact: it means "put it back if the
        // user turns it down", which is meaningless without a volume to put
        // back, and hostile besides. It stays on for Nivaat, whose ramp is a
        // decision the wind made and not one to be overridden mid-ring.
        volumeSettings: VolumeSettings.fixed(
          volume: volume?.clamp(0.0, 1.0),
          volumeEnforced: volume != null,
        ),
        notificationSettings: NotificationSettings(
          title: title,
          body: body,
          stopButton: 'Stop',
          // Android-only in the plugin; iOS ignores it and uses the app icon.
          icon: kNotificationIconRes,
          // Spelled out rather than left to the plugin's default, so a change
          // to that default cannot flip our behaviour silently.
          androidStopAlarmOnDismiss: false,
        ),
      );

  @override
  Future<void> cancel(int id) async {
    await ensureInitialized();
    await Alarm.stop(id);
  }

  @override
  Future<Set<int>> scheduledIds() async => (await scheduledAlarms()).keys.toSet();

  @override
  Future<bool> isRinging(int id) async {
    await ensureInitialized();
    return Alarm.isRinging(id);
  }

  /// True — Android reports host moves and drops on `Alarm.events` from
  /// `alarm 5.10.0`, so a ring that vanished with nothing said about it is a
  /// genuine anomaly here and Nivaat may treat it as one.
  @override
  bool get reportsHostEvents => true;

  @override
  Future<void> applyHostAlarmEvents() => _bridge.apply();

  /// One `Alarm.getAlarms()` for the whole set.
  ///
  /// Not an optimisation detail: the plugin's `Alarm.getAlarm(id)` is a linear
  /// scan over `getAlarms()`, so asking per id repeated the same platform round
  /// trip for every alarm in the window (and logged a plugin warning on each
  /// miss). Arunoday's resync alone asked twenty-odd times.
  ///
  /// `Alarm.init()` drains the native pending events into `Alarm.events`, so
  /// the app's handlers are awaited first — no caller may treat this snapshot
  /// as authoritative while a drop for one of these ids is still unapplied.
  @override
  Future<Map<int, ScheduledAlarmInfo>> scheduledAlarms() async {
    await ensureInitialized();
    await applyHostAlarmEvents();
    final alarms = await Alarm.getAlarms();
    return {
      for (final a in alarms)
        a.id: ScheduledAlarmInfo(id: a.id, dateTime: a.dateTime),
    };
  }

  @override
  void setHostAlarmEventHandler(
    Future<void> Function(HostAlarmEvent event)? handler,
  ) {
    _bridge.setHandler(handler);
  }
}

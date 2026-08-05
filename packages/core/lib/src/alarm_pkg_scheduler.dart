import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_exception.dart';
import 'package:flutter/foundation.dart';

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
  }) : _soundAssetForVolume = soundAssetForVolume;

  /// Resolves the sound at schedule time (user-selectable tone). Receives the
  /// ring volume for parity with AlarmKit's loudness-variant mapping; this
  /// scheduler applies real volume instead, so it is PRIVATE and reachable
  /// only through [ringAsset] — passing a ring volume here is the bug that
  /// getter exists to prevent.
  final String Function(double volume) _soundAssetForVolume;

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
    await Alarm.init();
    _initialized = true;
  }

  /// Arms the ring, and reports whether the plugin took it.
  ///
  /// **Read `true` as "accepted", not "armed".** `Alarm.set` returns the
  /// native result, and on Android that result is `true` even when the
  /// platform scheduling failed — the plugin drops the failure and replies
  /// success (upstream issue #420, ours). So this closes the half we own (an
  /// `AlarmException`, which used to abort the whole cascade pass on its way
  /// out) and cannot close the other; see REVIEW #2 for why no signal
  /// available to Dart can.
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
  /// **`androidStopAlarmOnDismiss` is deliberately left at the plugin's `true`**
  /// (2026-08-05, after device testing), even though the opt-out is ours
  /// (issue #413 / PR #414, shipped in 5.8.0). A swipe therefore stops the
  /// alarm. The fear behind #413 — brushing the shade at 6am and silently
  /// losing your alarm — turns out not to be reachable: the notification is
  /// `setOngoing(true)`, and ongoing notifications are **not dismissible while
  /// the phone is locked** (Android 14 behaviour changes), which is the state a
  /// phone is in at 6am. What is left is a swipe on an unlocked phone, by
  /// someone awake and holding it, where "stop" is a fair reading.
  ///
  /// Turning it off is worse, and that was measured, not guessed: the swipe
  /// then does *nothing visible* and the alarm plays on with no Stop control
  /// anywhere. Restoring the notification cannot be done app-side either —
  /// `AlarmPlugin.alarmTriggerApi` is null with no engine attached, so with the
  /// app closed Dart is never told the alarm is ringing at all.
  ///
  /// **So `true` here is INTERIM, not a preference.** Asked upstream as issue
  /// #421, which would make the opt-out *restore* the notification rather than
  /// ignore the swipe. **When a release contains that, set this to `false`**
  /// (or to `restore`, if it ships as a third state) and flip
  /// `scheduler_test` with it: the swipe then costs neither the alarm nor the
  /// Stop button, which is better than either answer available today. If it is
  /// rejected, `true` is the permanent answer and this paragraph should say
  /// that instead. See CLAUDE.md's *Upstream* section.
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
          // Spelled out rather than left to the plugin's default, so the
          // decision above is visible in the code and a change to that default
          // cannot flip our behaviour silently.
          androidStopAlarmOnDismiss: true,
        ),
      );

  @override
  Future<void> cancel(int id) async {
    await ensureInitialized();
    await Alarm.stop(id);
  }

  @override
  Future<Set<int>> scheduledIds() async {
    await ensureInitialized();
    final alarms = await Alarm.getAlarms();
    return alarms.map((a) => a.id).toSet();
  }

  @override
  Future<bool> isRinging(int id) async {
    await ensureInitialized();
    return Alarm.isRinging(id);
  }
}

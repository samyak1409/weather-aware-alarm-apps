import 'package:alarm/alarm.dart';

import 'scheduler.dart';

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

  @override
  Future<void> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double volume,
  }) async {
    await ensureInitialized();
    await Alarm.set(
      alarmSettings: AlarmSettings(
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
        volumeSettings: VolumeSettings.fixed(
          volume: volume.clamp(0.0, 1.0),
          volumeEnforced: true,
        ),
        notificationSettings: NotificationSettings(
          title: title,
          body: body,
          stopButton: 'Stop',
        ),
      ),
    );
  }

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

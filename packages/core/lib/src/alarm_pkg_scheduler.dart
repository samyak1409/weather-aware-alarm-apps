import 'package:alarm/alarm.dart';

import 'scheduler.dart';

/// [AlarmScheduler] backed by the `alarm` pub package — **Android only**. On
/// iOS `createAlarmScheduler` always picks `AlarmKitScheduler` and there is no
/// `alarm`-package fallback (a denied AlarmKit no-ops + nudges to Settings),
/// so this never runs on iOS.
class AlarmPkgScheduler implements AlarmScheduler {
  AlarmPkgScheduler({required this.soundAssetForVolume});

  /// Resolves the sound at schedule time (user-selectable tone). Receives
  /// the ring volume for parity with AlarmKit's loudness-variant mapping;
  /// this scheduler applies real volume, so most callers ignore it.
  final String Function(double volume) soundAssetForVolume;

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
        assetAudioPath: soundAssetForVolume(volume),
        loopAudio: true,
        vibrate: true,
        androidFullScreenIntent: true,
        // Android-only path: the ring is a foreground service + AlarmManager
        // alarm that genuinely survives the app being swiped/killed, so the
        // package's "may not ring" warning would be a false alarm here. Off.
        // (The iOS unreliability that warning is for no longer applies — iOS
        // uses AlarmKit, never this scheduler.)
        warningNotificationOnKill: false,
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

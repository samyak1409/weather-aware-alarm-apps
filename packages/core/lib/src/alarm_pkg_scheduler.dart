import 'package:alarm/alarm.dart';

import 'scheduler.dart';

/// v1 [AlarmScheduler] backed by the `alarm` pub package (both platforms).
/// v1.1 swaps the iOS path to flutter_alarmkit behind this same interface.
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

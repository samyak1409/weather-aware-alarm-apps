import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_alarmkit/flutter_alarmkit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alarm_pkg_scheduler.dart';
import 'scheduler.dart';

/// [AlarmScheduler] backed by Apple AlarmKit (iOS 26+): system-rung alarms
/// that break through Silent mode and Focus, show full-screen, and survive
/// app termination and reboot.
///
/// AlarmKit has no per-alarm volume; [soundAssetForVolume] maps the engine's
/// volume (Nivaat's wind ramp) to a pre-rendered loudness variant. AlarmKit
/// also assigns its own UUIDs, so an int-id -> UUID map is persisted.
class AlarmKitScheduler implements AlarmScheduler {
  AlarmKitScheduler({
    required this.soundAssetForVolume,
    required this.tintColor,
  });

  /// e.g. volume 0.85 -> 'assets/sounds/nivaat_ring_85.wav'. Unlike
  /// `AlarmPkgScheduler`, this one really does need the volume: AlarmKit has
  /// no volume knob, so the ramp can only arrive baked into the file.
  final String Function(double volume) soundAssetForVolume;

  /// '#RRGGBB' accent used on the system alarm UI.
  final String tintColor;

  final FlutterAlarmkit _ak = FlutterAlarmkit();
  static const String _mapKey = 'alarmkit.idmap';
  bool _authRequested = false;

  @override
  Future<void> ensureInitialized() async {
    if (_authRequested) return;
    final state = await _ak.getAuthorizationState();
    if (state == AlarmAuthorizationState.notDetermined) {
      await _ak.requestAuthorization();
    }
    _authRequested = true;
  }

  /// Reads the id->UUID map from DISK, not from this isolate's cache.
  ///
  /// Without the reload a background isolate never sees what the UI isolate
  /// wrote, so its read-modify-write saves the other side's entries away
  /// (REVIEW #7). This narrows that to the gap between reload and save — there
  /// is still no cross-isolate lock, and SharedPreferences offers none — which
  /// is also why [scheduledIds] only writes when something actually changed.
  Future<Map<String, String>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_mapKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> _saveMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapKey, jsonEncode(map));
  }

  @override
  Future<bool> scheduleRing({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required double? volume,
  }) async {
    await ensureInitialized();
    // Replace semantics, same as the alarm package — but only once the old one
    // is REALLY gone. Scheduling over an un-cancelled alarm would leave two
    // live in AlarmKit and overwrite the only handle we have on the first, so
    // the leak `cancel` was fixed to prevent would just move here (REVIEW #6).
    //
    // Refusing instead leaves exactly one alarm, still mapped and therefore
    // still cancellable, and reports `false` so the caller does not record a
    // ring it did not get — the next ladder rung retries the whole thing.
    // Closing it properly (schedule the replacement FIRST, keep a set of
    // pending-cancel UUIDs beside the live one) needs the map to stop being
    // one UUID per id, which is REVIEW #5 + #6 landing together.
    if (!await _cancelResolved(id)) return false;
    final String uuid;
    try {
      uuid = await _ak.scheduleOneShotAlarm(
        timestamp: at.millisecondsSinceEpoch.toDouble(),
        label: title,
        tintColor: tintColor,
        // AlarmKit has no volume knob, so loudness can only arrive baked into
        // the file — and a null volume means "no opinion", which is the
        // unattenuated master. iOS then plays it at the system alarm volume,
        // which is exactly what an app with no opinion should get.
        soundPath: soundAssetForVolume(volume ?? 1),
      );
    } on PlatformException {
      // AlarmKit denied or unavailable. By design there is NO `alarm`-package
      // fallback on iOS (2026-07-18 decision) — instead [alarmSchedulingDenied]
      // drives the permission banner to send the user to Settings. A failed
      // schedule must never crash the engine/controller, but it must not pass
      // for a success either: this used to `return` into a caller that then
      // recorded the alarm as armed, and Nivaat logged `Rang` for a morning
      // that never made a sound (REVIEW #2).
      return false;
    }
    final map = await _loadMap();
    map['$id'] = uuid;
    await _saveMap(map);
    return true;
  }

  /// Cancels the alarm, and **keeps the mapping unless it really went**.
  ///
  /// `cancelAlarm` reports failure two ways — a `false` return and a throw —
  /// and this used to drop the id->UUID entry before either was consulted. An
  /// alarm that refuses cancellation then becomes unreachable for good: its
  /// UUID is the only handle we have, and nothing can name it again (REVIEW
  /// #6). Keeping the entry costs nothing, because a mapping AlarmKit no
  /// longer knows about is pruned by [scheduledIds] on the next sweep — so the
  /// failure mode is a retry, not a leak.
  @override
  Future<void> cancel(int id) => _cancelResolved(id);

  /// Cancels, and reports whether the alarm is definitely gone.
  ///
  /// `true` also covers "there was nothing mapped" — nothing to lose is the
  /// same as nothing left.
  Future<bool> _cancelResolved(int id) async {
    final map = await _loadMap();
    final uuid = map['$id'];
    if (uuid == null) return true;
    bool cancelled;
    try {
      cancelled = await _ak.cancelAlarm(alarmId: uuid);
    } on PlatformException {
      // Includes "already gone" (fired, or the user removed it), which is
      // indistinguishable here from a real error — so treat it as unresolved
      // and let the sweep decide, rather than guessing in the direction that
      // loses the handle.
      cancelled = false;
    }
    if (!cancelled) return false;
    map.remove('$id');
    await _saveMap(map);
    return true;
  }

  /// The int ids AlarmKit still holds something for.
  ///
  /// **Prunes only what AlarmKit no longer knows AT ALL.** Keeping just
  /// `AlarmState.scheduled` dropped the UUID of an *alerting* alarm — the one
  /// sounding right now — and with the mapping gone [isRinging] went blind and
  /// [cancel] could no longer reach the system alert (REVIEW #4). Every other
  /// state is still an alarm we own: `countdown`, `paused`, `alerting`, and
  /// `unknown`, which is what a state name added by a future iOS arrives as —
  /// treating that as "gone" would wipe the whole map on the first resync.
  ///
  /// Nivaat's orphan sweep calls this on every pass, so the pruning had to
  /// stop being destructive before that could be safe.
  @override
  Future<Set<int>> scheduledIds() async {
    final map = await _loadMap();
    final Set<String> known;
    try {
      known = {for (final a in await _ak.getAlarms()) a.id};
    } on PlatformException {
      return {};
    }
    final before = map.length;
    map.removeWhere((_, uuid) => !known.contains(uuid));
    // Only write when something actually went. This map is a read-modify-write
    // blob with no cross-isolate lock (REVIEW #7), so every needless save is
    // another chance for two isolates to overwrite each other.
    if (map.length != before) await _saveMap(map);
    return map.keys.map(int.parse).toSet();
  }

  @override
  Future<bool> isRinging(int id) async {
    final map = await _loadMap();
    final uuid = map['$id'];
    if (uuid == null) return false;
    try {
      final alarms = await _ak.getAlarms();
      for (final a in alarms) {
        if (a.id == uuid && a.state == AlarmState.alerting) return true;
      }
    } on PlatformException {
      // fall through
    }
    return false;
  }
}

/// Picks the scheduler for the platform: **AlarmKit on iOS** (min target 26,
/// so always present), the `alarm` package on Android. iOS has **no**
/// `alarm`-package fallback (2026-07-18): if the user denies AlarmKit,
/// scheduling silently no-ops and [alarmSchedulingDenied] lets the UI nudge
/// them to Settings — we never ship the `alarm` package's unreliable
/// Timer-based iOS ring.
Future<AlarmScheduler> createAlarmScheduler({
  required String Function(double volume) soundAssetForVolume,
  required String tintColor,
}) async {
  if (Platform.isIOS) {
    return AlarmKitScheduler(
      soundAssetForVolume: soundAssetForVolume,
      tintColor: tintColor,
    );
  }
  return AlarmPkgScheduler(soundAssetForVolume: soundAssetForVolume);
}

/// True only when the user has **denied** AlarmKit on iOS — the signal for
/// [AlarmPermissionBanner]. Android, and any non-denied iOS state
/// (authorized / not-yet-asked), → false.
Future<bool> alarmSchedulingDenied() async {
  if (!Platform.isIOS) return false;
  try {
    final state = await FlutterAlarmkit().getAuthorizationState();
    return state == AlarmAuthorizationState.denied;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

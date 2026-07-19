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

  /// e.g. volume 0.9 -> 'assets/sounds/nivaat_ring_90.wav'
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

  Future<Map<String, String>> _loadMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_mapKey);
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
  }

  Future<void> _saveMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapKey, jsonEncode(map));
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
    await cancel(id); // replace semantics, same as the alarm package
    final String uuid;
    try {
      uuid = await _ak.scheduleOneShotAlarm(
        timestamp: at.millisecondsSinceEpoch.toDouble(),
        label: title,
        tintColor: tintColor,
        soundPath: soundAssetForVolume(volume),
      );
    } on PlatformException {
      // AlarmKit denied or unavailable. By design there is NO `alarm`-package
      // fallback on iOS (2026-07-18 decision) — instead [alarmSchedulingDenied]
      // drives the permission banner to send the user to Settings. A failed
      // schedule must never crash the engine/controller.
      return;
    }
    final map = await _loadMap();
    map['$id'] = uuid;
    await _saveMap(map);
  }

  @override
  Future<void> cancel(int id) async {
    final map = await _loadMap();
    final uuid = map.remove('$id');
    if (uuid != null) {
      try {
        await _ak.cancelAlarm(alarmId: uuid);
      } on PlatformException {
        // Already gone (fired or user-removed) — map cleanup is enough.
      }
      await _saveMap(map);
    }
  }

  @override
  Future<Set<int>> scheduledIds() async {
    final map = await _loadMap();
    final live = <String>{};
    try {
      for (final a in await _ak.getAlarms()) {
        if (a.state == AlarmState.scheduled) live.add(a.id);
      }
    } on PlatformException {
      return {};
    }
    map.removeWhere((_, uuid) => !live.contains(uuid));
    await _saveMap(map);
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

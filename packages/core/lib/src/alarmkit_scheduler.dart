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

  /// e.g. volume 0.6 -> 'assets/sounds/nivaat_ring_60.wav'
  final String Function(double volume) soundAssetForVolume;

  /// '#RRGGBB' accent used on the system alarm UI.
  final String tintColor;

  final FlutterAlarmkit _ak = FlutterAlarmkit();
  static const String _mapKey = 'alarmkit.idmap';
  bool _authRequested = false;

  /// True when AlarmKit is present and not denied (iOS 26+). On older iOS
  /// the plugin throws — callers fall back to [AlarmPkgScheduler].
  static Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      final state = await FlutterAlarmkit().getAuthorizationState();
      return state != AlarmAuthorizationState.denied;
    } on PlatformException {
      return false; // iOS < 26
    } on MissingPluginException {
      return false;
    }
  }

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
    final uuid = await _ak.scheduleOneShotAlarm(
      timestamp: at.millisecondsSinceEpoch.toDouble(),
      label: title,
      tintColor: tintColor,
      soundPath: soundAssetForVolume(volume),
    );
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

/// Picks the best scheduler for the platform: AlarmKit on iOS 26+,
/// otherwise the `alarm` package (Android, older iOS, or AlarmKit denied).
Future<AlarmScheduler> createAlarmScheduler({
  required String Function(double volume) soundAssetForVolume,
  required String tintColor,
}) async {
  if (await AlarmKitScheduler.isSupported()) {
    return AlarmKitScheduler(
      soundAssetForVolume: soundAssetForVolume,
      tintColor: tintColor,
    );
  }
  return AlarmPkgScheduler(soundAsset: soundAssetForVolume(1.0));
}

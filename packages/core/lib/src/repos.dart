import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// SharedPreferences-backed stores. Everything is small JSON blobs; both
/// apps are single-user, low-write. Background isolates re-read from disk.

class ArunodayStore {
  static const _key = 'arunoday.settings';

  Future<ArunodaySettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const ArunodaySettings();
    return ArunodaySettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(ArunodaySettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(settings.toJson()));
  }
}

/// Per-alarm cascade state persisted between background wakeups.
class CheckState {
  const CheckState({
    required this.alarmId,
    required this.alarmAt,
    required this.hadSuccessfulCheck,
  });

  final int alarmId;
  final DateTime alarmAt;
  final bool hadSuccessfulCheck;

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'alarmAt': alarmAt.toIso8601String(),
        'hadSuccessfulCheck': hadSuccessfulCheck,
      };

  factory CheckState.fromJson(Map<String, dynamic> j) => CheckState(
        alarmId: j['alarmId'] as int,
        alarmAt: DateTime.parse(j['alarmAt'] as String),
        hadSuccessfulCheck: j['hadSuccessfulCheck'] as bool? ?? false,
      );
}

class NivaatStore {
  static const _courtsKey = 'nivaat.courts';
  static const _alarmsKey = 'nivaat.alarms';
  static const _historyKey = 'nivaat.history';
  static const _statePrefix = 'nivaat.checkstate.';
  static const _soundKey = 'nivaat.sound';
  static const _historyLimit = 60;

  /// Selected alarm tone path; null = default (Court Call).
  Future<String?> loadSoundPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_soundKey);
  }

  Future<void> saveSoundPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_soundKey);
    } else {
      await prefs.setString(_soundKey, path);
    }
  }

  Future<List<SavedLocation>> loadCourts() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_courtsKey), SavedLocation.fromJson);
  }

  Future<void> saveCourts(List<SavedLocation> courts) =>
      _saveList(_courtsKey, courts.map((c) => c.toJson()));

  Future<List<NivaatAlarm>> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_alarmsKey), NivaatAlarm.fromJson);
  }

  Future<void> saveAlarms(List<NivaatAlarm> alarms) =>
      _saveList(_alarmsKey, alarms.map((a) => a.toJson()));

  Future<List<HistoryRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_historyKey), HistoryRecord.fromJson);
  }

  /// Prepends [record]; keeps the newest [_historyLimit] entries.
  Future<void> addHistory(HistoryRecord record) async {
    final all = await loadHistory();
    final trimmed = [record, ...all].take(_historyLimit);
    await _saveList(_historyKey, trimmed.map((r) => r.toJson()));
  }

  Future<CheckState?> loadCheckState(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_statePrefix$alarmId');
    if (raw == null) return null;
    return CheckState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCheckState(CheckState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_statePrefix${state.alarmId}',
      jsonEncode(state.toJson()),
    );
  }

  Future<void> clearCheckState(int alarmId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_statePrefix$alarmId');
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }

  static Future<void> _saveList(
    String key,
    Iterable<Map<String, dynamic>> items,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(items.toList()));
  }
}

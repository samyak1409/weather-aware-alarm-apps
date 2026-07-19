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
    this.ringScheduled = false,
    this.ringCourtSpeedKmh,
    this.ringRawGustKmh,
    this.ringVolume,
    this.extendedCheckShown = false,
    this.skipCourtSpeedKmh,
    this.skipRawGustKmh,
    this.skipGusty = false,
    this.lastCheckAt,
    this.lastAttemptAt,
  });

  final int alarmId;
  final DateTime alarmAt;

  /// When the last *successful* wind check ran (calm or skip-worthy; a failed
  /// fetch doesn't update it). Carried into a ring/windy/gusty history row's
  /// `checkedAt`, so it records the freshness of the reading it acted on —
  /// e.g. a 22:00 check behind a 06:00 ring.
  final DateTime? lastCheckAt;

  /// When the last check was *attempted*, success or failure. Used for a
  /// no-data skip's `checkedAt` ("last tried HH:MM"), since there was no
  /// successful reading to timestamp.
  final DateTime? lastAttemptAt;

  /// True once a ring has been committed (scheduled) for this occurrence. If
  /// the ring's time then passes without a live check overriding it, the ring
  /// fired — so it is recorded as "rang" rather than re-decided against newer
  /// wind (which would wrongly relabel a ring that already woke the user).
  final bool ringScheduled;

  /// The wind sample behind the committed ring, kept so a "rang" recorded
  /// after the fact still carries real numbers.
  final double? ringCourtSpeedKmh;
  final double? ringRawGustKmh;
  final double? ringVolume;

  /// True once the "extended check" heads-up card has been posted for this
  /// occurrence (at T), so the minute-by-minute retries don't re-post it.
  final bool extendedCheckShown;

  /// The last KNOWN skip reading — kept across no-data retries so the +30m
  /// card reports the real reason even if the cap check itself has no data.
  /// Null until a check actually reads a skip-worthy wind. [skipGusty]
  /// distinguishes gusty from windy (only meaningful when the speeds are set).
  final double? skipCourtSpeedKmh;
  final double? skipRawGustKmh;
  final bool skipGusty;

  CheckState copyWith({
    bool? ringScheduled,
    double? ringCourtSpeedKmh,
    double? ringRawGustKmh,
    double? ringVolume,
    bool? extendedCheckShown,
    double? skipCourtSpeedKmh,
    double? skipRawGustKmh,
    bool? skipGusty,
    DateTime? lastCheckAt,
    DateTime? lastAttemptAt,
  }) =>
      CheckState(
        alarmId: alarmId,
        alarmAt: alarmAt,
        ringScheduled: ringScheduled ?? this.ringScheduled,
        ringCourtSpeedKmh: ringCourtSpeedKmh ?? this.ringCourtSpeedKmh,
        ringRawGustKmh: ringRawGustKmh ?? this.ringRawGustKmh,
        ringVolume: ringVolume ?? this.ringVolume,
        extendedCheckShown: extendedCheckShown ?? this.extendedCheckShown,
        skipCourtSpeedKmh: skipCourtSpeedKmh ?? this.skipCourtSpeedKmh,
        skipRawGustKmh: skipRawGustKmh ?? this.skipRawGustKmh,
        skipGusty: skipGusty ?? this.skipGusty,
        lastCheckAt: lastCheckAt ?? this.lastCheckAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      );

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'alarmAt': alarmAt.toIso8601String(),
        'ringScheduled': ringScheduled,
        'ringCourtSpeedKmh': ringCourtSpeedKmh,
        'ringRawGustKmh': ringRawGustKmh,
        'ringVolume': ringVolume,
        'extendedCheckShown': extendedCheckShown,
        'skipCourtSpeedKmh': skipCourtSpeedKmh,
        'skipRawGustKmh': skipRawGustKmh,
        'skipGusty': skipGusty,
        'lastCheckAt': lastCheckAt?.toIso8601String(),
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
      };

  factory CheckState.fromJson(Map<String, dynamic> j) => CheckState(
        alarmId: j['alarmId'] as int,
        alarmAt: DateTime.parse(j['alarmAt'] as String),
        ringScheduled: j['ringScheduled'] as bool? ?? false,
        ringCourtSpeedKmh: (j['ringCourtSpeedKmh'] as num?)?.toDouble(),
        ringRawGustKmh: (j['ringRawGustKmh'] as num?)?.toDouble(),
        ringVolume: (j['ringVolume'] as num?)?.toDouble(),
        extendedCheckShown: j['extendedCheckShown'] as bool? ?? false,
        skipCourtSpeedKmh: (j['skipCourtSpeedKmh'] as num?)?.toDouble(),
        skipRawGustKmh: (j['skipRawGustKmh'] as num?)?.toDouble(),
        skipGusty: j['skipGusty'] as bool? ?? false,
        lastCheckAt: switch (j['lastCheckAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        lastAttemptAt: switch (j['lastAttemptAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
      );
}

class NivaatStore {
  static const _courtsKey = 'nivaat.courts';
  static const _alarmsKey = 'nivaat.alarms';
  static const _historyKey = 'nivaat.history';
  static const _statePrefix = 'nivaat.checkstate.';
  static const _soundKey = 'nivaat.sound';
  static const _historyLimit = 60;

  /// Re-reads the on-disk prefs into THIS isolate's cache. SharedPreferences
  /// caches per isolate, so history/check-state written by a background wind
  /// check stays invisible to the already-running app until a cold start —
  /// the foreground app must call this at the top of every resync. (Fresh
  /// background isolates read from disk anyway and don't need it.)
  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
  }

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

  /// Inserts [record], REPLACING any existing row for the same EVENT — same
  /// occurrence (alarmId + at) and same kind (heads-up snapshot vs final,
  /// told apart by `watchedUntil`). History is an append-only log (user
  /// decision 2026-07-20): the "still checking" row written at T and the
  /// final outcome row (cap skip, or a late ring) are separate entries that
  /// both stay — the replace half exists ONLY so a foreground/background
  /// double-write of the same event converges on one row instead of
  /// duplicating it. New events prepend (newest first). Keeps the newest
  /// [_historyLimit] entries.
  Future<void> upsertHistory(HistoryRecord record) async {
    final all = await loadHistory();
    final i = all.indexWhere((r) =>
        r.alarmId == record.alarmId &&
        r.at == record.at &&
        (r.watchedUntil != null) == (record.watchedUntil != null));
    final rows = [...all];
    if (i >= 0) {
      rows[i] = record;
    } else {
      rows.insert(0, record);
    }
    await _saveList(
        _historyKey, rows.take(_historyLimit).map((r) => r.toJson()));
  }

  /// Drops every history row for [courtId] — used when a court is deleted, so
  /// its whole skip/ring log goes with it. Keyed by court, so this reaches
  /// *every* row for the court, including those from alarms deleted earlier.
  Future<void> removeHistoryForCourt(String courtId) async {
    final kept =
        (await loadHistory()).where((r) => r.courtId != courtId);
    await _saveList(_historyKey, kept.map((r) => r.toJson()));
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

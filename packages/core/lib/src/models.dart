import 'wind.dart';

/// A saved named place (court or home). No GPS in v1 — locked decision.
class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'lat': lat, 'lon': lon};

  factory SavedLocation.fromJson(Map<String, dynamic> j) => SavedLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
      );
}

/// Arunoday settings: one active location, wake offset, optional bedtime
/// override, master toggles.
class ArunodaySettings {
  const ArunodaySettings({
    this.locations = const [],
    this.activeLocationId,
    this.wakeOffsetMinutes = 0,
    this.bedtimeOverrideMinutes,
    this.wakeEnabled = true,
    this.bedtimeEnabled = true,
  });

  final List<SavedLocation> locations;
  final String? activeLocationId;

  /// Signed offset applied to civil dawn (e.g. +120 = dawn + 2h).
  final int wakeOffsetMinutes;

  /// Minutes-after-midnight; null = auto (SleepPlan).
  final int? bedtimeOverrideMinutes;

  final bool wakeEnabled;
  final bool bedtimeEnabled;

  SavedLocation? get activeLocation {
    for (final l in locations) {
      if (l.id == activeLocationId) return l;
    }
    return locations.isEmpty ? null : locations.first;
  }

  ArunodaySettings copyWith({
    List<SavedLocation>? locations,
    String? activeLocationId,
    int? wakeOffsetMinutes,
    int? Function()? bedtimeOverrideMinutes,
    bool? wakeEnabled,
    bool? bedtimeEnabled,
  }) =>
      ArunodaySettings(
        locations: locations ?? this.locations,
        activeLocationId: activeLocationId ?? this.activeLocationId,
        wakeOffsetMinutes: wakeOffsetMinutes ?? this.wakeOffsetMinutes,
        bedtimeOverrideMinutes: bedtimeOverrideMinutes != null
            ? bedtimeOverrideMinutes()
            : this.bedtimeOverrideMinutes,
        wakeEnabled: wakeEnabled ?? this.wakeEnabled,
        bedtimeEnabled: bedtimeEnabled ?? this.bedtimeEnabled,
      );

  Map<String, dynamic> toJson() => {
        'locations': locations.map((l) => l.toJson()).toList(),
        'activeLocationId': activeLocationId,
        'wakeOffsetMinutes': wakeOffsetMinutes,
        'bedtimeOverrideMinutes': bedtimeOverrideMinutes,
        'wakeEnabled': wakeEnabled,
        'bedtimeEnabled': bedtimeEnabled,
      };

  factory ArunodaySettings.fromJson(Map<String, dynamic> j) =>
      ArunodaySettings(
        locations: (j['locations'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SavedLocation.fromJson)
            .toList(),
        activeLocationId: j['activeLocationId'] as String?,
        wakeOffsetMinutes: j['wakeOffsetMinutes'] as int? ?? 0,
        bedtimeOverrideMinutes: j['bedtimeOverrideMinutes'] as int?,
        wakeEnabled: j['wakeEnabled'] as bool? ?? true,
        bedtimeEnabled: j['bedtimeEnabled'] as bool? ?? true,
      );
}

/// One Nivaat alarm: a time, a court, a wind threshold.
class NivaatAlarm {
  const NivaatAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.courtId,
    this.courtSpeedLimitKmh = WindThresholds.defaultLimit,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.enabled = true,
  });

  /// Small positive int; also used to derive scheduler ids.
  final int id;
  final int hour;
  final int minute;
  final String courtId;
  final int courtSpeedLimitKmh;

  /// DateTime.weekday values (1 = Mon .. 7 = Sun).
  final Set<int> weekdays;
  final bool enabled;

  WindThresholds get thresholds =>
      WindThresholds(courtSpeedLimitKmh: courtSpeedLimitKmh);

  /// Next occurrence strictly after [now].
  DateTime? nextOccurrence(DateTime now) {
    if (weekdays.isEmpty) return null;
    for (var d = 0; d <= 7; d++) {
      final day = now.add(Duration(days: d));
      final at = DateTime(day.year, day.month, day.day, hour, minute);
      if (at.isAfter(now) && weekdays.contains(at.weekday)) return at;
    }
    return null;
  }

  NivaatAlarm copyWith({
    int? hour,
    int? minute,
    String? courtId,
    int? courtSpeedLimitKmh,
    Set<int>? weekdays,
    bool? enabled,
  }) =>
      NivaatAlarm(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        courtId: courtId ?? this.courtId,
        courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'courtId': courtId,
        'courtSpeedLimitKmh': courtSpeedLimitKmh,
        'weekdays': weekdays.toList(),
        'enabled': enabled,
      };

  factory NivaatAlarm.fromJson(Map<String, dynamic> j) => NivaatAlarm(
        id: j['id'] as int,
        hour: j['hour'] as int,
        minute: j['minute'] as int,
        courtId: j['courtId'] as String,
        courtSpeedLimitKmh:
            j['courtSpeedLimitKmh'] as int? ?? WindThresholds.defaultLimit,
        weekdays: (j['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
            .cast<int>()
            .toSet(),
        enabled: j['enabled'] as bool? ?? true,
      );
}

enum CheckOutcome { rang, skippedWindy, skippedGusty, skippedNoData }

/// One line of Nivaat history: what happened and why. The trust mechanism —
/// a skipped alarm must always be explainable.
class HistoryRecord {
  const HistoryRecord({
    required this.alarmId,
    required this.at,
    required this.outcome,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.volume,
  });

  final int alarmId;
  final DateTime at;
  final CheckOutcome outcome;
  final double? courtSpeedKmh;
  final double? rawGustKmh;
  final double? volume;

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'at': at.toIso8601String(),
        'outcome': outcome.name,
        'courtSpeedKmh': courtSpeedKmh,
        'rawGustKmh': rawGustKmh,
        'volume': volume,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> j) => HistoryRecord(
        alarmId: j['alarmId'] as int,
        at: DateTime.parse(j['at'] as String),
        outcome: CheckOutcome.values.byName(j['outcome'] as String),
        courtSpeedKmh: (j['courtSpeedKmh'] as num?)?.toDouble(),
        rawGustKmh: (j['rawGustKmh'] as num?)?.toDouble(),
        volume: (j['volume'] as num?)?.toDouble(),
      );
}

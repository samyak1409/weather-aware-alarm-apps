import 'format.dart';
import 'wind.dart';

/// A saved named place (court or home). Stored as fixed lat/lon — no continuous
/// GPS tracking (auto-location is the rejected feature); "add current location"
/// uses a one-shot GPS fix, see location_picker.
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
    this.bedtimeOffsetMinutes,
    this.wakeEnabled = true,
    this.bedtimeEnabled = true,
    this.oneTimeExtraMinutes = 0,
    this.oneTimeExtraDate,
    this.bedtimeDelayedUntil,
    this.soundPath,
  });

  final List<SavedLocation> locations;
  final String? activeLocationId;

  /// Signed offset applied to civil dawn (e.g. +120 = dawn + 2h).
  final int wakeOffsetMinutes;

  /// Signed offset from the auto bedtime (SleepPlan), in minutes; null = auto.
  /// Stored as an offset (not an absolute time) so it stays consistent when
  /// the active location — and thus the auto bedtime — changes.
  final int? bedtimeOffsetMinutes;

  final bool wakeEnabled;
  final bool bedtimeEnabled;

  /// One-time extra wake offset ("tomorrow +2h" from the bedtime ritual),
  /// applied only to the wake whose calendar date equals [oneTimeExtraDate]
  /// (ISO yyyy-mm-dd); auto-cleared once that wake has passed.
  final int oneTimeExtraMinutes;
  final String? oneTimeExtraDate;

  /// A "not sleepy yet" delayed bedtime reminder; cleared once it fires.
  final DateTime? bedtimeDelayedUntil;

  /// Selected alarm tone (asset or absolute device path); null = app default.
  final String? soundPath;

  SavedLocation? get activeLocation {
    for (final l in locations) {
      if (l.id == activeLocationId) return l;
    }
    return locations.isEmpty ? null : locations.first;
  }

  ArunodaySettings copyWith({
    List<SavedLocation>? locations,
    String? Function()? activeLocationId,
    int? wakeOffsetMinutes,
    int? Function()? bedtimeOffsetMinutes,
    bool? wakeEnabled,
    bool? bedtimeEnabled,
    int? oneTimeExtraMinutes,
    String? Function()? oneTimeExtraDate,
    DateTime? Function()? bedtimeDelayedUntil,
    String? Function()? soundPath,
  }) =>
      ArunodaySettings(
        locations: locations ?? this.locations,
        activeLocationId: activeLocationId != null
            ? activeLocationId()
            : this.activeLocationId,
        wakeOffsetMinutes: wakeOffsetMinutes ?? this.wakeOffsetMinutes,
        bedtimeOffsetMinutes: bedtimeOffsetMinutes != null
            ? bedtimeOffsetMinutes()
            : this.bedtimeOffsetMinutes,
        wakeEnabled: wakeEnabled ?? this.wakeEnabled,
        bedtimeEnabled: bedtimeEnabled ?? this.bedtimeEnabled,
        oneTimeExtraMinutes: oneTimeExtraMinutes ?? this.oneTimeExtraMinutes,
        oneTimeExtraDate: oneTimeExtraDate != null
            ? oneTimeExtraDate()
            : this.oneTimeExtraDate,
        bedtimeDelayedUntil: bedtimeDelayedUntil != null
            ? bedtimeDelayedUntil()
            : this.bedtimeDelayedUntil,
        soundPath: soundPath != null ? soundPath() : this.soundPath,
      );

  Map<String, dynamic> toJson() => {
        'locations': locations.map((l) => l.toJson()).toList(),
        'activeLocationId': activeLocationId,
        'wakeOffsetMinutes': wakeOffsetMinutes,
        'bedtimeOffsetMinutes': bedtimeOffsetMinutes,
        'wakeEnabled': wakeEnabled,
        'bedtimeEnabled': bedtimeEnabled,
        'oneTimeExtraMinutes': oneTimeExtraMinutes,
        'oneTimeExtraDate': oneTimeExtraDate,
        'bedtimeDelayedUntil': bedtimeDelayedUntil?.toIso8601String(),
        'soundPath': soundPath,
      };

  factory ArunodaySettings.fromJson(Map<String, dynamic> j) =>
      ArunodaySettings(
        locations: (j['locations'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(SavedLocation.fromJson)
            .toList(),
        activeLocationId: j['activeLocationId'] as String?,
        wakeOffsetMinutes: j['wakeOffsetMinutes'] as int? ?? 0,
        bedtimeOffsetMinutes: j['bedtimeOffsetMinutes'] as int?,
        wakeEnabled: j['wakeEnabled'] as bool? ?? true,
        bedtimeEnabled: j['bedtimeEnabled'] as bool? ?? true,
        oneTimeExtraMinutes: j['oneTimeExtraMinutes'] as int? ?? 0,
        oneTimeExtraDate: j['oneTimeExtraDate'] as String?,
        bedtimeDelayedUntil: j['bedtimeDelayedUntil'] == null
            ? null
            : DateTime.parse(j['bedtimeDelayedUntil'] as String),
        soundPath: j['soundPath'] as String?,
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
        // Clamp into the offered range: alarms saved with the old 1-3 settings
        // (dropped 2026-07-14 with the gust floor) migrate up to the new minimum
        // instead of feeding the dropdown a value it no longer lists.
        courtSpeedLimitKmh:
            ((j['courtSpeedLimitKmh'] as int?) ?? WindThresholds.defaultLimit)
                .clamp(WindThresholds.minLimit, WindThresholds.maxLimit),
        weekdays: (j['weekdays'] as List? ?? const [1, 2, 3, 4, 5, 6, 7])
            .cast<int>()
            .toSet(),
        enabled: j['enabled'] as bool? ?? true,
      );
}

enum CheckOutcome { rang, skippedWindy, skippedGusty, skippedNoData }

/// One line of Nivaat history: what happened and why. The trust mechanism —
/// a skipped alarm must always be explainable. History is an append-only log
/// of events, like the notifications (user decision 2026-07-20): the
/// "still checking" moment at T and the final outcome are SEPARATE rows that
/// both stay forever — nothing is overwritten.
class HistoryRecord {
  const HistoryRecord({
    required this.alarmId,
    required this.courtId,
    required this.at,
    required this.outcome,
    this.checkedAt,
    this.watchedUntil,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.courtSpeedLimitKmh,
    this.rawGustLimitKmh,
    this.volume,
  });

  final int alarmId;

  /// The court this check was for. History is grouped and deleted by court
  /// (independently of whether the alarm still exists), so this is the durable
  /// link — [alarmId] can be reused or deleted, [courtId] stays put.
  final String courtId;

  /// The alarm's scheduled time (which alarm this row is about).
  final DateTime at;
  final CheckOutcome outcome;

  /// When the wind check that drove this outcome actually ran — the freshness
  /// of the reading behind the ring/skip. May be well *before* [at] (e.g. an
  /// alarm set at 22:00 whose only check was then, ringing at 06:00 on that
  /// 22:00 reading). Null when no check ever succeeded (no-data) or on older
  /// rows → falls back to [at]. See [whenChecked].
  final DateTime? checkedAt;

  /// Set only on the provisional "still checking" row written at T (= the
  /// +30m retry cap it kept watching toward). Marks the row as the heads-up
  /// snapshot — its final counterpart (a late ring, or the cap's skip) is a
  /// separate later row. Null on every final row.
  final DateTime? watchedUntil;
  final double? courtSpeedKmh;
  final double? rawGustKmh;

  /// The thresholds in force at decision time, stored so an old entry still
  /// shows all four numbers (speed & gust, each vs its cap) even after the
  /// alarm's limit is edited or the alarm is deleted. Null only for the very
  /// first builds' rows or a no-data skip that carried no thresholds.
  final int? courtSpeedLimitKmh;
  final double? rawGustLimitKmh;
  final double? volume;

  /// The wind-check time, defaulting to [at] when unrecorded. For a no-data
  /// skip this is the last *attempt* (there was no successful reading); for
  /// every other outcome it's the last successful check. Always surfaced (even
  /// when equal to [at]) as reinforcement that the result came from a real
  /// check — the UI labels it "checked" or, for no-data, "last tried".
  DateTime get whenChecked => checkedAt ?? at;

  /// All four numbers for this outcome: "wind 3 (≤4) · gusts 16 (≤15) km/h".
  /// Falls back to a reduced "wind 3 · gusts 16 km/h" for older rows saved
  /// before limits were stored, and '' for a no-data skip (nothing measured).
  String get windGustSummary {
    final court = courtSpeedKmh, gust = rawGustKmh;
    if (court == null || gust == null) return '';
    final courtLimit = courtSpeedLimitKmh, gustLimit = rawGustLimitKmh;
    if (courtLimit == null || gustLimit == null) {
      return 'wind ${court.round()} · gusts ${gust.round()} km/h';
    }
    return fmtWindGust(court, courtLimit, gust, gustLimit);
  }

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'courtId': courtId,
        'at': at.toIso8601String(),
        'outcome': outcome.name,
        'checkedAt': checkedAt?.toIso8601String(),
        'watchedUntil': watchedUntil?.toIso8601String(),
        'courtSpeedKmh': courtSpeedKmh,
        'rawGustKmh': rawGustKmh,
        'courtSpeedLimitKmh': courtSpeedLimitKmh,
        'rawGustLimitKmh': rawGustLimitKmh,
        'volume': volume,
      };

  factory HistoryRecord.fromJson(Map<String, dynamic> j) => HistoryRecord(
        alarmId: j['alarmId'] as int,
        courtId: j['courtId'] as String? ?? '',
        at: DateTime.parse(j['at'] as String),
        outcome: CheckOutcome.values.byName(j['outcome'] as String),
        checkedAt: switch (j['checkedAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        watchedUntil: switch (j['watchedUntil']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        courtSpeedKmh: (j['courtSpeedKmh'] as num?)?.toDouble(),
        rawGustKmh: (j['rawGustKmh'] as num?)?.toDouble(),
        courtSpeedLimitKmh: j['courtSpeedLimitKmh'] as int?,
        rawGustLimitKmh: (j['rawGustLimitKmh'] as num?)?.toDouble(),
        volume: (j['volume'] as num?)?.toDouble(),
      );
}

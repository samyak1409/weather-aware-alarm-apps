import 'calendar.dart';
import 'format.dart';
import 'wind.dart';

/// Which of the two ways of adding a place produced this one (X5).
///
/// Stored as the FACT, never as the sentence it renders — [savedLocationDetail]
/// builds that. A place saved today has to keep answering correctly after the
/// wording changes, which a stored display string cannot do.
enum PlaceSource {
  /// Picked from the Open-Meteo geocoder, so it carries that result's own
  /// region line ("Rajasthan, India").
  search,

  /// A one-shot GPS fix the user named themselves — there is no region to
  /// quote, only where the coordinates came from.
  gps,
}

/// A saved named place (court or home). Stored as fixed lat/lon — no continuous
/// GPS tracking (auto-location is the rejected feature); "add current location"
/// uses a one-shot GPS fix, see location_picker.
class SavedLocation {
  const SavedLocation({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    this.source = PlaceSource.search,
    this.region,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;

  /// How this place was added — what its ⓘ can honestly say.
  final PlaceSource source;

  /// The geocoder's own sub-line for a [PlaceSource.search] place
  /// (`Rajasthan, India`), or null. Always null for a GPS fix: the picker's
  /// `GeoPlace.region` there is a coordinate stand-in for the row it never
  /// renders, and storing it would put a second copy of the numbers behind an
  /// ⓘ whose whole job is to say something the row does not.
  final String? region;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lon': lon,
        'source': source.name,
        'region': region,
      };

  /// **No defaults for keys this app always writes** (CLAUDE.md's no-migration
  /// policy): a blob from a build before `source` existed throws here rather
  /// than being quietly reinterpreted as a searched place. `region` is read
  /// as nullable because null is a value this build really writes, not an
  /// absent key being papered over.
  factory SavedLocation.fromJson(Map<String, dynamic> j) => SavedLocation(
        id: j['id'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        source: PlaceSource.values.byName(j['source'] as String),
        region: j['region'] as String?,
      );
}

/// What the ⓘ beside a saved place says (X5) — **only the part the row does
/// not already show**.
///
/// The row is the name, so the ⓘ is the rest of the geocoder's line and
/// nothing else: `Rajasthan, India` under a place called Jaipur, never
/// `Jaipur, Rajasthan, India` (Samyak, 2026-08-15). Repeating the name spends
/// the front of a two-second pill on the one word already an inch above it.
///
/// A pure builder rather than a line inside the row, for the reason this repo
/// keeps relearning: a string built inside a `build()` is a string no test can
/// name. Both apps render it, so it lives here.
///
/// **A GPS fix has no region and needs none.** [SavedLocation.source] is read
/// first, so it answers `Saved using GPS` and never looks at the region at all
/// — the null it carries there says nothing about what the ⓘ shows.
///
/// **A SEARCHED place with no region says nothing, and that is the right
/// answer** rather than a fallback standing in for one. Two spellings, one
/// meaning: `''` when Open-Meteo answered with neither `admin1` nor `country`,
/// and null for a place built without one — which is every fixture that omits
/// it, so this is the branch that actually runs. The ⓘ then shows an empty
/// pill, and that is the accepted residual.
///
/// An earlier draft returned the coordinates there and called the case
/// unreachable in the same breath (Samyak, 2026-08-15). The coordinates went —
/// they invented detail the row already carries in Nivaat — but the
/// "unreachable" claim was wrong twice over and is gone too: the branch is
/// exercised by every fixture that omits a region, and a doc that asserts
/// unreachability for something a test then pins is the 2026-07-31 rule
/// running backwards.
String savedLocationDetail(SavedLocation place) =>
    place.source == PlaceSource.gps ? 'Saved using GPS' : place.region ?? '';

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
    this.bedtimeDelayCall = 0,
    this.bedtimeDelayFromMinute,
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

  /// A "sleep late" delayed bedtime reminder; cleared once it fires.
  final DateTime? bedtimeDelayedUntil;

  /// Which call the pending [bedtimeDelayedUntil] re-ring is — 2 for the
  /// first push (the bedtime alarm itself was the first call), 3 for the next,
  /// and so on. 0 when nothing is pending.
  ///
  /// A number rather than a wording, because `+1h` can be taken again on every
  /// re-ring: the body that says "Second call" for the fourth one is simply
  /// wrong (2026-08-13). It is not cleared when the re-ring fires — the ring
  /// screen's next `+1h` reads it to know it is the one after this.
  final int bedtimeDelayCall;

  /// The daily bedtime's minute-of-day that the pending push chain is measured
  /// against — null when nothing is pending.
  ///
  /// It exists so "did the bedtime move?" can be **asked** rather than guessed
  /// from where the re-ring sits on the clock face
  /// (`ArunodayController._clearOvertakenReRing`). Guessing was wrong past
  /// twelve pushes: by then the re-ring is more than twelve hours from its
  /// bedtime, so the shorter way round says "after" and an untouched bedtime
  /// read as a moved one.
  final int? bedtimeDelayFromMinute;

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
    int? bedtimeDelayCall,
    int? Function()? bedtimeDelayFromMinute,
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
        bedtimeDelayCall: bedtimeDelayCall ?? this.bedtimeDelayCall,
        bedtimeDelayFromMinute: bedtimeDelayFromMinute != null
            ? bedtimeDelayFromMinute()
            : this.bedtimeDelayFromMinute,
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
        'bedtimeDelayCall': bedtimeDelayCall,
        'bedtimeDelayFromMinute': bedtimeDelayFromMinute,
        'soundPath': soundPath,
      };

  factory ArunodaySettings.fromJson(Map<String, dynamic> j) =>
      ArunodaySettings(
        locations: (j['locations'] as List)
            .cast<Map<String, dynamic>>()
            .map(SavedLocation.fromJson)
            .toList(),
        activeLocationId: j['activeLocationId'] as String?,
        wakeOffsetMinutes: j['wakeOffsetMinutes'] as int,
        bedtimeOffsetMinutes: j['bedtimeOffsetMinutes'] as int?,
        wakeEnabled: j['wakeEnabled'] as bool,
        bedtimeEnabled: j['bedtimeEnabled'] as bool,
        oneTimeExtraMinutes: j['oneTimeExtraMinutes'] as int,
        oneTimeExtraDate: j['oneTimeExtraDate'] as String?,
        bedtimeDelayedUntil: j['bedtimeDelayedUntil'] == null
            ? null
            : DateTime.parse(j['bedtimeDelayedUntil'] as String),
        bedtimeDelayCall: j['bedtimeDelayCall'] as int,
        bedtimeDelayFromMinute: j['bedtimeDelayFromMinute'] as int?,
        soundPath: j['soundPath'] as String?,
      );
}

/// One Nivaat alarm: a time, a court, a wind threshold, a retry window.
class NivaatAlarm {
  const NivaatAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.courtId,
    this.courtSpeedLimitKmh = WindThresholds.defaultLimit,
    this.retryMinutesAfter = CheckCascade.retryCapMinutesAfter,
    this.weekdays = const {1, 2, 3, 4, 5, 6, 7},
    this.enabled = true,
  });

  /// Small positive int; also used to derive scheduler ids.
  final int id;
  final int hour;
  final int minute;
  final String courtId;
  final int courtSpeedLimitKmh;

  /// How long after T to keep re-checking a skip (30 / 60, or a dev-gated 1).
  /// Stored per alarm; drives `watchedUntil`, the heads-up deadline, and the
  /// cascade cap.
  final int retryMinutesAfter;

  /// DateTime.weekday values (1 = Mon .. 7 = Sun).
  final Set<int> weekdays;
  final bool enabled;

  WindThresholds get thresholds =>
      WindThresholds(courtSpeedLimitKmh: courtSpeedLimitKmh);

  /// Cap instant for an occurrence at [alarmAt] (T + [retryMinutesAfter]).
  DateTime retryCapAt(DateTime alarmAt) =>
      alarmAt.add(Duration(minutes: retryMinutesAfter));

  /// Next occurrence strictly after [now].
  ///
  /// Walks **calendar** days, not 24-hour blocks (REVIEW #10). `now.add(days)`
  /// visited the same date twice on a fall-back day, so eight steps covered
  /// seven dates and a once-a-week alarm could return null — and null is not
  /// "no alarm today": `_resolveOccurrence` handing it to `_evaluate` cancels
  /// that alarm's ring **and** its next check. Android checks only re-book
  /// themselves, so a lone alarm there then waits for you to open the app.
  DateTime? nextOccurrence(DateTime now) {
    if (weekdays.isEmpty) return null;
    for (var d = 0; d <= 7; d++) {
      final at = clockTimeOn(calendarDay(now, d), hour * 60 + minute);
      if (at.isAfter(now) && weekdays.contains(at.weekday)) return at;
    }
    return null;
  }

  NivaatAlarm copyWith({
    int? hour,
    int? minute,
    String? courtId,
    int? courtSpeedLimitKmh,
    int? retryMinutesAfter,
    Set<int>? weekdays,
    bool? enabled,
  }) =>
      NivaatAlarm(
        id: id,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        courtId: courtId ?? this.courtId,
        courtSpeedLimitKmh: courtSpeedLimitKmh ?? this.courtSpeedLimitKmh,
        retryMinutesAfter: retryMinutesAfter ?? this.retryMinutesAfter,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );

}

enum CheckOutcome { rang, skippedWindy, skippedGusty, skippedNoData }

/// How the ring itself resolved — a SEPARATE axis from what the wind was
/// doing, and never folded into [CheckOutcome].
///
/// `skippedNoData` is "we couldn't read the wind", which is a decision the app
/// made and can explain; a platform drop is the opposite — the app decided to
/// ring and the host overruled it. Reusing one for the other would put a wind
/// reason on a morning the wind had nothing to do with.
///
/// A premature post-T `Rang` is superseded in place by [missed] (a known
/// `AlarmDropped`) or [unknown] (ambiguous: the owed ring vanished with no
/// host event to explain it).
enum RingDisposition {
  /// Positive proof the ring was audible (or pending settled as rang).
  rang,

  /// Host dropped the alarm (known [AlarmDropped]).
  missed,

  /// Ambiguous: owed ring vanished with no host event (policy B).
  unknown,
}

/// What a row *is*, as opposed to what the wind was doing.
///
/// A morning's heads-up row and its outcome row share a reason (both "windy")
/// but read differently — `Still checking · …` vs `Skipped · …` — so the two
/// axes can't share one enum (2026-07-26). [cancelled] carries no reason of
/// its own; it keeps whatever was last known so the row stays faithful, and
/// simply doesn't render it.
enum HistoryKind { stillChecking, outcome, cancelled }

/// One line of Nivaat history: what happened and why. The trust mechanism —
/// a skipped alarm must always be explainable.
///
/// **Rows are immutable for card pushes** (user decision 2026-07-26), with one
/// carve-out (2026-08-08): a premature `Rang` written before the ring settled
/// is **overwritten in place** — same `alarmId + at + pushSeq`, so
/// [NivaatStore.upsertHistory]'s dedup replaces it — by a
/// [RingDisposition.missed] / [RingDisposition.unknown] correction. Rewriting
/// rather than appending is the point: the sheet renders every row, so an
/// appended correction would stack visible `Rang` above `Missed` for one
/// morning. Ordinary Keep-checking edits still append; that is why there is
/// still no general `copyWith` — reach for `upsertHistory` with a fresh
/// record instead.
///
/// [pushSeq] is what makes that safe. Two isolates racing on the same push
/// both read the same counter from `CheckState`, so they write the same
/// `alarmId + at + pushSeq` and converge onto one row; two genuinely separate
/// pushes get different numbers and both survive. Content can't be the key —
/// widening 30→60→30 produces two byte-identical rows that must both stay.
class HistoryRecord {
  const HistoryRecord({
    required this.alarmId,
    required this.courtId,
    required this.at,
    required this.outcome,
    this.kind = HistoryKind.outcome,
    this.pushSeq = 0,
    this.checkedAt,
    this.watchedUntil,
    this.checkingEndedAt,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.courtSpeedLimitKmh,
    this.rawGustLimitKmh,
    this.volume,
    this.ringDisposition,
    this.hostEventKey,
  })  : assert(
          watchedUntil == null || kind == HistoryKind.stillChecking,
          'only a still-checking row promises a deadline',
        ),
        assert(
          kind != HistoryKind.stillChecking || checkingEndedAt == null,
          'a still-checking row has not ended yet',
        );

  final int alarmId;

  /// The court this check was for. History is grouped and deleted by court
  /// (independently of whether the alarm still exists), so this is the durable
  /// link — [alarmId] can be reused or deleted, [courtId] stays put.
  final String courtId;

  /// The alarm's scheduled time (which alarm this row is about).
  final DateTime at;

  /// The wind reason. On a [HistoryKind.cancelled] row this is the last reason
  /// known when you stopped it — kept so the data stays true, not rendered.
  final CheckOutcome outcome;

  /// Which of the morning's rows this is. See [HistoryKind].
  final HistoryKind kind;

  /// Which card push wrote this row, counted per occurrence. The dedup key,
  /// not a display value — see the class doc.
  final int pushSeq;

  /// When the wind check that drove this outcome actually ran — the freshness
  /// of the reading behind the ring/skip. May be well *before* [at] (e.g. an
  /// alarm set at 22:00 whose only check was then, ringing at 06:00 on that
  /// 22:00 reading). Null when no check ever succeeded (no-data) or on older
  /// rows → falls back to [at]. See [whenChecked].
  final DateTime? checkedAt;

  /// The deadline this row promised — that alarm's retry cap (30/60 min, or a
  /// dev-gated 1) as it stood at this push. [HistoryKind.stillChecking] rows
  /// only, and frozen: a later Keep-checking edit writes a NEW row with the new
  /// cap rather than touching this one.
  final DateTime? watchedUntil;

  /// When checking actually stopped, which is not always when we last *saw*
  /// the wind. On an [HistoryKind.outcome] row it is the last attempt — equal
  /// to [whenChecked] unless that final attempt failed to reach the network,
  /// which is the one thing that distinguishes "we gave up at 06:29" from "we
  /// tried at 06:30 and got nothing". On a [HistoryKind.cancelled] row it is
  /// the moment you stopped it. Null on [HistoryKind.stillChecking].
  final DateTime? checkingEndedAt;
  final double? courtSpeedKmh;
  final double? rawGustKmh;

  /// The thresholds in force at decision time, stored so an old entry still
  /// shows all four numbers (speed & gust, each vs its cap) even after the
  /// alarm's limit is edited or the alarm is deleted. Null only for the very
  /// first builds' rows or a no-data skip that carried no thresholds.
  final int? courtSpeedLimitKmh;
  final double? rawGustLimitKmh;
  final double? volume;

  /// Ring settle result when this row is about the ring itself — orthogonal
  /// to [outcome]'s wind reason. Null on pure wind skips / still-checking.
  final RingDisposition? ringDisposition;

  /// The host event's `(id, recordedAt)` claim key when this row came from
  /// one, so a re-delivery finds its own row already written and stops rather
  /// than appending a second. Host events are delivered at least once by
  /// design — see `HostAlarmEventClaims` — so this is what makes the settle
  /// path idempotent, not the claim store.
  final String? hostEventKey;

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

}

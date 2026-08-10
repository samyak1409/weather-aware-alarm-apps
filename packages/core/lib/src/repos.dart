import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    this.cardShown = false,
    this.skipCourtSpeedKmh,
    this.skipRawGustKmh,
    this.skipGusty = false,
    this.lastCheckAt,
    this.lastAttemptAt,
    this.pushSeq = 0,
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

  /// True once the morning's card has been posted for this occurrence (at T),
  /// so the minute-by-minute retries don't re-post it — and so the paths that
  /// END the morning know whether there is anything to explain: a cancellation
  /// writes its row only where a card was shown, and a late ring only pulls a
  /// card down if one is up.
  ///
  /// Renamed from `extendedCheckShown` with the one-card model (2026-07-26) —
  /// the "extended check" card it was named for no longer exists.
  final bool cardShown;

  /// The last KNOWN skip reading — kept across no-data retries so the final
  /// card reports the real reason even if the cap check itself has no data.
  /// Null until a check actually reads a skip-worthy wind. [skipGusty]
  /// distinguishes gusty from windy (only meaningful when the speeds are set).
  final double? skipCourtSpeedKmh;
  final double? skipRawGustKmh;
  final bool skipGusty;

  /// How many cards this occurrence has pushed. Bumped once per push and
  /// stamped onto the history row it writes, so two isolates racing on the
  /// SAME push read the same number and their rows converge, while two
  /// separate pushes get different numbers and both survive. Lives here
  /// rather than in history because it is per-occurrence state, and history
  /// rows are immutable — see [HistoryRecord].
  final int pushSeq;

  CheckState copyWith({
    bool? ringScheduled,
    double? ringCourtSpeedKmh,
    double? ringRawGustKmh,
    double? ringVolume,
    bool? cardShown,
    double? skipCourtSpeedKmh,
    double? skipRawGustKmh,
    bool? skipGusty,
    DateTime? lastCheckAt,
    DateTime? lastAttemptAt,
    int? pushSeq,
  }) =>
      CheckState(
        alarmId: alarmId,
        alarmAt: alarmAt,
        ringScheduled: ringScheduled ?? this.ringScheduled,
        ringCourtSpeedKmh: ringCourtSpeedKmh ?? this.ringCourtSpeedKmh,
        ringRawGustKmh: ringRawGustKmh ?? this.ringRawGustKmh,
        ringVolume: ringVolume ?? this.ringVolume,
        cardShown: cardShown ?? this.cardShown,
        skipCourtSpeedKmh: skipCourtSpeedKmh ?? this.skipCourtSpeedKmh,
        skipRawGustKmh: skipRawGustKmh ?? this.skipRawGustKmh,
        skipGusty: skipGusty ?? this.skipGusty,
        lastCheckAt: lastCheckAt ?? this.lastCheckAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        pushSeq: pushSeq ?? this.pushSeq,
      );

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'alarmAt': alarmAt.toIso8601String(),
        'ringScheduled': ringScheduled,
        'ringCourtSpeedKmh': ringCourtSpeedKmh,
        'ringRawGustKmh': ringRawGustKmh,
        'ringVolume': ringVolume,
        'cardShown': cardShown,
        'skipCourtSpeedKmh': skipCourtSpeedKmh,
        'skipRawGustKmh': skipRawGustKmh,
        'skipGusty': skipGusty,
        'lastCheckAt': lastCheckAt?.toIso8601String(),
        'lastAttemptAt': lastAttemptAt?.toIso8601String(),
        'pushSeq': pushSeq,
      };

  factory CheckState.fromJson(Map<String, dynamic> j) => CheckState(
        alarmId: j['alarmId'] as int,
        alarmAt: DateTime.parse(j['alarmAt'] as String),
        ringScheduled: j['ringScheduled'] as bool,
        ringCourtSpeedKmh: (j['ringCourtSpeedKmh'] as num?)?.toDouble(),
        ringRawGustKmh: (j['ringRawGustKmh'] as num?)?.toDouble(),
        ringVolume: (j['ringVolume'] as num?)?.toDouble(),
        cardShown: j['cardShown'] as bool,
        skipCourtSpeedKmh: (j['skipCourtSpeedKmh'] as num?)?.toDouble(),
        skipRawGustKmh: (j['skipRawGustKmh'] as num?)?.toDouble(),
        skipGusty: j['skipGusty'] as bool,
        lastCheckAt: switch (j['lastCheckAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        lastAttemptAt: switch (j['lastAttemptAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        pushSeq: j['pushSeq'] as int,
      );
}

/// Which of Nivaat's three ring lockers held the pending ring.
enum RingLockerRole { ring, lateRing, nextRing }

/// A ring that was scheduled but not yet settled as audible / dropped / unknown.
///
/// Separate from [CheckState] so roll-on can open the next occurrence while
/// this still tracks the previous ring: [CheckState] is one slot per alarm, so
/// it cannot hold an unsettled ring and the next occurrence at once.
class PendingRing {
  const PendingRing({
    required this.alarmId,
    required this.pluginId,
    required this.role,
    required this.occurrenceAt,
    required this.scheduledFor,
    required this.courtId,
    this.volume,
    this.courtSpeedKmh,
    this.rawGustKmh,
    this.courtSpeedLimitKmh,
    this.rawGustLimitKmh,
    this.lastCheckAt,
    this.rollOnDone = false,
  });

  final int alarmId;
  final int pluginId;
  final RingLockerRole role;

  /// The occurrence this ring belongs to (alarmAt).
  final DateTime occurrenceAt;

  /// When the plugin was told to ring (may differ for lateRing / moves).
  final DateTime scheduledFor;

  final String courtId;
  final double? volume;
  final double? courtSpeedKmh;
  final double? rawGustKmh;
  final int? courtSpeedLimitKmh;
  final double? rawGustLimitKmh;
  final DateTime? lastCheckAt;

  /// True once `_rollOn` has already run for this pending — finalize must not
  /// roll again (replay / second isolate).
  final bool rollOnDone;

  PendingRing copyWith({
    DateTime? scheduledFor,
    bool? rollOnDone,
  }) =>
      PendingRing(
        alarmId: alarmId,
        pluginId: pluginId,
        role: role,
        occurrenceAt: occurrenceAt,
        scheduledFor: scheduledFor ?? this.scheduledFor,
        courtId: courtId,
        volume: volume,
        courtSpeedKmh: courtSpeedKmh,
        rawGustKmh: rawGustKmh,
        courtSpeedLimitKmh: courtSpeedLimitKmh,
        rawGustLimitKmh: rawGustLimitKmh,
        lastCheckAt: lastCheckAt,
        rollOnDone: rollOnDone ?? this.rollOnDone,
      );

  Map<String, dynamic> toJson() => {
        'alarmId': alarmId,
        'pluginId': pluginId,
        'role': role.name,
        'occurrenceAt': occurrenceAt.toIso8601String(),
        'scheduledFor': scheduledFor.toIso8601String(),
        'courtId': courtId,
        'volume': volume,
        'courtSpeedKmh': courtSpeedKmh,
        'rawGustKmh': rawGustKmh,
        'courtSpeedLimitKmh': courtSpeedLimitKmh,
        'rawGustLimitKmh': rawGustLimitKmh,
        'lastCheckAt': lastCheckAt?.toIso8601String(),
        'rollOnDone': rollOnDone,
      };

  factory PendingRing.fromJson(Map<String, dynamic> j) => PendingRing(
        alarmId: j['alarmId'] as int,
        pluginId: j['pluginId'] as int,
        role: RingLockerRole.values.byName(j['role'] as String),
        occurrenceAt: DateTime.parse(j['occurrenceAt'] as String),
        scheduledFor: DateTime.parse(j['scheduledFor'] as String),
        courtId: j['courtId'] as String,
        volume: (j['volume'] as num?)?.toDouble(),
        courtSpeedKmh: (j['courtSpeedKmh'] as num?)?.toDouble(),
        rawGustKmh: (j['rawGustKmh'] as num?)?.toDouble(),
        courtSpeedLimitKmh: j['courtSpeedLimitKmh'] as int?,
        rawGustLimitKmh: (j['rawGustLimitKmh'] as num?)?.toDouble(),
        lastCheckAt: switch (j['lastCheckAt']) {
          final String s => DateTime.parse(s),
          _ => null,
        },
        rollOnDone: j['rollOnDone'] as bool,
      );
}

class NivaatStore {
  static const _courtsKey = 'nivaat.courts';
  static const _alarmsKey = 'nivaat.alarms';
  static const _alarmIdSeqKey = 'nivaat.alarmIdSeq';
  static const _historyKey = 'nivaat.history';
  static const _statePrefix = 'nivaat.checkstate.';
  static const _pendingPrefix = 'nivaat.pendingRing.';
  static const _soundKey = 'nivaat.sound';

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

  /// The next alarm id to hand out, or null before the first alarm has ever
  /// been saved (REVIEW #9). **Null means 1, never "work it out from the
  /// alarms"** — deriving it is the original bug wearing a recovery hat, since
  /// ids are `block + alarmId` and a reissued number inherits the old alarm's
  /// ring, check and card. `NivaatController.upsertAlarm` keeps this ahead of
  /// every stored id by saving it first.
  Future<int?> loadAlarmIdSeq() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_alarmIdSeqKey);
  }

  Future<void> saveAlarmIdSeq(int next) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_alarmIdSeqKey, next);
  }

  Future<List<HistoryRecord>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_historyKey), HistoryRecord.fromJson);
  }

  /// Inserts [record], REPLACING any existing row for the same PUSH — same
  /// occurrence (`alarmId + at`) and same `pushSeq`.
  ///
  /// History is append-only (user decision 2026-07-20, tightened 2026-07-26):
  /// every card push writes one row and **nothing is ever rewritten**. The
  /// replace half exists solely so a foreground/background double-write of
  /// the *same* push converges onto one row instead of duplicating it — both
  /// isolates read the same `CheckState.pushSeq`, so they collide by design.
  /// Two genuinely different pushes carry different numbers and both survive,
  /// which is why the key can't be the row's content: widening Keep checking
  /// 30→60→30 leaves two byte-identical rows that must both stay.
  ///
  /// New rows prepend (newest first).
  ///
  /// **The log is unbounded (2026-07-31, Samyak).** It used to keep only the
  /// newest 60 rows, which contradicted SPEC's "history is immediate,
  /// *permanent*, and append-only" — and 60 is not the long log it sounds
  /// like: one morning writes a row per card push, so two alarms retiring
  /// their promise-then-outcome pair spend it in a fortnight. The only thing
  /// that ever explains a morning the alarm didn't ring was being deleted on a
  /// schedule nobody chose. Deleting a court still wipes that court's rows
  /// ([removeHistoryForCourt]) — an explicit act, not a silent ceiling.
  ///
  /// Cost, accepted: the whole log is one JSON string, decoded and re-encoded
  /// on every write, so a write is O(rows). A fully-populated row measures
  /// **330 bytes**, and a two-alarm day writes about four, so a year lands
  /// near half a megabyte — fine for the prefs store, and the writes run in a
  /// background isolate. It is still the reason a future version that wants
  /// years of history wants a real database rather than a bigger blob.
  ///
  /// **Surviving the other isolate (REVIEW #7).** One blob, read-modify-write,
  /// two isolates that genuinely run at once — the app open at 06:00 while the
  /// AlarmManager wakeup fires is the DESIGNED case, not a corner. Two things
  /// keep a row from being written straight over:
  ///
  /// 1. **[refresh] first**, so the read is of the disk and not of this
  ///    isolate's cache. Without it the whole hazard needs no concurrency at
  ///    all: a foreground that loaded prefs at startup rebuilds the log from a
  ///    snapshot taken before the background check's row existed, and saving it
  ///    back deletes that row. That was the reported bug — a background `Still
  ///    checking` losing to a foreground `Cancelled`.
  /// 2. **Read back and re-apply.** If a concurrent isolate's save landed
  ///    between our read and our write, our row is simply gone; writing it
  ///    again on top of the now-fresher list keeps BOTH. This converges rather
  ///    than livelocking — each retry reads the other side's row and preserves
  ///    it — and it is bounded, because a row that cannot be re-applied twice
  ///    is losing to something we cannot outrun anyway.
  ///
  /// **This is convergence, not a lock:** SharedPreferences offers none, the
  /// read-modify-write is still not atomic, and an unlucky interleaving can
  /// still drop a row. The real answer is a database, not more retries here.
  Future<void> upsertHistory(HistoryRecord record) async {
    bool isSamePush(HistoryRecord r) =>
        r.alarmId == record.alarmId &&
        r.at == record.at &&
        r.pushSeq == record.pushSeq;
    for (var attempt = 0; attempt < 3; attempt++) {
      await refresh();
      final all = await loadHistory();
      final i = all.indexWhere(isSamePush);
      final rows = [...all];
      if (i >= 0) {
        rows[i] = record;
      } else {
        rows.insert(0, record);
      }
      await _saveList(_historyKey, rows.map((r) => r.toJson()));
      await refresh();
      // By KEY, not by content: a foreground/background double-write of the
      // same push is meant to converge onto one row, so finding the other
      // side's copy of it is success, not a reason to write again.
      if ((await loadHistory()).any(isSamePush)) return;
    }
    // Logged rather than swallowed: this is the log that explains a morning the
    // alarm didn't ring, so a row lost here is worth a trace even though there
    // is nothing left to do about it.
    debugPrint('nivaat history row (alarm ${record.alarmId}, ${record.at}, '
        'push ${record.pushSeq}) lost to a concurrent write after 3 tries');
  }

  /// Drops every history row for [courtId] — used when a court is deleted, so
  /// its whole skip/ring log goes with it. Keyed by court, so this reaches
  /// *every* row for the court, including those from alarms deleted earlier.
  ///
  /// [refresh] first for the same reason as [upsertHistory]: this rebuilds the
  /// whole blob from what it reads, so reading a stale cache would resurrect
  /// every row a background check has written since. No read-back here — a
  /// removal that loses the race leaves court-less rows, and
  /// `NivaatController._loadHistory` already prunes those on every load.
  Future<void> removeHistoryForCourt(String courtId) async {
    await refresh();
    final kept = (await loadHistory()).where((r) => r.courtId != courtId);
    await _saveList(_historyKey, kept.map((r) => r.toJson()));
  }

  /// **Reads and writes reload first, exactly like the history rows and the
  /// pending ring** (REVIEW #7's rule, extended here 2026-08-09).
  ///
  /// `CheckState` is the same shape of state as those two — written by
  /// whichever isolate is awake, read by the other — and it carries
  /// `ringScheduled`, which decides whether a morning is settled at all. A
  /// foreground holding a snapshot from launch would re-save an old
  /// `ringScheduled` over a background isolate that had just cleared it.
  Future<CheckState?> loadCheckState(int alarmId) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_statePrefix$alarmId');
    if (raw == null) return null;
    return CheckState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveCheckState(CheckState state) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_statePrefix${state.alarmId}',
      jsonEncode(state.toJson()),
    );
  }

  Future<void> clearCheckState(int alarmId) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_statePrefix$alarmId');
  }

  /// **Every pending-ring read and write reloads first** (the REVIEW #7 rule,
  /// extended here 2026-08-09).
  ///
  /// This slot decides whether a morning reads `Rang` or `Couldn't confirm`,
  /// and it is written by whichever isolate happened to be awake at T. Without
  /// the reload the foreground, holding a snapshot from launch, sees no pending
  /// for a ring the background check armed at 06:00 — and then settles the
  /// morning as unconfirmed on evidence it simply could not see. Same split as
  /// the history rows, on the state that now chooses the wording.
  Future<PendingRing?> loadPendingRing(int alarmId) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_pendingPrefix$alarmId');
    if (raw == null) return null;
    return PendingRing.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> savePendingRing(PendingRing pending) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_pendingPrefix${pending.alarmId}',
      jsonEncode(pending.toJson()),
    );
  }

  Future<void> clearPendingRing(int alarmId) async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_pendingPrefix$alarmId');
  }

  /// Every pending ring still on disk — used for ambiguous-B recovery and
  /// host-event matching across alarms.
  Future<List<PendingRing>> loadAllPendingRings() async {
    await refresh();
    final prefs = await SharedPreferences.getInstance();
    final out = <PendingRing>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_pendingPrefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      out.add(PendingRing.fromJson(jsonDecode(raw) as Map<String, dynamic>));
    }
    return out;
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

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db/app_database.dart';
import 'db/tables.dart';
import 'models.dart';

/// Arunoday's settings: one writer (the UI isolate), so they stay on
/// SharedPreferences.
///
/// The two-backend split and why it is the design rather than a half-finished
/// migration is on `AppDatabase`; the inventory of what sits on which side is
/// on `tables.dart`.
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

}


/// Nivaat's contended state, on SQLite.
///
/// **Every method keeps the signature it had on SharedPreferences**, so the
/// call sites did not move — which is what makes this diff reviewable. What
/// changed is underneath: each read-modify-write that two isolates could
/// interleave is now either a single statement or a [transaction].
///
/// **`refresh()` is gone, and its absence is the point.** It existed because
/// SharedPreferences caches per isolate, so a background wind check's write was
/// invisible to the already-running app until a cold start; every read here had
/// to reload first or risk deciding on state it simply could not see. SQLite
/// reads the file, so there is no per-isolate cache to defeat and nothing to
/// remember to call. The reads that used to reload are ordinary reads now.
class NivaatStore {
  /// Resolved per call rather than captured in a field: tests swap the database
  /// in `setUp`, and a store built before that would otherwise go on writing to
  /// the one the previous test closed.
  AppDatabase get _db => appDb;

  /// The alarm tone stays on SharedPreferences — one writer (the UI), no
  /// contention, nothing to make atomic.
  static const _soundKey = 'nivaat.sound';

  /// Row name for the alarm-id counter in [Counters].
  static const _alarmIdSeqCounter = 'nivaat.alarmIdSeq';

  /// Runs [action] as one atomic unit — everything inside lands or nothing
  /// does, even against another isolate holding its own connection to the same
  /// file.
  ///
  /// Drift's native executor opens these with `BEGIN IMMEDIATE`, so the write
  /// lock is taken up front rather than upgraded mid-transaction, which is what
  /// makes it safe for two connections to contend on one file.
  ///
  /// **A transaction may not contain a platform call.** It covers the database
  /// and nothing else: an alarm armed inside one is still armed after a
  /// rollback, and no `ROLLBACK` can un-arm it. Intents that need a platform
  /// call go through [OutboxStore] instead.
  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

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
    final rows = await (_db.select(_db.courts)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return [
      for (final r in rows)
        SavedLocation(
          id: r.id,
          name: r.name,
          lat: r.lat,
          lon: r.lon,
          source: r.source,
          region: r.region,
        ),
    ];
  }

  /// Replaces the whole court list in one transaction.
  ///
  /// Whole-list replace rather than a per-row diff because that is what the
  /// callers mean — they hand over the list they want stored. A reader on
  /// another connection sees the old list or the new one, never the empty gap
  /// in between, which the prefs blob also gave but only by accident of being
  /// one key.
  Future<void> saveCourts(List<SavedLocation> courts) =>
      _db.transaction(() async {
        await _db.delete(_db.courts).go();
        await _db.batch((b) => b.insertAll(_db.courts, [
              for (var i = 0; i < courts.length; i++)
                CourtsCompanion(
                  id: Value(courts[i].id),
                  name: Value(courts[i].name),
                  lat: Value(courts[i].lat),
                  lon: Value(courts[i].lon),
                  source: Value(courts[i].source),
                  region: Value(courts[i].region),
                  position: Value(i),
                ),
            ]));
      });

  Future<List<NivaatAlarm>> loadAlarms() async {
    final rows = await (_db.select(_db.nivaatAlarms)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return [
      for (final r in rows)
        NivaatAlarm(
          id: r.id,
          hour: r.hour,
          minute: r.minute,
          courtId: r.courtId,
          courtSpeedLimitKmh: r.courtSpeedLimitKmh,
          retryMinutesAfter: r.retryMinutesAfter,
          weekdays: r.weekdays,
          enabled: r.enabled,
        ),
    ];
  }

  /// Replaces the alarm list, optionally advancing the id counter **in the same
  /// transaction**.
  ///
  /// That pairing is the whole of REVIEW #9's guarantee, and it is now
  /// structural rather than a rule to remember. The old code saved the counter
  /// first and the alarms second, deliberately, because interrupted between the
  /// two writes it is better to skip a number than to leave an alarm with no
  /// counter past it — the next alarm created would take that number and
  /// inherit its ring, late ring, check, card and cascade state. There is no
  /// "between the two writes" any more: pass [alarmIdSeq] and both land or
  /// neither does.
  ///
  /// The counter is still written first inside the transaction. That is now
  /// redundant and kept on purpose, so the ordering rule stays visible to
  /// anyone who ever splits this apart again.
  Future<void> saveAlarms(List<NivaatAlarm> alarms, {int? alarmIdSeq}) =>
      _db.transaction(() async {
        if (alarmIdSeq != null) await saveAlarmIdSeq(alarmIdSeq);
        await _db.delete(_db.nivaatAlarms).go();
        await _db.batch((b) => b.insertAll(_db.nivaatAlarms, [
              for (var i = 0; i < alarms.length; i++)
                NivaatAlarmsCompanion(
                  id: Value(alarms[i].id),
                  hour: Value(alarms[i].hour),
                  minute: Value(alarms[i].minute),
                  courtId: Value(alarms[i].courtId),
                  courtSpeedLimitKmh: Value(alarms[i].courtSpeedLimitKmh),
                  retryMinutesAfter: Value(alarms[i].retryMinutesAfter),
                  weekdays: Value(alarms[i].weekdays),
                  enabled: Value(alarms[i].enabled),
                  position: Value(i),
                ),
            ]));
      });

  /// The next alarm id to hand out, or null before the first alarm has ever
  /// been saved (REVIEW #9). **Null means 1, never "work it out from the
  /// alarms"** — deriving it is the original bug wearing a recovery hat, since
  /// ids are `block + alarmId` and a reissued number inherits the old alarm's
  /// ring, check and card. `NivaatController.upsertAlarm` keeps this ahead of
  /// every stored id by writing it in the same transaction as the alarms.
  Future<int?> loadAlarmIdSeq() async {
    final row = await (_db.select(_db.counters)
          ..where((t) => t.name.equals(_alarmIdSeqCounter)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> saveAlarmIdSeq(int next) => _db
      .into(_db.counters)
      .insertOnConflictUpdate(CountersCompanion(
        name: const Value(_alarmIdSeqCounter),
        value: Value(next),
      ));

  /// The whole log, newest first.
  ///
  /// Ordered by [HistoryEntries.rowSeq] descending, which is insertion order —
  /// the prefs version got the same thing by prepending onto a list. Callers
  /// depend on it: `nivaatLatestRowPerOccurrence` breaks a `pushSeq` tie by
  /// list order and documents that callers pass newest-first.
  Future<List<HistoryRecord>> loadHistory() async {
    final rows = await (_db.select(_db.historyEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.rowSeq)]))
        .get();
    return rows.map(_historyFromRow).toList();
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
  /// **The log is unbounded (2026-07-31, Samyak)** — deleting a court is the
  /// only thing that removes rows ([removeHistoryForCourt]). The size worry
  /// that argument was had with is gone: this writes one row rather than
  /// re-encoding the whole log.
  ///
  /// **This is one atomic statement now, and the retry loop it replaces is
  /// deleted.** The old version reloaded, rebuilt the list, saved, read back
  /// and re-applied up to three times — convergence, not a lock, and an unlucky
  /// interleaving could still drop a row, which is exactly what a database was
  /// wanted for. `INSERT … ON CONFLICT DO UPDATE` cannot lose a concurrent
  /// row: a competing writer either loses the race and updates ours, or wins it
  /// and has ours applied on top. Nothing to retry, nothing to converge.
  ///
  /// The conflict update deliberately leaves `rowSeq` alone, so a row corrected
  /// in place keeps its position in the log rather than jumping to the top.
  Future<void> upsertHistory(HistoryRecord record) async {
    final row = _historyCompanion(record);
    await _db.into(_db.historyEntries).insert(
          row,
          onConflict: DoUpdate(
            (_) => row,
            target: [
              _db.historyEntries.alarmId,
              _db.historyEntries.at,
              _db.historyEntries.pushSeq,
            ],
          ),
        );
  }

  /// Drops every history row for [courtId] — used when a court is deleted, so
  /// its whole skip/ring log goes with it. Keyed by court, so this reaches
  /// *every* row for the court, including those from alarms deleted earlier.
  ///
  /// One `DELETE`, so a row another isolate writes while this runs is either
  /// deleted with the rest or lands after and survives as an orphan —
  /// `NivaatController._loadHistory` already prunes those on every load. The
  /// prefs version rebuilt the whole blob from what it read, which is why it
  /// had to reload first or resurrect everything written since.
  Future<void> removeHistoryForCourt(String courtId) =>
      (_db.delete(_db.historyEntries)..where((t) => t.courtId.equals(courtId)))
          .go();

  Future<CheckState?> loadCheckState(int alarmId) async {
    final row = await (_db.select(_db.checkStates)
          ..where((t) => t.alarmId.equals(alarmId)))
        .getSingleOrNull();
    if (row == null) return null;
    return CheckState(
      alarmId: row.alarmId,
      alarmAt: row.alarmAt,
      ringScheduled: row.ringScheduled,
      ringCourtSpeedKmh: row.ringCourtSpeedKmh,
      ringRawGustKmh: row.ringRawGustKmh,
      ringVolume: row.ringVolume,
      cardShown: row.cardShown,
      skipCourtSpeedKmh: row.skipCourtSpeedKmh,
      skipRawGustKmh: row.skipRawGustKmh,
      skipGusty: row.skipGusty,
      lastCheckAt: row.lastCheckAt,
      lastAttemptAt: row.lastAttemptAt,
      pushSeq: row.pushSeq,
    );
  }

  Future<void> saveCheckState(CheckState state) =>
      _db.into(_db.checkStates).insertOnConflictUpdate(CheckStatesCompanion(
            alarmId: Value(state.alarmId),
            alarmAt: Value(state.alarmAt),
            ringScheduled: Value(state.ringScheduled),
            ringCourtSpeedKmh: Value(state.ringCourtSpeedKmh),
            ringRawGustKmh: Value(state.ringRawGustKmh),
            ringVolume: Value(state.ringVolume),
            cardShown: Value(state.cardShown),
            skipCourtSpeedKmh: Value(state.skipCourtSpeedKmh),
            skipRawGustKmh: Value(state.skipRawGustKmh),
            skipGusty: Value(state.skipGusty),
            lastCheckAt: Value(state.lastCheckAt),
            lastAttemptAt: Value(state.lastAttemptAt),
            pushSeq: Value(state.pushSeq),
          ));

  Future<void> clearCheckState(int alarmId) =>
      (_db.delete(_db.checkStates)..where((t) => t.alarmId.equals(alarmId)))
          .go();

  /// Clears [alarmId]'s state **only if it still describes [occurrenceAt]**.
  ///
  /// One statement, replacing a load-compare-delete: the old shape read the
  /// state, checked its `alarmAt`, and deleted — and a roll-on landing in that
  /// gap writes the NEXT occurrence's state into the same slot, which the
  /// delete would then throw away. The occurrence goes into the `WHERE` clause
  /// so there is no gap to land in.
  Future<void> clearCheckStateForOccurrence(
    int alarmId,
    DateTime occurrenceAt,
  ) =>
      (_db.delete(_db.checkStates)
            ..where((t) =>
                t.alarmId.equals(alarmId) & t.alarmAt.equalsValue(occurrenceAt)))
          .go();

  Future<PendingRing?> loadPendingRing(int alarmId) async {
    final row = await (_db.select(_db.pendingRings)
          ..where((t) => t.alarmId.equals(alarmId)))
        .getSingleOrNull();
    return row == null ? null : _pendingFromRow(row);
  }

  Future<void> savePendingRing(PendingRing pending) =>
      _db.into(_db.pendingRings).insertOnConflictUpdate(PendingRingsCompanion(
            alarmId: Value(pending.alarmId),
            pluginId: Value(pending.pluginId),
            role: Value(pending.role),
            occurrenceAt: Value(pending.occurrenceAt),
            scheduledFor: Value(pending.scheduledFor),
            courtId: Value(pending.courtId),
            volume: Value(pending.volume),
            courtSpeedKmh: Value(pending.courtSpeedKmh),
            rawGustKmh: Value(pending.rawGustKmh),
            courtSpeedLimitKmh: Value(pending.courtSpeedLimitKmh),
            rawGustLimitKmh: Value(pending.rawGustLimitKmh),
            lastCheckAt: Value(pending.lastCheckAt),
            rollOnDone: Value(pending.rollOnDone),
          ));

  Future<void> clearPendingRing(int alarmId) =>
      (_db.delete(_db.pendingRings)..where((t) => t.alarmId.equals(alarmId)))
          .go();

  /// Clears [alarmId]'s pending ring **only if it still describes
  /// [occurrenceAt]**.
  ///
  /// Same shape and same reason as [clearCheckStateForOccurrence], on the state
  /// where it matters most: a settle rolls on before clearing, the roll is a
  /// whole evaluation, and it is exactly where the next occurrence's pending
  /// gets written. Reading first and deleting after would drop a ring that had
  /// only just been armed. Ring ids repeat daily, so the occurrence — never the
  /// plugin id — is what ownership is matched on.
  Future<void> clearPendingRingForOccurrence(
    int alarmId,
    DateTime occurrenceAt,
  ) =>
      (_db.delete(_db.pendingRings)
            ..where((t) =>
                t.alarmId.equals(alarmId) &
                t.occurrenceAt.equalsValue(occurrenceAt)))
          .go();

  /// Every pending ring still stored — used for ambiguous-B recovery and
  /// host-event matching across alarms.
  Future<List<PendingRing>> loadAllPendingRings() async {
    final rows = await _db.select(_db.pendingRings).get();
    return rows.map(_pendingFromRow).toList();
  }

  static PendingRing _pendingFromRow(PendingRingRow row) => PendingRing(
        alarmId: row.alarmId,
        pluginId: row.pluginId,
        role: row.role,
        occurrenceAt: row.occurrenceAt,
        scheduledFor: row.scheduledFor,
        courtId: row.courtId,
        volume: row.volume,
        courtSpeedKmh: row.courtSpeedKmh,
        rawGustKmh: row.rawGustKmh,
        courtSpeedLimitKmh: row.courtSpeedLimitKmh,
        rawGustLimitKmh: row.rawGustLimitKmh,
        lastCheckAt: row.lastCheckAt,
        rollOnDone: row.rollOnDone,
      );

  static HistoryRecord _historyFromRow(HistoryEntry row) => HistoryRecord(
        alarmId: row.alarmId,
        courtId: row.courtId,
        at: row.at,
        outcome: row.outcome,
        kind: row.kind,
        pushSeq: row.pushSeq,
        checkedAt: row.checkedAt,
        watchedUntil: row.watchedUntil,
        checkingEndedAt: row.checkingEndedAt,
        courtSpeedKmh: row.courtSpeedKmh,
        rawGustKmh: row.rawGustKmh,
        courtSpeedLimitKmh: row.courtSpeedLimitKmh,
        rawGustLimitKmh: row.rawGustLimitKmh,
        volume: row.volume,
        ringDisposition: row.ringDisposition,
        hostEventKey: row.hostEventKey,
      );

  static HistoryEntriesCompanion _historyCompanion(HistoryRecord r) =>
      HistoryEntriesCompanion(
        alarmId: Value(r.alarmId),
        at: Value(r.at),
        pushSeq: Value(r.pushSeq),
        courtId: Value(r.courtId),
        outcome: Value(r.outcome),
        kind: Value(r.kind),
        checkedAt: Value(r.checkedAt),
        watchedUntil: Value(r.watchedUntil),
        checkingEndedAt: Value(r.checkingEndedAt),
        courtSpeedKmh: Value(r.courtSpeedKmh),
        rawGustKmh: Value(r.rawGustKmh),
        courtSpeedLimitKmh: Value(r.courtSpeedLimitKmh),
        rawGustLimitKmh: Value(r.rawGustLimitKmh),
        volume: Value(r.volume),
        ringDisposition: Value(r.ringDisposition),
        hostEventKey: Value(r.hostEventKey),
      );
}

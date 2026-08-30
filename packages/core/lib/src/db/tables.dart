import 'package:drift/drift.dart';

import '../models.dart';
import '../repos.dart';
import '../wind.dart';

/// Every table that carries **contended** state — anything two isolates can
/// write at the same time.
///
/// Single-writer settings deliberately stay on SharedPreferences
/// (`arunoday.settings`, `nivaat.sound`, `appearance.heavyType`, `dev.enabled`,
/// the three "asked" flags). Mixing the two stores is the design, not a smell:
/// only what two isolates fight over needs a transaction, and prefs is the
/// cheaper store for the rest. If a second writer ever appears for one of
/// those keys, it moves here too.
///
/// **Instants are microseconds since epoch, not drift's default.** Drift stores
/// a `DateTime` as unix *seconds* unless told otherwise, and this app compares
/// instants far below that: `_hostEventSlack`, `closed + 1ms`, and — the one
/// that actually breaks — `CheckState.alarmAt == PendingRing.occurrenceAt`,
/// which is `DateTime.==` and therefore exact. Text storage would round-trip
/// through UTC and come back with `isUtc` set, and `DateTime.==` compares that
/// flag too, so every such comparison would silently go false. Microseconds
/// through [dateTimeMicros] round-trip any Dart `DateTime` losslessly and land
/// back in local time, which is what the old `toIso8601String()` /
/// `DateTime.parse` pair did.

/// `DateTime` <-> microseconds since epoch. See the note above for why not
/// drift's built-in seconds or text mapping.
class _DateTimeMicrosConverter extends TypeConverter<DateTime, int> {
  const _DateTimeMicrosConverter();

  @override
  DateTime fromSql(int fromDb) => DateTime.fromMicrosecondsSinceEpoch(fromDb);

  @override
  int toSql(DateTime value) => value.microsecondsSinceEpoch;
}

const dateTimeMicros = _DateTimeMicrosConverter();
const nullableDateTimeMicros =
    NullAwareTypeConverter.wrap(_DateTimeMicrosConverter());

/// `Set<int>` <-> a sorted comma-separated list ("1,3,5").
///
/// Sorted on the way in so two writes of the same weekdays produce the same
/// bytes — a set has no order of its own, and an unstable encoding would make
/// `_stillLive`'s field-by-field comparison see an edit that never happened.
class _WeekdaySetConverter extends TypeConverter<Set<int>, String> {
  const _WeekdaySetConverter();

  @override
  Set<int> fromSql(String fromDb) =>
      fromDb.isEmpty ? <int>{} : fromDb.split(',').map(int.parse).toSet();

  @override
  String toSql(Set<int> value) => (value.toList()..sort()).join(',');
}

const weekdaySet = _WeekdaySetConverter();

/// Nivaat's saved courts. [position] keeps the list order the UI renders.
///
/// [source] and [region] are the ⓘ's provenance (X5, `savedLocationDetail`):
/// the enum by NAME rather than by index, so adding a third way to pick a place
/// can never re-label the courts already saved. [region] is nullable because a
/// GPS fix genuinely has none.
class Courts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get lat => real()();
  RealColumn get lon => real()();
  TextColumn get source => textEnum<PlaceSource>()();
  TextColumn get region => text().nullable()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Nivaat's alarms. Moves together with [Counters]' `nivaat.alarmIdSeq`,
/// because the counter must reach the disk before the alarm that spends it —
/// that ordering is now one transaction rather than a documented sequence.
///
/// Renamed away from drift's default `NivaatAlarm` because that is the model
/// class; same reason for [CheckStates] and [PendingRings] below. These row
/// types never leave the DB layer — the stores hand back the models.
@DataClassName('AlarmRow')
class NivaatAlarms extends Table {
  IntColumn get id => integer()();
  IntColumn get hour => integer()();
  IntColumn get minute => integer()();
  TextColumn get courtId => text()();
  IntColumn get courtSpeedLimitKmh => integer()();
  IntColumn get retryMinutesAfter => integer()();
  IntColumn get timeUntilPlayMinutes => integer()();
  IntColumn get minPlayMinutes => integer()();
  TextColumn get weekdays => text().map(weekdaySet)();
  BoolColumn get enabled => boolean()();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Named integer counters. One row today: `nivaat.alarmIdSeq`.
class Counters extends Table {
  TextColumn get name => text()();
  IntColumn get value => integer()();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// Nivaat's history log — one row per card push.
///
/// [rowSeq] is an autoincrementing surrogate key and the **render order**:
/// callers read newest-first, which the prefs version got by prepending onto a
/// list. An upsert on the natural key deliberately leaves [rowSeq] alone, so a
/// row corrected in place keeps its position rather than jumping to the top.
///
/// The natural key `(alarmId, at, pushSeq)` is a UNIQUE index rather than the
/// primary key, so [rowSeq] can stay monotonic. That key is what makes two
/// isolates racing on the SAME push converge onto one row while two genuinely
/// different pushes both survive.
class HistoryEntries extends Table {
  IntColumn get rowSeq => integer().autoIncrement()();
  IntColumn get alarmId => integer()();
  IntColumn get at => integer().map(dateTimeMicros)();
  IntColumn get pushSeq => integer()();
  TextColumn get courtId => text()();
  TextColumn get outcome => textEnum<CheckOutcome>()();
  TextColumn get kind => textEnum<HistoryKind>()();
  IntColumn get checkedAt => integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get watchedUntil =>
      integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get checkingEndedAt =>
      integer().nullable().map(nullableDateTimeMicros)();
  RealColumn get courtSpeedKmh => real().nullable()();
  RealColumn get rawGustKmh => real().nullable()();
  IntColumn get courtSpeedLimitKmh => integer().nullable()();
  RealColumn get rawGustLimitKmh => real().nullable()();

  /// The 15-minute slot the numbers above DESCRIBE — the worst one in the play
  /// window, which is the one that decided the occurrence.
  ///
  /// Distinct from [checkedAt], which is when the check ran. They differ by the
  /// whole lead time, so a row saying `last checked 06:00` about wind measured
  /// for 06:45 needs to name the 06:45 or it reads as a contradiction.
  IntColumn get slotAt => integer().nullable().map(nullableDateTimeMicros)();
  RealColumn get volume => real().nullable()();
  TextColumn get ringDisposition => textEnum<RingDisposition>().nullable()();
  TextColumn get hostEventKey => text().nullable()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {alarmId, at, pushSeq},
      ];
}

/// Per-alarm cascade state, one row per alarm.
@DataClassName('CheckStateRow')
class CheckStates extends Table {
  IntColumn get alarmId => integer()();
  IntColumn get alarmAt => integer().map(dateTimeMicros)();
  BoolColumn get ringScheduled => boolean()();
  RealColumn get ringCourtSpeedKmh => real().nullable()();
  RealColumn get ringRawGustKmh => real().nullable()();

  /// The slot behind the ring's reading, so a `Rang` history row can name the
  /// moment its numbers came from exactly as a skipped row does. Its twin is
  /// `skipSlotAt` above.
  IntColumn get ringSlotAt => integer().nullable().map(nullableDateTimeMicros)();
  RealColumn get ringVolume => real().nullable()();
  BoolColumn get cardShown => boolean()();
  RealColumn get skipCourtSpeedKmh => real().nullable()();
  RealColumn get skipRawGustKmh => real().nullable()();
  IntColumn get skipSlotAt =>
      integer().nullable().map(nullableDateTimeMicros)();
  BoolColumn get skipGusty => boolean()();
  IntColumn get lastCheckAt =>
      integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get lastAttemptAt =>
      integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get pushSeq => integer()();

  @override
  Set<Column<Object>> get primaryKey => {alarmId};
}

/// A ring that was scheduled but not yet settled. One row per alarm — the slot
/// that decides whether an occurrence reads `Rang` or `Couldn't confirm`.
@DataClassName('PendingRingRow')
class PendingRings extends Table {
  IntColumn get alarmId => integer()();
  IntColumn get pluginId => integer()();
  TextColumn get role => textEnum<RingLockerRole>()();
  IntColumn get occurrenceAt => integer().map(dateTimeMicros)();
  IntColumn get scheduledFor => integer().map(dateTimeMicros)();
  TextColumn get courtId => text()();
  RealColumn get volume => real().nullable()();
  RealColumn get courtSpeedKmh => real().nullable()();
  RealColumn get rawGustKmh => real().nullable()();
  IntColumn get courtSpeedLimitKmh => integer().nullable()();
  RealColumn get rawGustLimitKmh => real().nullable()();

  /// The slot behind those readings — carried so a disposition row settled
  /// from a pending ring names the same moment its live twin would.
  IntColumn get slotAt => integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get lastCheckAt =>
      integer().nullable().map(nullableDateTimeMicros)();
  BoolColumn get rollOnDone => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {alarmId};
}

/// Where a host event has got to.
///
/// **A boolean would not have been enough, and that is the whole reason this
/// is a state column.** "Insert the claim, then run the handler" is the prefs
/// bug this repo already fixed once from the other side: the row says *handled*
/// while the handler has not run, and a process death in between makes the
/// event permanently invisible — the plugin acknowledged it natively long ago,
/// so nothing will redeliver it. [processing] with a lease is what makes the
/// crash recoverable: the next barrier finds an expired lease and runs the
/// handler again, which is safe because every handler is idempotent on
/// `(id, recordedAt)`.
///
/// [abandoned] is terminal and is **not** [done]: it means a handler failed its
/// last attempt, so the event was neither applied nor is it coming back.
/// Keeping the two apart is the point — reading an abandoned event as handled
/// is how a dropped ring ends up with no history row and nothing to explain it.
enum HostEventClaimState { pending, processing, done, abandoned }

/// Host events this isolate has taken responsibility for.
///
/// Keyed by the same `hostAlarmEvent.<id>.<recordedAtMillis>` string the prefs
/// version used, so history rows that stamped a `hostEventKey` still match.
class HostEventClaims extends Table {
  TextColumn get claimKey => text()();
  TextColumn get state => textEnum<HostEventClaimState>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get leasedUntil =>
      integer().nullable().map(nullableDateTimeMicros)();

  /// The event's own `recordedAt`, kept as a column rather than parsed back out
  /// of [claimKey] so the TTL sweep is a `WHERE` clause instead of a scan.
  IntColumn get recordedAt => integer().map(dateTimeMicros)();
  IntColumn get updatedAt => integer().map(dateTimeMicros)();

  @override
  Set<Column<Object>> get primaryKey => {claimKey};
}

/// AlarmKit's `int id -> UUID` mapping, **one row per handle** rather than one
/// blob for every id.
///
/// Two ids can no longer contend, which is the concurrent half of REVIEW #7.
/// **It is not the other half:** AlarmKit mints the UUID, so there is still
/// nothing to write down until `scheduleOneShotAlarm` returns, and a process
/// death between that return and this insert still leaves an armed alarm no row
/// names. Moving the map here does not close that window — see
/// `AlarmKitScheduler.scheduleRing`.
///
/// [seq] orders the handles under one id, newest first when read descending: a
/// replacement whose predecessor refused to cancel leaves both live, and the
/// newest is what the id means now.
class AlarmKitHandles extends Table {
  IntColumn get alarmId => integer()();
  TextColumn get uuid => text()();
  IntColumn get seq => integer()();

  /// When this handle was recorded — the fence the prune compares against.
  ///
  /// Pruning asks AlarmKit what it still knows and deletes everything else, and
  /// that answer is a SNAPSHOT. Another isolate arming an alarm in the gap
  /// between the snapshot and the delete would have its brand-new handle read
  /// as "AlarmKit has forgotten this" and removed — orphaning an armed alarm,
  /// which is the exact failure the map exists to prevent. A handle recorded
  /// after the snapshot was taken is therefore never eligible: `scheduleRing`
  /// writes the row only once `scheduleOneShotAlarm` has returned, so anything
  /// recorded before the snapshot was already known to AlarmKit when it was
  /// asked.
  IntColumn get createdAt => integer().map(dateTimeMicros)();

  @override
  Set<Column<Object>> get primaryKey => {alarmId, uuid};
}

/// Where an outbox intent has got to. [dead] is a row that exhausted its
/// attempts: parked and logged rather than retried forever.
enum OutboxState { pending, processing, done, dead }

/// Intents that must survive a crash but **cannot** live inside a transaction,
/// because carrying them out means calling the platform.
///
/// A transaction covers the database; it does not cover AlarmKit or
/// AlarmManager. `_settlePending` writes history and then rolls on, and rolling
/// on arms a real alarm — wrap both in `BEGIN … COMMIT` and a rollback leaves
/// the alarm armed with no way to un-arm it. So the transaction records the
/// *intent* here and a dispatcher performs the platform call afterwards and
/// marks the row done.
///
/// [dedupKey] is what makes a retry safe to run twice: it is derived from the
/// occurrence, so a second settle of the same one finds the row already
/// [OutboxState.done] instead of rolling on again.
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get kind => text()();
  TextColumn get dedupKey => text().unique()();
  TextColumn get payload => text()();
  TextColumn get state => textEnum<OutboxState>()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get leasedUntil =>
      integer().nullable().map(nullableDateTimeMicros)();
  IntColumn get createdAt => integer().map(dateTimeMicros)();
  IntColumn get updatedAt => integer().map(dateTimeMicros)();
  TextColumn get lastError => text().nullable()();
}

/// The wind models this build asks Open-Meteo for, seeded from
/// `OpenMeteo.defaultWindModels` and **pruned when the service rejects one**.
///
/// It has to be a table rather than a constant because a retired name is a hard
/// 400 the app can only learn about by being refused ([OpenMeteoUnknownModel]).
/// The engine flags the named row and retries; the next launch reads the
/// shorter list rather than walking into the same wall.
///
/// **Additions ARE covered since 2026-08-30**, and they arrive for free: the
/// read inserts every default this table has never held, so an app update that
/// renames or adds a model picks it up on the next check. That was a deliberate
/// gap while pruning DELETED rows — there was no way to tell a name we had
/// never offered from one we had thrown away — and closing it is the same
/// change that makes a fully-pruned list stay pruned.
class WindModels extends Table {
  TextColumn get name => text()();
  IntColumn get position => integer()();

  /// **A rejected model is flagged, never deleted (2026-08-30).**
  ///
  /// Deleting it made an empty table mean two different things — "nobody has
  /// seeded this yet" and "every name we had was rejected" — and the seeding
  /// read cannot tell them apart, so a full sweep re-seeded the very names it
  /// had just thrown away. Keeping the row makes the two states distinct: a
  /// seeded table is never empty, so seeding is unambiguous, and a pruned name
  /// stays pruned.
  ///
  /// It also buys the way back. A name absent from this table ENTIRELY is one
  /// the app has never offered, so an app update that renames or adds a model
  /// gets it inserted on the next read — which is the only recovery a build
  /// with all seven names retired could have had anyway.
  BoolColumn get retired => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {name};
}

/// The latest wind verdict per alarm, for the home row's dot (N15).
///
/// Separate from [CheckStates] because that is per-OCCURRENCE and is cleared
/// the moment an occurrence finalises — the dot has to keep saying something
/// for tomorrow's alarm all day today. Written by whichever isolate ran the
/// check, including the background ones, so the foreground reads it back
/// rather than holding its own copy.
class AlarmForecastEntries extends Table {
  IntColumn get alarmId => integer()();

  /// The verdict, not a "will it ring" flag: the row's ⓘ names the reason a
  /// skip failed, and a bool cannot tell windy from gusty. See [AlarmForecast].
  TextColumn get verdict => textEnum<WindVerdict>()();

  /// When the CHECK ran — the app-clock moment the row is "as per", which is
  /// not the slot the reading describes. The row says "as per 16:00 check".
  IntColumn get checkedAt => integer().map(dateTimeMicros)();

  /// The reading behind the verdict, the limits it was judged against, and the
  /// slot it describes. Stored rather than derived at render time for the
  /// reason `HistoryEntries` keeps its own copies — see [AlarmForecast].
  ///
  /// Non-nullable: a row is only ever written from a real decision.
  RealColumn get courtSpeedKmh => real()();
  RealColumn get rawGustKmh => real()();
  IntColumn get courtSpeedLimitKmh => integer()();
  RealColumn get rawGustLimitKmh => real()();
  IntColumn get slotAt => integer().map(dateTimeMicros)();

  @override
  Set<Column<Object>> get primaryKey => {alarmId};
}

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'app_database.dart';
import 'tables.dart';

/// An intent to record now and carry out afterwards.
///
/// [dedupKey] is the whole idempotency story, so derive it from the thing the
/// intent is about — an occurrence, not a clock reading. Enqueueing the same
/// key twice is a no-op whatever state the first one reached, so a repeated
/// settle of one occurrence cannot roll it on twice.
class OutboxIntent {
  const OutboxIntent({
    required this.kind,
    required this.dedupKey,
    this.payload = const {},
  });

  final String kind;
  final String dedupKey;
  final Map<String, Object?> payload;
}

/// A claimed intent handed to a handler.
class OutboxJob {
  const OutboxJob({
    required this.id,
    required this.kind,
    required this.dedupKey,
    required this.payload,
    required this.attempts,
  });

  final int id;
  final String kind;
  final String dedupKey;
  final Map<String, Object?> payload;

  /// Including this one, so a handler can tell a first try from a retry.
  final int attempts;
}

/// Runs one [OutboxJob]. Throwing asks for a retry on a later barrier;
/// returning normally marks the row done.
typedef OutboxHandler = Future<void> Function(OutboxJob job);

/// Durable intents whose execution is a platform call.
///
/// **Why this exists at all.** A SQLite transaction covers the database and
/// stops there. `NivaatEngine._settlePending` writes history and then rolls on,
/// and rolling on arms a real alarm — put both in one transaction and a
/// rollback leaves that alarm armed with nothing able to un-arm it. So the
/// transaction that closes the occurrence also records the *intent* here, and
/// this dispatcher performs the platform call afterwards and marks it done.
/// Without that step a crash between the two still skips the next occurrence,
/// which is the one thing moving to a database was supposed to fix.
///
/// **What it does NOT buy is exactly-once scheduling, and nothing at this layer
/// can.** A transaction is exactly-once for rows. The alarm lives on the
/// platform, outside it: AlarmKit mints a UUID on every create and the process
/// can die between that create and any record of it, so an alarm the app cannot
/// name remains possible. This makes the intent durable and the retry safe —
/// at-least-once, converging. If a future reader finds "exactly once" written
/// about scheduling anywhere, it is wrong.
///
/// **The retry is safe because the platform calls converge, not because they
/// are idempotent.** Android's `Alarm.set` genuinely replaces per id. AlarmKit
/// does not — `scheduleOneShotAlarm` mints a fresh UUID every call — but
/// `AlarmKitScheduler.scheduleRing` already records the new handle and cancels
/// the one it superseded, and the int id a retry reuses is deterministic
/// (`block + alarmId`). So a second attempt lands on the same id and collapses
/// back to one alarm. This class does not need to carry the previous UUID; the
/// scheduler's own map is where that belongs.
class OutboxStore {
  /// Resolved per call so a test swapping the database in `setUp` is seen.
  AppDatabase get _db => appDb;

  /// How long a claim holds a row before another pass may take it.
  ///
  /// This is the crash window: a process that dies mid-handler leaves the row
  /// [OutboxState.processing], and nothing else may touch it until the lease
  /// runs out. Too short and two isolates run one handler concurrently; too
  /// long and a crashed roll-on waits that long for the next occurrence to
  /// be booked. Two minutes is inside Nivaat's 15-minute retry cadence.
  static const Duration lease = Duration(minutes: 2);

  /// How long a failed attempt waits before the next barrier may retake it.
  ///
  /// **Not zero, on purpose.** Retrying immediately spends every attempt in the
  /// same millisecond against exactly the conditions that just failed, which is
  /// a busy loop wearing a retry policy's clothes — the same rule
  /// `HostAlarmEventBridge` follows by deferring to the next barrier.
  static const Duration retryAfter = Duration(minutes: 1);

  /// Attempts before a row is parked as [OutboxState.dead] and logged rather
  /// than retried forever.
  static const int maxAttempts = 5;

  /// How long a finished row is kept.
  ///
  /// Kept rather than deleted because a [OutboxState.done] row IS the "already
  /// rolled on" record — [enqueue] on the same key finds it and does nothing.
  /// An occurrence is only re-settleable for so long, so the same seven days
  /// the host-event claims use.
  static const Duration doneTtl = Duration(days: 7);

  /// Records [intent] — a no-op if it is already owed or already carried out,
  /// and a **revival** if it was parked as [OutboxState.dead].
  ///
  /// Call it inside the transaction that makes the intent true, so there is no
  /// window where the state says the occurrence closed and nothing says what is
  /// owed.
  ///
  /// The three cases, and why they differ:
  ///
  /// - [OutboxState.done] — the work happened. Doing it again would be a second
  ///   roll, which is the whole reason the key is derived from the occurrence.
  /// - [OutboxState.pending] / [OutboxState.processing] — already owed, and
  ///   re-enqueueing would only reset a backoff or steal a live lease.
  /// - [OutboxState.dead] — **revived**, attempts reset. Parking is meant to
  ///   stop a broken handler being re-run on every barrier for the life of the
  ///   install, not to entomb the intent: nothing ever carried it out, and a
  ///   caller asserting it again in a fresh transaction is new information —
  ///   the occurrence is still open and still owes a roll. Without this a dead
  ///   row could never be claimed again (the dispatcher only ever looks at
  ///   `pending`/`processing`) and never re-enqueued, so `_rollOn` returned
  ///   false forever, the pending slot was held open forever, and every later
  ///   pass re-settled an occurrence that could never finish.
  ///
  /// Revival is not a busy loop: it costs one attempt per settle, which is the
  /// same per-barrier cadence [retryAfter] enforces inside a single run.
  Future<void> enqueue(OutboxIntent intent, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.outboxEntries)
            ..where((t) => t.dedupKey.equals(intent.dedupKey)))
          .getSingleOrNull();
      if (existing != null) {
        if (existing.state != OutboxState.dead) return;
        await (_db.update(_db.outboxEntries)
              ..where((t) => t.id.equals(existing.id)))
            .write(OutboxEntriesCompanion(
          state: const Value(OutboxState.pending),
          attempts: const Value(0),
          leasedUntil: const Value(null),
          updatedAt: Value(at),
        ));
        debugPrint('outbox: ${intent.kind} ${intent.dedupKey} was parked and '
            'has been re-asserted — retrying it');
        return;
      }
      await _db.into(_db.outboxEntries).insert(OutboxEntriesCompanion(
            kind: Value(intent.kind),
            dedupKey: Value(intent.dedupKey),
            payload: Value(jsonEncode(intent.payload)),
            state: const Value(OutboxState.pending),
            createdAt: Value(at),
            updatedAt: Value(at),
          ));
    });
  }

  /// Where [dedupKey] has got to, or null if it was never recorded.
  Future<OutboxState?> stateOf(String dedupKey) async {
    final row = await (_db.select(_db.outboxEntries)
          ..where((t) => t.dedupKey.equals(dedupKey)))
        .getSingleOrNull();
    return row?.state;
  }

  /// Claims and runs what is currently owed.
  ///
  /// Either isolate may call this and it must be safe for one to do all the
  /// work alone — which is why eligibility is a `WHERE` clause over persisted
  /// state rather than anything held in memory.
  ///
  /// **[only] scopes a call to a single [OutboxIntent.dedupKey], and the caller
  /// that just enqueued one should always use it.** An unscoped dispatch runs
  /// every owed row, and a caller mid-way through one alarm's work would then
  /// carry out another alarm's intent inside that alarm's lane — breaking the
  /// serialisation the engine relies on. Unscoped is for a barrier, where there
  /// is no lane to break.
  ///
  /// **Re-entrancy needs no flag.** A handler that reaches this again cannot
  /// take the row it is already running: claiming leases it, and a leased row
  /// is not eligible. That is the same mechanism that stops a second isolate,
  /// so there is only one rule to trust rather than two.
  ///
  /// Never throws: a handler that fails costs its own row and nothing else, the
  /// same rule the host-event drain follows. A batch that aborted on the first
  /// throw would be the net taking down what it protects.
  Future<void> dispatch(
    Map<String, OutboxHandler> handlers, {
    DateTime? now,
    String? only,
  }) async {
    final at = now ?? DateTime.now();
    for (final job in await _claim(at, only: only)) {
      final handler = handlers[job.kind];
      if (handler == null) {
        // An intent nobody can carry out is a bug, not a transient fault: park
        // it rather than spending five attempts discovering the same thing.
        // Reachable if a kind is renamed while rows are still in flight.
        await _finish(job, OutboxState.dead,
            at: at, error: 'no handler for "${job.kind}"');
        debugPrint('outbox: no handler for "${job.kind}" (${job.dedupKey})');
        continue;
      }
      try {
        await handler(job);
        await _finish(job, OutboxState.done, at: at);
      } on Exception catch (e, st) {
        if (job.attempts >= maxAttempts) {
          await _finish(job, OutboxState.dead, at: at, error: '$e');
          debugPrint('outbox: ${job.kind} ${job.dedupKey} failed '
              '$maxAttempts times, parking it: $e\n$st');
        } else {
          await _release(job, at: at, error: '$e');
          debugPrint('outbox: ${job.kind} ${job.dedupKey} failed '
              '(attempt ${job.attempts}, retrying on a later barrier): $e');
        }
      }
    }
  }

  /// Takes ownership of every eligible row in one transaction, so two isolates
  /// cannot both claim the same one.
  ///
  /// Eligible means owed and not currently leased: a [OutboxState.pending] row
  /// whose backoff has passed, or a [OutboxState.processing] row whose lease
  /// expired — that second half is the crash recovery, and without it a process
  /// that died mid-handler would strand the intent forever.
  Future<List<OutboxJob>> _claim(DateTime at, {String? only}) =>
      _db.transaction(() async {
        // Compared as raw microseconds, not as a `DateTime`: a type converter
        // only maps through `equalsValue`, and every ordering comparison on a
        // converted column is against its SQL type. Getting this wrong does not
        // fail to compile — `Expression<int>` happily takes an int — it just
        // never matches, so a lease would never expire.
        final micros = at.microsecondsSinceEpoch;
        final query = _db.select(_db.outboxEntries)
          ..where((t) =>
              (t.state.equalsValue(OutboxState.pending) &
                  (t.leasedUntil.isNull() |
                      t.leasedUntil.isSmallerOrEqualValue(micros))) |
              (t.state.equalsValue(OutboxState.processing) &
                  t.leasedUntil.isSmallerOrEqualValue(micros)))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]);
        if (only != null) query.where((t) => t.dedupKey.equals(only));
        final rows = await query.get();
        final jobs = <OutboxJob>[];
        for (final row in rows) {
          await (_db.update(_db.outboxEntries)
                ..where((t) => t.id.equals(row.id)))
              .write(OutboxEntriesCompanion(
            state: const Value(OutboxState.processing),
            attempts: Value(row.attempts + 1),
            leasedUntil: Value(at.add(lease)),
            updatedAt: Value(at),
          ));
          jobs.add(OutboxJob(
            id: row.id,
            kind: row.kind,
            dedupKey: row.dedupKey,
            payload:
                (jsonDecode(row.payload) as Map<String, dynamic>).cast(),
            attempts: row.attempts + 1,
          ));
        }
        return jobs;
      });

  /// **A worker may only settle the claim it still holds** — `attempts` is the
  /// fencing token, and matching on [OutboxEntries.id] alone was a bug.
  ///
  /// A handler can outlive its own lease: the row is then retaken by the next
  /// barrier, which bumps `attempts`. The slow worker eventually returns and
  /// writes its verdict — and with only the id in the `WHERE`, that verdict
  /// lands on top of its successor's live claim. Marking `done` there retires an
  /// intent the successor is still carrying out, and if the successor's own
  /// arming then fails the roll is lost with nothing owed. `attempts` only ever
  /// climbs, so a stale worker's number no longer matches and its write is a
  /// no-op — which is exactly what a worker that lost its lease should be.
  Future<void> _finish(OutboxJob job, OutboxState state,
          {required DateTime at, String? error}) =>
      (_db.update(_db.outboxEntries)
            ..where((t) => t.id.equals(job.id) & t.attempts.equals(job.attempts)))
          .write(OutboxEntriesCompanion(
        state: Value(state),
        leasedUntil: const Value(null),
        updatedAt: Value(at),
        lastError: Value(error),
      ));

  Future<void> _release(OutboxJob job,
          {required DateTime at, required String error}) =>
      (_db.update(_db.outboxEntries)
            ..where((t) => t.id.equals(job.id) & t.attempts.equals(job.attempts)))
          .write(OutboxEntriesCompanion(
        state: const Value(OutboxState.pending),
        leasedUntil: Value(at.add(retryAfter)),
        updatedAt: Value(at),
        lastError: Value(error),
      ));

  /// Settles [job] exactly as the dispatcher would, for tests that need to
  /// stage a stale worker returning after its lease expired — the one
  /// interleaving no single-threaded test can reach on its own.
  @visibleForTesting
  Future<void> settleForTesting(OutboxJob job, OutboxState state,
          {required DateTime at}) =>
      _finish(job, state, at: at);

  /// Drops finished rows past [doneTtl]. [OutboxState.dead] rows stay: they are
  /// the record of an intent that never happened, and deleting them would erase
  /// the only trace of an occurrence that was never booked.
  Future<void> prune({DateTime? now}) async {
    final cutoff =
        (now ?? DateTime.now()).subtract(doneTtl).microsecondsSinceEpoch;
    await (_db.delete(_db.outboxEntries)
          ..where((t) =>
              t.state.equalsValue(OutboxState.done) &
              t.updatedAt.isSmallerThanValue(cutoff)))
        .go();
  }
}

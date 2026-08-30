import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import 'db/app_database.dart';
import 'db/tables.dart';

/// Why the host changed an alarm without the app asking.
///
/// Mirrors `alarm`'s `AlarmEventCause` so apps never import the plugin type.
enum HostAlarmEventCause {
  snooze,
  platformRefusal,
  staleAtBoot,
}

/// What the host did.
enum HostAlarmEventKind { moved, dropped }

/// A host-side change to a plugin alarm, delivered **at least once**.
///
/// Key every irreversible side effect on `(id, recordedAt)`. **The reason
/// changed with the move to SQLite (2026-08-12) and the requirement did not.**
/// It used to be that SharedPreferences could not compare-and-swap, so two
/// isolates could both run one handler; [HostAlarmEventClaims] is a real lock
/// now. What survives is that the lease bounds how long a claim is RESPECTED,
/// not how long a handler runs — a handler that outlives its own lease is
/// legitimately taken over by the next barrier — and that a handler which ran
/// but was not yet marked done is deliberately re-run rather than dropped.
/// Idempotent on that pair is the contract, not a nicety.
class HostAlarmEvent {
  const HostAlarmEvent({
    required this.id,
    required this.kind,
    required this.cause,
    required this.recordedAt,
    required this.at,
    this.acknowledge,
  });

  final int id;
  final HostAlarmEventKind kind;
  final HostAlarmEventCause cause;

  /// When the host recorded this (unique with [id] for idempotency).
  final DateTime recordedAt;

  /// For [HostAlarmEventKind.moved]: when it rings now.
  /// For [HostAlarmEventKind.dropped]: when it should have rung.
  final DateTime at;

  /// Releases the host's durable marker for this event, or null when the
  /// source has none — a test fake, and iOS, where AlarmKit records nothing.
  ///
  /// **Called only once this isolate is durably finished with the event**,
  /// which is the whole manual boundary. The plugin's default cleared it at
  /// the emit, so the only copy lived in memory from `Alarm.init()` until
  /// [HostAlarmEventClaims.complete] — the wind fetch included — and nothing
  /// re-drives a claim row that no event ever arrives for again.
  final Future<void> Function()? acknowledge;

  String get claimKey => hostAlarmEventClaimKey(id, recordedAt);
}

String hostAlarmEventClaimKey(int id, DateTime recordedAt) =>
    'hostAlarmEvent.$id.${recordedAt.millisecondsSinceEpoch}';

/// A claim taken out on one event, and the attempt number it is.
class HostAlarmEventClaim {
  const HostAlarmEventClaim({required this.attempts});

  /// Including this one, and **counted on disk** rather than in memory: a
  /// process that dies retrying gets a fourth go at an event it has already
  /// failed three times, which is how a deterministically-broken handler used
  /// to keep its budget refilled by every restart.
  final int attempts;
}

/// Who is handling `(id, recordedAt)`, and how far it got.
///
/// **This is the compare-and-swap SharedPreferences could never give.** The
/// prefs version was a bool that could only say "done", so two isolates could
/// both read absent and both run the handler, and convergence had to live in
/// the handlers. A row with a state and a lease makes taking responsibility one
/// atomic statement.
///
/// **A single-statement `INSERT … ON CONFLICT DO NOTHING` would not have been
/// enough, and that is why there is a state rather than a flag.** Inserting a
/// "handled" row and then running the handler is the prefs bug from the other
/// side: the row says handled while the handler has not run, and a process
/// death in between makes the event permanently invisible — the plugin
/// acknowledged it natively long ago, so nothing will redeliver it. So [begin]
/// writes [HostEventClaimState.processing] with a lease, [complete] writes
/// `done`, and a `processing` row whose lease has expired is taken over by the
/// next barrier. Re-running a handler is safe; losing one is not.
///
/// Every handler must still be idempotent on `(id, recordedAt)` — Nivaat
/// matches `hostEventKey` in its own history before writing. The lease makes
/// concurrent double-handling rare; it does not make it impossible, because a
/// handler can outlive its own lease.
class HostAlarmEventClaims {
  /// Resolved per call so a test swapping the database in `setUp` is seen.
  AppDatabase get _db => appDb;

  /// Rows older than this are swept on [prune]. A host event is only
  /// actionable for the occurrence it belongs to — the plugin's own markers are
  /// capped the same way — and without a ceiling these accumulate for the life
  /// of the install.
  static const Duration keyTtl = Duration(days: 7);

  /// How long a [begin] holds an event before another pass may take it over.
  ///
  /// This is the crash window: too short and two isolates run one handler at
  /// once, too long and an event a dead process was holding waits that long to
  /// be retried. A handler here is a wind fetch plus a few writes.
  static const Duration lease = Duration(minutes: 2);

  /// True once [event] has been **applied** — not merely attempted.
  ///
  /// [HostEventClaimState.abandoned] reads false on purpose: an event whose
  /// handler ran out of attempts was never applied, and calling that "claimed"
  /// would hide a dropped ring behind a row that says it was dealt with.
  Future<bool> isClaimed(HostAlarmEvent event) async {
    final row = await _row(event);
    return row?.state == HostEventClaimState.done;
  }

  /// True once [event] is settled **terminally** — applied, or given up on.
  ///
  /// The question [begin]'s null cannot answer: it also means "another holder
  /// has a live lease", and releasing the host's marker under one would throw
  /// away the only thing that holder could be recovered from. Counts
  /// [HostEventClaimState.abandoned], unlike [isClaimed] — the question is not
  /// "was it applied" but "will anyone try again".
  Future<bool> isSettled(HostAlarmEvent event) async {
    final state = (await _row(event))?.state;
    return state == HostEventClaimState.done ||
        state == HostEventClaimState.abandoned;
  }

  /// Takes responsibility for [event], or returns null when there is nothing
  /// to do — it is already applied, already abandoned, or someone else holds a
  /// live lease on it.
  ///
  /// One transaction, so two isolates asking at once cannot both be told yes.
  Future<HostAlarmEventClaim?> begin(
    HostAlarmEvent event, {
    DateTime? now,
  }) =>
      _db.transaction(() async {
        final at = now ?? DateTime.now();
        final row = await _row(event);
        if (row != null) {
          switch (row.state) {
            case HostEventClaimState.done:
            case HostEventClaimState.abandoned:
              return null;
            case HostEventClaimState.processing:
              final held = row.leasedUntil;
              if (held != null && held.isAfter(at)) return null;
            case HostEventClaimState.pending:
              break;
          }
        }
        final attempts = (row?.attempts ?? 0) + 1;
        await _db.into(_db.hostEventClaims).insertOnConflictUpdate(
              HostEventClaimsCompanion(
                claimKey: Value(event.claimKey),
                state: const Value(HostEventClaimState.processing),
                attempts: Value(attempts),
                leasedUntil: Value(at.add(lease)),
                recordedAt: Value(event.recordedAt),
                updatedAt: Value(at),
              ),
            );
        return HostAlarmEventClaim(attempts: attempts);
      });

  /// Marks [event] applied. Call only after the handler has succeeded, and
  /// pass the [claim] [begin] handed back.
  Future<bool> complete(HostAlarmEvent event, HostAlarmEventClaim claim,
          {DateTime? now}) =>
      _settle(event, claim, HostEventClaimState.done, now: now);

  /// Hands [event] back for a later barrier — a handler that failed but has
  /// attempts left. The attempt count stays where it is, so the budget survives
  /// a restart.
  Future<bool> release(HostAlarmEvent event, HostAlarmEventClaim claim,
          {DateTime? now}) =>
      _settle(event, claim, HostEventClaimState.pending, now: now);

  /// Parks [event] for good: its handler failed its last attempt.
  ///
  /// Terminal so a deterministically-failing handler stops being re-run on
  /// every barrier for the life of the install, and distinct from [complete]
  /// so nothing can mistake it for an event that was actually applied.
  Future<bool> abandon(HostAlarmEvent event, HostAlarmEventClaim claim,
          {DateTime? now}) =>
      _settle(event, claim, HostEventClaimState.abandoned, now: now);

  /// **Only the holder of the current claim may settle it** — `attempts` is the
  /// fencing token, and matching on [claimKey] alone was a bug.
  ///
  /// The lease bounds how long a claim is respected, not how long a handler
  /// runs, so a slow worker can still be inside its handler when the next
  /// barrier retakes the event and bumps `attempts`. When that worker returns
  /// and writes its verdict, a `claimKey`-only `WHERE` lands it on top of the
  /// successor's live claim: `release` re-opens an event someone is actively
  /// handling, and `abandon` parks one that has already been applied — leaving a
  /// row that says a dropped ring was never dealt with when it was, or the
  /// reverse. `attempts` only ever climbs, so a stale worker's write matches
  /// nothing and is correctly a no-op.
  /// Returns whether the write landed; false means this holder was overtaken.
  /// **A caller with a side effect outside the database must check it** — the
  /// bridge's marker release is one, and doing it on an overtaken settle hands
  /// the successor a claim nothing can recover.
  Future<bool> _settle(
    HostAlarmEvent event,
    HostAlarmEventClaim claim,
    HostEventClaimState state, {
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final rows = await (_db.update(_db.hostEventClaims)
          ..where((t) =>
              t.claimKey.equals(event.claimKey) &
              t.attempts.equals(claim.attempts)))
        .write(HostEventClaimsCompanion(
      state: Value(state),
      leasedUntil: const Value(null),
      updatedAt: Value(at),
    ));
    return rows > 0;
  }

  Future<HostEventClaim?> _row(HostAlarmEvent event) =>
      (_db.select(_db.hostEventClaims)
            ..where((t) => t.claimKey.equals(event.claimKey)))
          .getSingleOrNull();

  /// Drops rows whose event is older than [keyTtl].
  ///
  /// Swept on `recordedAt` — the event's own instant, which is also what the
  /// key encodes — so a row that has sat [HostEventClaimState.pending] for a
  /// week goes too. That is deliberate: an event nothing managed to apply in
  /// seven days is about an occurrence long past.
  Future<void> prune({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now())
        .subtract(keyTtl)
        .microsecondsSinceEpoch;
    await (_db.delete(_db.hostEventClaims)
          ..where((t) => t.recordedAt.isSmallerThanValue(cutoff)))
        .go();
  }
}

/// Thrown by a handler that could not yet act on an event, to ask for it back
/// on the next barrier instead of having it marked handled.
///
/// An `Exception`, not an `Error`, and that is load-bearing: the bridge defers
/// on `Exception` only, so an `Error` here would be lost rather than retried.
class HostAlarmEventNotReady implements Exception {
  const HostAlarmEventNotReady(this.reason);

  final String reason;

  @override
  String toString() => 'HostAlarmEventNotReady: $reason';
}

/// Source of host events — production wraps `Alarm.events`; tests inject fakes.
typedef HostAlarmEventSource = Stream<HostAlarmEvent> Function();

/// Serialised host-event drain for one isolate.
///
/// [apply] awaits every handler. **Listening alone is never a barrier** — a
/// subscription only guarantees the events will arrive, not that anything has
/// acted on them, and every caller here is about to make a decision that
/// depends on having acted.
class HostAlarmEventBridge {
  HostAlarmEventBridge({
    required HostAlarmEventSource events,
    required HostAlarmEventClaims claims,
    Future<void> Function()? ensurePluginReady,
  })  : _events = events,
        _claims = claims,
        _ensurePluginReady = ensurePluginReady;

  final HostAlarmEventSource _events;
  final HostAlarmEventClaims _claims;
  final Future<void> Function()? _ensurePluginReady;

  Future<void> Function(HostAlarmEvent event)? _handler;
  StreamSubscription<HostAlarmEvent>? _sub;
  final List<HostAlarmEvent> _queue = [];
  Completer<void>? _drain;

  /// The in-flight [start], so concurrent callers share one attempt. Cleared
  /// when it settles — including when it FAILS, which is the whole point: a
  /// plugin hiccup during the first `Alarm.init()` used to latch a `_started`
  /// flag that was never true, and every later drain then returned instantly
  /// having subscribed to nothing.
  Future<void>? _starting;
  bool _listening = false;

  /// How many times one event's handler may fail before it is abandoned.
  /// Bounded because a handler that throws deterministically would otherwise
  /// re-run on every barrier for the life of the process.
  ///
  /// **The count lives in the claims table, not here.** It used to be an
  /// in-memory map, which meant a restart handed a permanently-broken handler
  /// a fresh budget — the ceiling only ever bounded one process's patience.
  static const int maxHandlerAttempts = 3;

  /// Events whose handler failed, waiting for the NEXT barrier.
  ///
  /// Deliberately not re-queued into the current flush: retrying three times
  /// inside one drain spends every attempt in the same millisecond, against
  /// exactly the conditions that just failed. A transient fault — a prefs write
  /// losing a race, a plugin call refused while the process is still coming
  /// up — needs the next evaluate pass, not the next microtask. One attempt per
  /// barrier is the whole difference between a retry policy and a busy loop.
  final List<HostAlarmEvent> _deferred = [];

  /// >0 while a handler is running on this isolate — [apply] must not await
  /// the outer [_drain] Completer (that would deadlock when evaluate re-drains
  /// mid-handler after a wind fetch).
  int _handlerDepth = 0;

  HostAlarmEventClaims get claims => _claims;

  void setHandler(Future<void> Function(HostAlarmEvent event)? handler) {
    _handler = handler;
  }

  /// Start listening (replay buffer + live). Does not await handlers — call
  /// [apply] for that.
  ///
  /// Safe to call again after a failure: nothing is latched until the
  /// subscription actually exists.
  Future<void> start() {
    if (_listening) return Future<void>.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    final ready = _ensurePluginReady;
    if (ready != null) await ready();
    _sub = _events().listen(_onEvent, onError: (Object e, StackTrace st) {
      debugPrint('host alarm event stream error: $e\n$st');
    });
    _listening = true;
    // Housekeeping, not correctness — never let a failure here cost the drain.
    try {
      await _claims.prune();
    } on Exception catch (e) {
      debugPrint('host alarm event claim prune failed (non-fatal): $e');
    }
  }

  void _onEvent(HostAlarmEvent event) {
    _queue.add(event);
    _kickDrain();
  }

  /// Runs [event]'s handler exactly once per `(id, recordedAt)` that succeeds.
  ///
  /// Never throws: a failure here must cost that ONE event, because the caller
  /// is draining a batch and the alternative is the net taking down what it
  /// protects — the same rule `NivaatEngine._sweepOrphanRings` guards each
  /// cancel with (CLAUDE.md). A failed event keeps its place in the queue for
  /// up to [maxHandlerAttempts] barriers and is never marked handled, so the
  /// next `apply` retries it rather than losing it silently.
  Future<void> _runHandler(HostAlarmEvent event) async {
    final handler = _handler;
    if (handler == null) return;
    _handlerDepth++;
    try {
      // Takes the claim BEFORE the handler and only completes it after, which
      // is the pair the old bool could not express: claiming first alone loses
      // the event to a crash, marking done afterwards alone lets two isolates
      // both run it. See [HostAlarmEventClaims].
      final claim = await _claims.begin(event);
      if (claim == null) {
        // Finished with by someone else, so the marker is ours to release.
        // A live lease reads false and keeps it — the safe way for the race
        // between these two reads to land.
        if (await _claims.isSettled(event)) await _acknowledge(event);
        return;
      }
      try {
        await handler(event);
      } on Exception catch (e, st) {
        if (claim.attempts < maxHandlerAttempts) {
          await _claims.release(event, claim);
          debugPrint('host alarm event handler failed for ${event.id} '
              '(attempt ${claim.attempts}, will retry on the next barrier): $e');
          _deferred.add(event);
        } else {
          // Terminal: keeping the marker would redeliver a permanently
          // broken handler's event on every init until the host expired it.
          // Fenced on the settle landing, for the reason below.
          if (await _claims.abandon(event, claim)) await _acknowledge(event);
          debugPrint('host alarm event handler failed for ${event.id} '
              '$maxHandlerAttempts times, giving up: $e\n$st');
        }
        return;
      } catch (_) {
        // A programming Error is not this event's fault and must not spend its
        // budget; hand the claim back so the rethrow below reaches [apply] with
        // the event still retryable.
        await _claims.release(event, claim);
        rethrow;
      }
      // Durably `done`, so a death after this costs a redelivery — which the
      // null-claim branch above then releases — rather than the event. **And
      // only if the settle LANDED:** a lease bounds how long a claim is
      // RESPECTED, not how long a handler runs, so a worker overtaken inside
      // its handler writes a correct no-op here, while releasing the marker
      // would not be one and would leave its successor unrecoverable. The
      // fence has to reach the side effect, not just the row.
      if (await _claims.complete(event, claim)) await _acknowledge(event);
    } finally {
      _handlerDepth--;
    }
  }

  /// Releases the host's marker for [event], and never throws: a failed
  /// release costs one redelivery that the claim row turns into a no-op, where
  /// letting it escape would unwind [_runHandler] *after* the claim was
  /// already settled.
  Future<void> _acknowledge(HostAlarmEvent event) async {
    final ack = event.acknowledge;
    if (ack == null) return;
    try {
      await ack();
    } on Object catch (e) {
      debugPrint('host alarm event acknowledgement failed for ${event.id} '
          '(harmless: it will be redelivered and acknowledged again): $e');
    }
  }

  Future<void> _flushQueue() async {
    while (_queue.isNotEmpty) {
      final next = List<HostAlarmEvent>.from(_queue);
      _queue.clear();
      for (final event in next) {
        await _runHandler(event);
      }
    }
  }

  /// A programming `Error` that escaped a handler, held until [apply] can
  /// rethrow it.
  ///
  /// Errors are not caught by [_runHandler] on purpose — this repo's policy is
  /// that an `Exception` soft-fails and an `Error` propagates, because the
  /// second is a bug and should be loud. But the drain runs in a detached
  /// microtask, so "propagates" meant "becomes an unhandled zone error while
  /// `apply()` returns normally" — the batch eaten, the caller told nothing,
  /// and the noise landing somewhere nobody is looking. Holding it here sends
  /// it out through the barrier the caller actually awaits.
  Object? _drainError;
  StackTrace? _drainStack;

  void _kickDrain() {
    if (_drain != null) return;
    _drain = Completer<void>();
    scheduleMicrotask(() async {
      try {
        await _flushQueue();
      } catch (e, st) {
        _drainError ??= e;
        _drainStack ??= st;
      } finally {
        final done = _drain;
        _drain = null;
        done?.complete();
        if (_queue.isNotEmpty) _kickDrain();
      }
    });
  }

  /// Await every queued / in-flight handler. Call before evaluate / arm /
  /// cancel / orphan sweep.
  Future<void> apply() async {
    await start();
    // Anything that failed on an earlier barrier gets exactly one more go now.
    if (_deferred.isNotEmpty) {
      _queue.addAll(_deferred);
      _deferred.clear();
      _kickDrain();
    }
    // `Alarm.events` is a ReplaySubject: subscribing hands over its buffer,
    // but through the stream's own event loop rather than synchronously. Yield
    // a full timer turn (not a microtask — the delivery hop is not one) so
    // those land in [_queue] before we decide there is nothing to wait for.
    await Future<void>.delayed(Duration.zero);
    if (_handlerDepth > 0) {
      // Re-entrant (evaluate after wind fetch while settling a host event):
      // flush newly queued events inline — never await the outer drain.
      await _flushQueue();
      _rethrowDrainError();
      return;
    }
    while (_drain != null || _queue.isNotEmpty) {
      final inFlight = _drain;
      if (inFlight != null) {
        await inFlight.future;
      } else if (_queue.isNotEmpty) {
        _kickDrain();
      }
      await Future<void>.delayed(Duration.zero);
    }
    _rethrowDrainError();
  }

  /// Surfaces an `Error` the drain swallowed, once, to whoever is waiting.
  void _rethrowDrainError() {
    final e = _drainError;
    if (e == null) return;
    final st = _drainStack;
    _drainError = null;
    _drainStack = null;
    Error.throwWithStackTrace(e, st ?? StackTrace.current);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _listening = false;
    _deferred.clear();
    _drainError = null;
    _drainStack = null;
  }
}

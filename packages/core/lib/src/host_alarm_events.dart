import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
/// Key every irreversible side effect on `(id, recordedAt)`: SharedPreferences
/// cannot compare-and-swap, so a second isolate may run the same handler, and
/// a handler that ran but had not yet been marked done is deliberately re-run
/// rather than dropped (see [HostAlarmEventClaims]). Idempotent on that pair
/// is the contract, not a nicety.
class HostAlarmEvent {
  const HostAlarmEvent({
    required this.id,
    required this.kind,
    required this.cause,
    required this.recordedAt,
    required this.at,
  });

  final int id;
  final HostAlarmEventKind kind;
  final HostAlarmEventCause cause;

  /// When the host recorded this (unique with [id] for idempotency).
  final DateTime recordedAt;

  /// For [HostAlarmEventKind.moved]: when it rings now.
  /// For [HostAlarmEventKind.dropped]: when it should have rung.
  final DateTime at;

  String get claimKey => hostAlarmEventClaimKey(id, recordedAt);
}

String hostAlarmEventClaimKey(int id, DateTime recordedAt) =>
    'hostAlarmEvent.$id.${recordedAt.millisecondsSinceEpoch}';

/// Persist that we have **finished** handling `(id, recordedAt)`.
///
/// **The mark goes down after the handler, never before.** Claiming first
/// looks safer and is not: a process death between the claim and the handler
/// leaves the event marked done and never applied, and the plugin has already
/// acknowledged it natively, so nothing will ever redeliver it — a dropped
/// ring that no history row explains. Marking afterwards costs the mirror
/// image, a second delivery of an event that already landed, and that one is
/// harmless because every handler here is idempotent on `(id, recordedAt)`
/// (Nivaat matches `hostEventKey` in its own history before writing).
///
/// **This is not a lock and cannot be made one.** SharedPreferences has no
/// compare-and-swap, so two isolates can both read "absent" and both run.
/// Convergence lives in the handlers, exactly as it does for history rows
/// (CLAUDE.md, REVIEW #7) — this store only keeps the common case cheap.
class HostAlarmEventClaims {
  HostAlarmEventClaims({
    Future<SharedPreferences> Function()? prefs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefs;

  /// Keys older than this are swept on [prune]. A host event is only
  /// actionable for the morning it belongs to — the plugin's own markers are
  /// capped the same way — and without a ceiling these bools accumulate in the
  /// app's prefs blob for the life of the install.
  static const Duration keyTtl = Duration(days: 7);

  static const String keyPrefix = 'hostAlarmEvent.';

  Future<bool> isClaimed(HostAlarmEvent event) async {
    final prefs = await _prefs();
    await prefs.reload();
    return prefs.containsKey(event.claimKey);
  }

  /// Marks [event] handled. Call only after the handler has succeeded.
  Future<void> claim(HostAlarmEvent event) async {
    final prefs = await _prefs();
    await prefs.reload();
    await prefs.setBool(event.claimKey, true);
  }

  /// Removes the mark — for a handler that has since been undone.
  Future<void> unclaim(HostAlarmEvent event) async {
    final prefs = await _prefs();
    await prefs.reload();
    await prefs.remove(event.claimKey);
  }

  /// Drops claim keys older than [keyTtl], read back out of the key itself
  /// (`hostAlarmEvent.<id>.<recordedAtMillis>`) so no second record is needed.
  Future<void> prune({DateTime? now}) async {
    final prefs = await _prefs();
    await prefs.reload();
    final cutoff = (now ?? DateTime.now()).subtract(keyTtl);
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(keyPrefix)) continue;
      final millis = int.tryParse(key.split('.').last);
      if (millis == null) continue;
      if (DateTime.fromMillisecondsSinceEpoch(millis).isBefore(cutoff)) {
        await prefs.remove(key);
      }
    }
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
  static const int maxHandlerAttempts = 3;
  final Map<String, int> _attempts = {};

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
      if (await _claims.isClaimed(event)) return;
      await handler(event);
      // AFTER the handler, never before — see [HostAlarmEventClaims].
      await _claims.claim(event);
      _attempts.remove(event.claimKey);
    } on Exception catch (e, st) {
      final tries = (_attempts[event.claimKey] ?? 0) + 1;
      _attempts[event.claimKey] = tries;
      if (tries < maxHandlerAttempts) {
        debugPrint('host alarm event handler failed for ${event.id} '
            '(attempt $tries, will retry on the next barrier): $e');
        _deferred.add(event);
      } else {
        _attempts.remove(event.claimKey);
        debugPrint('host alarm event handler failed for ${event.id} '
            '$maxHandlerAttempts times, giving up: $e\n$st');
      }
    } finally {
      _handlerDepth--;
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
    _attempts.clear();
    _deferred.clear();
    _drainError = null;
    _drainStack = null;
  }
}

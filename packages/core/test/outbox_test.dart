import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// The outbox is the seam between a transaction and a platform call.
///
/// A transaction covers the database and stops there: an alarm armed inside one
/// stays armed through a `ROLLBACK`. So the transaction records the intent and a
/// dispatcher carries it out afterwards — which only works if the row survives
/// the process that was holding it, cannot be run twice for one occurrence, and
/// stops being retried eventually. These lock those three.
void main() {
  late OutboxStore outbox;

  setUp(() {
    outbox = OutboxStore();
  });

  const intent = OutboxIntent(
    kind: 'rollOn',
    dedupKey: 'rollOn:7:123',
    payload: {'alarmId': 7},
  );

  /// A handler that records what it was given, and optionally fails.
  ({List<OutboxJob> ran, Map<String, OutboxHandler> map}) handler({
    Object? throws,
    int failFirst = 0,
  }) {
    final ran = <OutboxJob>[];
    return (
      ran: ran,
      map: {
        'rollOn': (job) async {
          ran.add(job);
          if (throws != null && ran.length <= (failFirst == 0 ? 1 << 30 : failFirst)) {
            throw throws;
          }
        },
      },
    );
  }

  test('an intent is carried out once and marked done', () async {
    final h = handler();
    await outbox.enqueue(intent);
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.pending);

    await outbox.dispatch(h.map);

    expect(h.ran, hasLength(1));
    expect(h.ran.single.payload['alarmId'], 7);
    expect(h.ran.single.attempts, 1);
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.done);

    // The barrier runs again and finds nothing owed.
    await outbox.dispatch(h.map);
    expect(h.ran, hasLength(1));
  });

  test('re-enqueueing a finished intent does not run it again', () async {
    // The idempotency the whole design rests on. Host events arrive at least
    // once and two isolates can both be told, so an occurrence gets settled
    // more than once as a matter of course — and each settle enqueues. Keyed by
    // occurrence, so the second one finds the roll already recorded.
    final h = handler();
    await outbox.enqueue(intent);
    await outbox.dispatch(h.map);
    await outbox.enqueue(intent);
    await outbox.dispatch(h.map);

    expect(h.ran, hasLength(1));
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.done);
  });

  test('a row whose holder died is retaken once the lease expires', () async {
    // The crash recovery, and the reason this is a state machine rather than a
    // queue. A process that dies mid-handler leaves the row `processing`;
    // nothing may touch it until the lease runs out, and then the next barrier
    // must pick it up rather than leaving the intent stranded for good.
    final t = DateTime(2026, 8, 12, 6);
    var died = true;
    final ran = <int>[];
    final handlers = <String, OutboxHandler>{
      'rollOn': (job) async {
        ran.add(job.attempts);
        // Model the process dying inside the handler: the row stays leased,
        // because nothing ever gets to release it.
        if (died) await Future<Never>.delayed(Duration.zero, () => throw _Died());
      },
    };
    await outbox.enqueue(intent, now: t);

    // The holder dies. `_Died` is an Error, so it escapes the dispatcher the
    // way a real crash escapes everything — the row is left `processing`.
    await expectLater(outbox.dispatch(handlers, now: t), throwsA(isA<_Died>()));
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.processing);

    // Inside the lease, another pass must NOT take it: that is what stops two
    // isolates arming the same occurrence twice.
    await outbox.dispatch(handlers,
        now: t.add(OutboxStore.lease - const Duration(seconds: 1)));
    expect(ran, [1]);

    died = false;
    await outbox.dispatch(handlers,
        now: t.add(OutboxStore.lease + const Duration(seconds: 1)));
    expect(ran, [1, 2], reason: 'the expired lease is reclaimed');
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.done);
  });

  test('a worker that lost its lease cannot settle its successor\'s claim',
      () async {
    // The fencing token. A lease bounds how long a claim is RESPECTED, not how
    // long a handler runs, so a slow worker can still be inside its handler
    // when the next barrier retakes the row. Its verdict must then land on
    // nothing: marking `done` there would retire an intent the successor is
    // still carrying out, and if the successor's own arming failed the roll
    // would be lost with nothing left saying it was owed.
    final t = DateTime(2026, 8, 12, 6);
    final claimed = <OutboxJob>[];
    final handlers = <String, OutboxHandler>{
      // Captures the job and returns without settling, so the test can settle
      // it by hand at the wrong moment — which is what a slow worker does.
      'rollOn': (job) async {
        claimed.add(job);
        throw _Held();
      },
    };
    await outbox.enqueue(intent, now: t);
    await expectLater(outbox.dispatch(handlers, now: t), throwsA(isA<_Held>()));
    final stale = claimed.single;
    expect(stale.attempts, 1);

    // The lease expires and a second pass takes it over.
    final later = t.add(OutboxStore.lease + const Duration(seconds: 1));
    await expectLater(
        outbox.dispatch(handlers, now: later), throwsA(isA<_Held>()));
    expect(claimed.last.attempts, 2, reason: 'the successor holds it now');

    // The first worker finally returns and tries to mark it done.
    await outbox.settleForTesting(stale, OutboxState.done, at: later);

    expect(await outbox.stateOf(intent.dedupKey), OutboxState.processing,
        reason: "the stale worker's verdict must land on nothing");
  });

  test('a failing handler waits for a later barrier, then is parked',
      () async {
    // Not retried in a loop: spending every attempt in the same millisecond,
    // against exactly the conditions that just failed, is a busy loop wearing a
    // retry policy's clothes. And it stops eventually, or a deterministically
    // broken intent is re-run on every barrier for the life of the install.
    var t = DateTime(2026, 8, 12, 6);
    final h = handler(throws: Exception('plugin refused'));
    await outbox.enqueue(intent, now: t);

    await outbox.dispatch(h.map, now: t);
    expect(h.ran, hasLength(1));
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.pending);

    // Immediately again: the backoff has not passed, so nothing runs.
    await outbox.dispatch(h.map, now: t);
    expect(h.ran, hasLength(1), reason: 'the retry waits for a later barrier');

    for (var i = 1; i < OutboxStore.maxAttempts; i++) {
      t = t.add(OutboxStore.retryAfter + const Duration(seconds: 1));
      await outbox.dispatch(h.map, now: t);
    }
    expect(h.ran, hasLength(OutboxStore.maxAttempts));
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.dead);

    t = t.add(const Duration(days: 1));
    await outbox.dispatch(h.map, now: t);
    expect(h.ran, hasLength(OutboxStore.maxAttempts),
        reason: 'a parked row is never picked up again');
  });

  test('a parked intent is revived when a caller asserts it again', () async {
    // **Parking must not entomb.** The dispatcher only ever looks at
    // `pending`/`processing`, `prune` deliberately keeps dead rows, and
    // enqueueing used to ignore any key it already had — so a roll-on that
    // exhausted its attempts could never be claimed again and never
    // re-enqueued. `_rollOn` then returned false forever, the pending slot it
    // guards was held open forever, and every later pass re-settled an
    // occurrence that could never finish.
    //
    // A caller asserting the intent again is new information: nothing carried
    // it out, and the occurrence still owes a roll.
    var t = DateTime(2026, 8, 12, 6);
    final h = handler(throws: Exception('plugin refused'));
    await outbox.enqueue(intent, now: t);
    for (var i = 0; i < OutboxStore.maxAttempts; i++) {
      await outbox.dispatch(h.map, now: t);
      t = t.add(OutboxStore.retryAfter + const Duration(seconds: 1));
    }
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.dead);

    // The next settle records the same intent again.
    await outbox.enqueue(intent, now: t);
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.pending,
        reason: 'a re-asserted intent comes back');

    final ok = handler();
    await outbox.dispatch(ok.map, now: t);
    expect(ok.ran, hasLength(1), reason: 'and is carried out');
    expect(ok.ran.single.attempts, 1, reason: 'with a fresh budget');
    expect(await outbox.stateOf(intent.dedupKey), OutboxState.done);
  });

  test('re-asserting an intent already owed changes nothing', () async {
    // Revival is only for `dead`. Re-enqueueing a row that is merely waiting
    // out its backoff would reset it, and one that is leased would have its
    // holder stolen from under it.
    final t = DateTime(2026, 8, 12, 6);
    final h = handler(throws: Exception('plugin refused'));
    await outbox.enqueue(intent, now: t);
    await outbox.dispatch(h.map, now: t);
    expect(h.ran, hasLength(1));

    await outbox.enqueue(intent, now: t);
    await outbox.dispatch(h.map, now: t);
    expect(h.ran, hasLength(1),
        reason: 'the backoff still stands — this is not a way to skip it');
  });

  test('one failing intent does not cost the others', () async {
    // Same rule the host-event drain follows: a batch that aborted on the first
    // throw would be the net taking down what it protects.
    final ran = <String>[];
    final handlers = <String, OutboxHandler>{
      'rollOn': (job) async {
        ran.add(job.dedupKey);
        if (job.dedupKey.endsWith(':1')) throw Exception('boom');
      },
    };
    await outbox.enqueue(const OutboxIntent(kind: 'rollOn', dedupKey: 'x:1'));
    await outbox.enqueue(const OutboxIntent(kind: 'rollOn', dedupKey: 'x:2'));

    await outbox.dispatch(handlers);

    expect(ran, ['x:1', 'x:2']);
    expect(await outbox.stateOf('x:1'), OutboxState.pending);
    expect(await outbox.stateOf('x:2'), OutboxState.done);
  });

  test('only: runs one intent and leaves the rest owed', () async {
    // A caller that just enqueued an intent is inside one alarm's lane. An
    // unscoped dispatch there would carry out another alarm's intent too, and
    // its evaluate would run outside its own lane.
    final h = handler();
    await outbox.enqueue(const OutboxIntent(kind: 'rollOn', dedupKey: 'x:1'));
    await outbox.enqueue(const OutboxIntent(kind: 'rollOn', dedupKey: 'x:2'));

    await outbox.dispatch(h.map, only: 'x:2');

    expect(h.ran.map((j) => j.dedupKey), ['x:2']);
    expect(await outbox.stateOf('x:1'), OutboxState.pending);
  });

  test('an intent nobody can carry out is parked, not retried', () async {
    // Reachable when a `kind` is renamed while rows are still in flight.
    // Spending the whole retry budget rediscovering that there is no handler
    // would just delay the same answer.
    await outbox.enqueue(const OutboxIntent(kind: 'gone', dedupKey: 'x:1'));
    await outbox.dispatch(const {});
    expect(await outbox.stateOf('x:1'), OutboxState.dead);
  });

  test('prune drops finished rows but keeps the parked ones', () async {
    // A `done` row is the "already carried out" record, so it is kept for as
    // long as the occurrence it belongs to could still be re-settled. A `dead`
    // row is the only trace of an intent that never happened — deleting that
    // would erase the evidence that an occurrence was never booked.
    final t = DateTime(2026, 8, 12, 6);
    await outbox.enqueue(const OutboxIntent(kind: 'rollOn', dedupKey: 'done:1'),
        now: t);
    await outbox.enqueue(const OutboxIntent(kind: 'gone', dedupKey: 'dead:1'),
        now: t);
    await outbox.dispatch(handler().map, now: t);
    expect(await outbox.stateOf('done:1'), OutboxState.done);
    expect(await outbox.stateOf('dead:1'), OutboxState.dead);

    await outbox.prune(now: t.add(OutboxStore.doneTtl * 2));

    expect(await outbox.stateOf('done:1'), isNull);
    expect(await outbox.stateOf('dead:1'), OutboxState.dead);
  });
}

/// An `Error`, so it escapes the dispatcher's `on Exception` the way a real
/// process death escapes everything — leaving the row leased rather than
/// released.
class _Died extends Error {}

/// Same trick, for a worker that is still holding the row when its lease runs
/// out rather than one that died.
class _Held extends Error {}

import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostAlarmEventClaims', () {
    setUp(useInMemoryAppDatabase);

    HostAlarmEvent eventAt(DateTime recordedAt, {int id = 10001}) =>
        HostAlarmEvent(
          id: id,
          kind: HostAlarmEventKind.dropped,
          cause: HostAlarmEventCause.platformRefusal,
          recordedAt: recordedAt,
          at: recordedAt,
        );

    test('unique keys are per (id, recordedAt)', () {
      final a = DateTime.utc(2026, 8, 8, 6);
      final b = DateTime.utc(2026, 8, 8, 6, 0, 1);
      expect(hostAlarmEventClaimKey(1, a), isNot(hostAlarmEventClaimKey(1, b)));
      expect(hostAlarmEventClaimKey(1, a), isNot(hostAlarmEventClaimKey(2, a)));
    });

    test('begin is a real compare-and-swap — only one caller gets the event',
        () async {
      // The thing SharedPreferences could not do. Two isolates could both read
      // "absent" and both run the handler, so convergence had to live in the
      // handlers; the whole of that claim was one bool. Now taking
      // responsibility is one transaction, and the loser is told so.
      final a = HostAlarmEventClaims();
      final b = HostAlarmEventClaims();
      final event = eventAt(DateTime.utc(2026, 8, 8, 6, 0, 30));

      expect(await a.isClaimed(event), isFalse);
      final claimA = await a.begin(event);
      expect(claimA, isNotNull);
      expect(claimA!.attempts, 1);
      expect(await b.begin(event), isNull,
          reason: 'A holds a live lease on it');

      await a.complete(event, claimA);
      expect(await b.isClaimed(event), isTrue);
      expect(await b.begin(event), isNull, reason: 'already applied');
    });

    test('a claim whose holder died is retaken once its lease expires',
        () async {
      // The crash recovery a boolean cannot express. A row that says "handled"
      // before the handler ran loses the event for good — the plugin
      // acknowledged it natively long ago, so nothing redelivers it. Marking
      // `processing` with a lease is what makes the dead holder recoverable.
      final claims = HostAlarmEventClaims();
      final event = eventAt(DateTime.utc(2026, 8, 8, 6, 0, 30));
      final t = DateTime.utc(2026, 8, 8, 6, 1);

      expect(await claims.begin(event, now: t), isNotNull);
      // Still inside the lease: nobody else may touch it.
      expect(
        await claims.begin(event,
            now: t.add(HostAlarmEventClaims.lease - const Duration(seconds: 1))),
        isNull,
      );

      final retaken = await claims.begin(event,
          now: t.add(HostAlarmEventClaims.lease + const Duration(seconds: 1)));
      expect(retaken, isNotNull);
      expect(retaken!.attempts, 2, reason: 'the count is on disk, not in RAM');
      expect(await claims.isClaimed(event), isFalse,
          reason: 'processing is not done');
    });

    test('an abandoned event is never re-run, and never reads as applied',
        () async {
      // `abandoned` has to be distinct from `done` in both directions: it must
      // stop the retries, and it must not let a dropped ring look like an event
      // that was dealt with.
      final claims = HostAlarmEventClaims();
      final event = eventAt(DateTime.utc(2026, 8, 8, 6, 0, 30));
      final first = await claims.begin(event);
      expect(first, isNotNull);
      await claims.abandon(event, first!);

      expect(await claims.begin(event), isNull);
      expect(await claims.isClaimed(event), isFalse);
    });

    test('release hands the event back with its attempt count intact',
        () async {
      final claims = HostAlarmEventClaims();
      final event = eventAt(DateTime.utc(2026, 8, 8, 6, 0, 30));
      final first = (await claims.begin(event))!;
      expect(first.attempts, 1);
      await claims.release(event, first);
      // Immediately retakeable — `release` drops the lease rather than waiting
      // it out, because the caller has already decided to try again later.
      expect((await claims.begin(event))!.attempts, 2);
    });

    test('a worker that lost its lease cannot settle its successor\'s claim',
        () async {
      // The lease bounds how long a claim is RESPECTED, not how long a handler
      // runs. A slow worker can still be inside its handler when the next
      // barrier retakes the event, and its verdict must then land on nothing —
      // `abandon` from a stale worker would park an event the successor is
      // about to apply, leaving a row saying a dropped ring was never dealt
      // with, and `release` would re-open one someone is actively handling.
      final claims = HostAlarmEventClaims();
      final event = eventAt(DateTime.utc(2026, 8, 8, 6, 0, 30));
      final t = DateTime.utc(2026, 8, 8, 6, 1);

      final stale = (await claims.begin(event, now: t))!;
      final later = t.add(HostAlarmEventClaims.lease + const Duration(minutes: 1));
      final holder = (await claims.begin(event, now: later))!;
      expect(holder.attempts, 2);

      // The overtaken worker finally returns, both ways round.
      await claims.abandon(event, stale, now: later);
      expect(await claims.begin(event, now: later.add(const Duration(hours: 1))),
          isNotNull,
          reason: 'a stale abandon must not park a live claim');

      // And the real holder still settles it. (Its own attempts moved on with
      // the begin above, so re-read rather than reusing `holder`.)
      final current = (await claims.begin(
          event, now: later.add(const Duration(hours: 2))))!;
      await claims.complete(event, current);
      expect(await claims.isClaimed(event), isTrue);
    });

    test('prune drops rows past the TTL and keeps the rest', () async {
      final now = DateTime.utc(2026, 8, 9, 12);
      final claims = HostAlarmEventClaims();
      final old = eventAt(now.subtract(const Duration(days: 8)));
      final recent = eventAt(now.subtract(const Duration(days: 1)), id: 10002);
      final oldClaim = await claims.begin(old);
      await claims.complete(old, oldClaim!);
      final recentClaim = await claims.begin(recent);
      await claims.complete(recent, recentClaim!);

      await claims.prune(now: now);

      // Without a ceiling these rows live as long as the install — one per host
      // event ever delivered.
      expect(await claims.isClaimed(old), isFalse);
      expect(await claims.isClaimed(recent), isTrue);
    });
  });

  group('HostAlarmEventBridge', () {
    test('apply awaits handlers before returning — listen is not a barrier',
        () async {
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      final claims = HostAlarmEventClaims();
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: claims,
      );

      final order = <String>[];
      final gate = Completer<void>();
      bridge.setHandler((event) async {
        order.add('start-${event.id}');
        await gate.future;
        order.add('done-${event.id}');
      });

      await bridge.start();
      controller.add(HostAlarmEvent(
        id: 1,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.staleAtBoot,
        recordedAt: DateTime.utc(2026, 8, 8),
        at: DateTime.utc(2026, 8, 8, 6),
      ));

      // listen alone must NOT mean the handler finished
      await Future<void>.delayed(Duration.zero);
      expect(order, ['start-1']);

      final applyFuture = bridge.apply();
      gate.complete();
      await applyFuture;
      expect(order, ['start-1', 'done-1']);

      expect(await claims.isClaimed(HostAlarmEvent(
        id: 1,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.staleAtBoot,
        recordedAt: DateTime.utc(2026, 8, 8),
        at: DateTime.utc(2026, 8, 8, 6),
      )), isTrue, reason: 'a handler that finished must be marked handled');

      await bridge.dispose();
      await controller.close();
    });

    test('a failing handler costs only its own event, and is retried',
        () async {
      // The net must not take down what it protects: draining a batch, one
      // throwing handler used to discard every event queued beside it — they
      // were already off the queue — while apply() returned as if all was well.
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      final claims = HostAlarmEventClaims();
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: claims,
      );

      final seen = <int>[];
      var failuresLeft = 1;
      bridge.setHandler((event) async {
        seen.add(event.id);
        if (event.id == 1 && failuresLeft > 0) {
          failuresLeft--;
          throw Exception('handler boom');
        }
      });

      HostAlarmEvent make(int id) => HostAlarmEvent(
            id: id,
            kind: HostAlarmEventKind.dropped,
            cause: HostAlarmEventCause.platformRefusal,
            recordedAt: DateTime.utc(2026, 8, 8, 6),
            at: DateTime.utc(2026, 8, 8, 6),
          );

      await bridge.start();
      controller.add(make(1));
      controller.add(make(2));
      await bridge.apply();

      expect(seen, containsAll(<int>[1, 2]),
          reason: 'the second event must still be handled');
      expect(seen.where((id) => id == 1).length, 1,
          reason: 'one attempt per barrier — retrying three times inside one '
              'drain spends every attempt against the same instant');
      expect(await claims.isClaimed(make(1)), isFalse);
      expect(await claims.isClaimed(make(2)), isTrue);

      // The next barrier is the retry, and by then the transient fault is gone.
      await bridge.apply();
      expect(seen.where((id) => id == 1).length, 2);
      expect(await claims.isClaimed(make(1)), isTrue);

      await bridge.dispose();
      await controller.close();
    });

    test('a handler that never succeeds is never marked handled', () async {
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      final claims = HostAlarmEventClaims();
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: claims,
      );
      var calls = 0;
      bridge.setHandler((event) async {
        calls++;
        throw Exception('always');
      });
      final event = HostAlarmEvent(
        id: 3,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.staleAtBoot,
        recordedAt: DateTime.utc(2026, 8, 8, 6),
        at: DateTime.utc(2026, 8, 8, 6),
      );

      await bridge.start();
      controller.add(event);
      // One attempt per barrier, so the cap is reached over several of them.
      for (var i = 0; i < HostAlarmEventBridge.maxHandlerAttempts + 2; i++) {
        await bridge.apply();
      }

      // Bounded, or a deterministically-throwing handler spins on every
      // barrier for the life of the process.
      expect(calls, HostAlarmEventBridge.maxHandlerAttempts);
      expect(await claims.isClaimed(event), isFalse,
          reason: 'the mark goes down after success, never before');

      await bridge.dispose();
      await controller.close();
    });

    test('a failed start does not latch — the next apply subscribes', () async {
      // `_started = true` used to go up before `Alarm.init()` ran, so one
      // plugin hiccup left every later barrier returning instantly having
      // subscribed to nothing at all.
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      var readyCalls = 0;
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: HostAlarmEventClaims(),
        ensurePluginReady: () async {
          readyCalls++;
          if (readyCalls == 1) throw Exception('init boom');
        },
      );
      final seen = <int>[];
      bridge.setHandler((event) async => seen.add(event.id));

      await expectLater(bridge.start(), throwsException);

      controller.add(HostAlarmEvent(
        id: 9,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: DateTime.utc(2026, 8, 8, 6),
        at: DateTime.utc(2026, 8, 8, 6),
      ));
      await bridge.apply();
      // A broadcast stream drops what it emitted with no listener, so what is
      // proved here is that the retry really subscribed — the next event lands.
      controller.add(HostAlarmEvent(
        id: 10,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: DateTime.utc(2026, 8, 8, 7),
        at: DateTime.utc(2026, 8, 8, 7),
      ));
      await bridge.apply();

      expect(readyCalls, 2);
      expect(seen, [10]);

      await bridge.dispose();
      await controller.close();
    });

    test('one event delivered to two bridges runs exactly one handler',
        () async {
      // **This assertion changed direction with the move to SQLite, and the new
      // one is the fix.** Two bridges model two isolates. On prefs both could
      // read "absent" and both run the handler, because a bool cannot
      // compare-and-swap — so this test used to assert that BOTH ran, which was
      // recording the defect rather than a requirement. `begin` is a
      // transaction now, so the second one is told no.
      //
      // Handlers must still be idempotent on `(id, recordedAt)`. The claim
      // makes concurrent double-handling rare, not impossible: a handler can
      // outlive its own lease, and then a second isolate legitimately takes the
      // event over.
      await useInMemoryAppDatabase();
      final event = HostAlarmEvent(
        id: 42,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.staleAtBoot,
        recordedAt: DateTime.utc(2026, 8, 8, 6),
        at: DateTime.utc(2026, 8, 8, 5, 59),
      );
      final source = StreamController<HostAlarmEvent>.broadcast();

      final seenA = <HostAlarmEvent>[];
      final seenB = <HostAlarmEvent>[];
      final bridgeA = HostAlarmEventBridge(
        events: () => source.stream,
        claims: HostAlarmEventClaims(),
      );
      final bridgeB = HostAlarmEventBridge(
        events: () => source.stream,
        claims: HostAlarmEventClaims(),
      );
      bridgeA.setHandler((e) async => seenA.add(e));
      bridgeB.setHandler((e) async => seenB.add(e));
      await bridgeA.start();
      await bridgeB.start();
      source.add(event);
      await bridgeA.apply();
      await bridgeB.apply();
      expect([...seenA, ...seenB], hasLength(1),
          reason: 'the claim is a lock now, so the duplicate is suppressed');
      expect([...seenA, ...seenB].single.claimKey, event.claimKey);
      await bridgeA.dispose();
      await bridgeB.dispose();
      await source.close();
    });
    test('apply is re-entrant during a handler — no deadlock with nested apply',
        () async {
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: HostAlarmEventClaims(),
      );
      final started = Completer<void>();
      final finished = Completer<void>();
      bridge.setHandler((event) async {
        started.complete();
        // Mimic evaluate's post-fetch re-drain while settling this event.
        await bridge.apply().timeout(const Duration(seconds: 1));
        finished.complete();
      });
      await bridge.start();
      controller.add(HostAlarmEvent(
        id: 7,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: DateTime.utc(2026, 8, 8, 6),
        at: DateTime.utc(2026, 8, 8, 6),
      ));
      // Yield so the auto-drain microtask starts the handler before apply waits.
      await Future<void>.delayed(Duration.zero);
      await started.future.timeout(const Duration(seconds: 2));
      await bridge.apply().timeout(const Duration(seconds: 2));
      await finished.future.timeout(const Duration(seconds: 2));
      await bridge.dispose();
      await controller.close();
    });
    test('a programming Error reaches the caller instead of the void',
        () async {
      // Policy: an Exception soft-fails, an Error propagates — it is a bug and
      // should be loud. But the drain runs in a detached microtask, so "loud"
      // used to mean an unhandled zone error while `apply()` returned normally
      // with the rest of the batch eaten. It has to come out of the barrier the
      // caller actually awaits.
      await useInMemoryAppDatabase();
      final controller = StreamController<HostAlarmEvent>.broadcast();
      final claims = HostAlarmEventClaims();
      final bridge = HostAlarmEventBridge(
        events: () => controller.stream,
        claims: claims,
      );
      bridge.setHandler((event) async => throw StateError('programming bug'));
      final event = HostAlarmEvent(
        id: 11,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.staleAtBoot,
        recordedAt: DateTime.utc(2026, 8, 8, 6),
        at: DateTime.utc(2026, 8, 8, 6),
      );

      await bridge.start();
      controller.add(event);
      await expectLater(bridge.apply(), throwsStateError);

      expect(await claims.isClaimed(event), isFalse,
          reason: 'a handler that blew up did not handle anything');
      // Reported once, not on every later barrier.
      await bridge.apply();

      await bridge.dispose();
      await controller.close();
    });
  });
}

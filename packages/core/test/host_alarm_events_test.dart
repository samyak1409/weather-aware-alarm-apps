import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HostAlarmEventClaims', () {
    test('unique keys are per (id, recordedAt)', () {
      final a = DateTime.utc(2026, 8, 8, 6);
      final b = DateTime.utc(2026, 8, 8, 6, 0, 1);
      expect(hostAlarmEventClaimKey(1, a), isNot(hostAlarmEventClaimKey(1, b)));
      expect(hostAlarmEventClaimKey(1, a), isNot(hostAlarmEventClaimKey(2, a)));
    });

    test(
        'two caches + one backend share claims after reload '
        '(host mock cannot hold two truly stale unflushed caches)', () async {
      // Honest limit (H4): SharedPreferences.setMockInitialValues gives one
      // in-memory map. Two Claims objects both reload that same map — this
      // proves the write is visible after reload, NOT a true dual-isolate race
      // where each cache holds a stale snapshot across an awaited gap. Real
      // isolates still need idempotent handlers (history hostEventKey +
      // clearPending) because prefs cannot CAS.
      SharedPreferences.setMockInitialValues({});
      final backend = await SharedPreferences.getInstance();

      Future<SharedPreferences> prefsA() async {
        await backend.reload();
        return backend;
      }

      Future<SharedPreferences> prefsB() async {
        await backend.reload();
        return backend;
      }

      final claimsA = HostAlarmEventClaims(prefs: prefsA);
      final claimsB = HostAlarmEventClaims(prefs: prefsB);
      final event = HostAlarmEvent(
        id: 10001,
        kind: HostAlarmEventKind.dropped,
        cause: HostAlarmEventCause.platformRefusal,
        recordedAt: DateTime.utc(2026, 8, 8, 6, 0, 30),
        at: DateTime.utc(2026, 8, 8, 6),
      );

      expect(await claimsA.isClaimed(event), isFalse);
      await claimsA.claim(event);
      expect(await claimsB.isClaimed(event), isTrue,
          reason: 'B must see A\'s claim after reload');
    });

    test('prune drops keys past the TTL and keeps the rest', () async {
      SharedPreferences.setMockInitialValues({});
      final now = DateTime.utc(2026, 8, 9, 12);
      final claims = HostAlarmEventClaims();
      HostAlarmEvent at(DateTime recordedAt) => HostAlarmEvent(
            id: 10001,
            kind: HostAlarmEventKind.dropped,
            cause: HostAlarmEventCause.staleAtBoot,
            recordedAt: recordedAt,
            at: recordedAt,
          );
      final old = at(now.subtract(const Duration(days: 8)));
      final recent = at(now.subtract(const Duration(days: 1)));
      await claims.claim(old);
      await claims.claim(recent);

      await claims.prune(now: now);

      // Without a ceiling these bools live as long as the install — one per
      // host event, in the same prefs blob the history log sits in.
      expect(await claims.isClaimed(old), isFalse);
      expect(await claims.isClaimed(recent), isTrue);
    });

    test('an unrelated key is never pruned', () async {
      SharedPreferences.setMockInitialValues({'nivaat.history': '[]'});
      final prefs = await SharedPreferences.getInstance();
      await HostAlarmEventClaims().prune(now: DateTime.utc(2030));
      await prefs.reload();
      expect(prefs.getString('nivaat.history'), '[]');
    });
  });

  group('HostAlarmEventBridge', () {
    test('apply awaits handlers before returning — listen is not a barrier',
        () async {
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
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

    test('injected identical events into two bridges are both delivered',
        () async {
      // Native won't re-emit after ack; apps must still tolerate injected
      // duplicates via idempotent handlers (matrix #5).
      SharedPreferences.setMockInitialValues({});
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
      expect(seenA, hasLength(1));
      expect(seenB, hasLength(1));
      expect(seenA.single.claimKey, event.claimKey);
      await bridgeA.dispose();
      await bridgeB.dispose();
      await source.close();
    });
    test('apply is re-entrant during a handler — no deadlock with nested apply',
        () async {
      SharedPreferences.setMockInitialValues({});
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
      SharedPreferences.setMockInitialValues({});
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

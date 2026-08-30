import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/ids.dart';

/// The id map's safety net. Every number Nivaat hands to a scheduler or the
/// notification manager comes from [NivaatIds]; these lock the properties the
/// rest of the app silently assumes.
void main() {
  test('no two ids collide, for any alarm id in range', () {
    final seen = <int, String>{};
    void claim(int id, String what) {
      expect(seen.containsKey(id), isFalse,
          reason: '$what collides with ${seen[id]} at id $id');
      seen[id] = what;
    }

    for (var a = 1; a <= NivaatIds.maxAlarmId; a++) {
      for (final r in NivaatIds.allRings(a)) {
        claim(r, 'ring($a)');
      }
      for (var r = 0; r < CheckCascade.ladderMinutesBefore.length; r++) {
        claim(NivaatIds.check(a, r), 'check($a, rung $r)');
      }
      claim(NivaatIds.card(a), 'card($a)');
    }
  });

  test('every ladder rung gets its own locker, and allChecks names them all',
      () {
    // The chain fix (2026-08-25): rungs are booked independently, so two rungs
    // of the same alarm sharing a number would silently overwrite one booking
    // with the next — exactly the failure the split exists to remove.
    final ids = NivaatIds.allChecks(42);
    expect(ids, hasLength(CheckCascade.ladderMinutesBefore.length));
    expect(ids.toSet(), hasLength(ids.length), reason: 'no rung shares an id');
    for (var r = 0; r < CheckCascade.ladderMinutesBefore.length; r++) {
      expect(ids[r], NivaatIds.check(42, r));
    }
    // Post-T retries reuse the LAST rung's locker — T-0 has fired by then, and
    // only one retry can ever be outstanding.
    expect(NivaatIds.retryCheck(42),
        NivaatIds.check(42, CheckCascade.ladderMinutesBefore.length - 1));
  });

  test('check ids stay inside int32 at the top of the block range', () {
    // The blocks moved to 100000+ for the per-rung split; the ceiling is what
    // the alarm package and AlarmManager request codes can hold.
    final top = NivaatIds.check(
        NivaatIds.maxAlarmId, CheckCascade.ladderMinutesBefore.length - 1);
    expect(top, lessThan(2147483647));
    expect(top, greaterThan(0));
  });

  test('ids are legal for the alarm package (never 0 or -1, within int32)', () {
    // Alarm.alarmSettingsValidation throws on 0 / -1 / out-of-int32.
    for (var a = 1; a <= NivaatIds.maxAlarmId; a++) {
      for (final id in NivaatIds.allRings(a)) {
        expect(id, greaterThan(0));
        expect(id, lessThan(2147483647));
      }
    }
  });

  group('ring lockers', () {
    test('the pre-arm and the late ring never share a locker', () {
      // The two that can be live at once: a late ring for the occurrence just
      // closed, and the pre-arm for the next one, written in the same pass.
      expect(NivaatIds.ring(7), isNot(NivaatIds.lateRing(7)));
    });

    test('the split is role-based, so ANY gap between occurrences is safe', () {
      // Guards the trap a day-parity split falls into: a Mon+Fri alarm's
      // consecutive occurrences are 4 days apart, so both land on the same
      // parity and the pre-arm would evict the late ring again. Role-based
      // ids don't look at the date at all, so no gap can break them.
      for (final gapDays in [1, 2, 3, 4, 5, 6, 7, 14]) {
        final closed = DateTime(2026, 7, 13, 6, 0); // Monday
        final upcoming = closed.add(Duration(days: gapDays));
        expect(NivaatIds.lateRing(7), isNot(NivaatIds.ring(7)),
            reason: 'late ring for $closed vs pre-arm for $upcoming');
      }
    });

    test('re-deciding one occurrence reuses its locker', () {
      // The eight ladder rungs must converge on ONE armed ring, not scatter
      // eight of them — so the pre-arm id can't depend on when it was decided.
      expect(NivaatIds.ring(7), NivaatIds.ring(7));
      expect(NivaatIds.lateRing(7), NivaatIds.lateRing(7));
    });

    test("the roll-on pre-arm never shares the closing occurrence's locker", () {
      // The pass that finalises an occurrence opens the next one in the same
      // breath — and it runs AT the moment the closing ring is due but may not
      // have sounded yet. `Alarm.set` stops any alarm sharing the id first, so
      // one locker meant tomorrow's pre-arm cancelled the ring about to wake
      // you, while history recorded "Rang".
      expect(NivaatIds.nextRing(7), isNot(NivaatIds.ring(7)));
      // And not the late locker either: a late ring and a next-day pre-arm are
      // different roles that can be live at the same instant.
      expect(NivaatIds.nextRing(7), isNot(NivaatIds.lateRing(7)));
    });

    test('allRings covers every locker an alarm can ever use', () {
      expect(
          NivaatIds.allRings(7),
          containsAll(<int>[
            NivaatIds.ring(7),
            NivaatIds.lateRing(7),
            NivaatIds.nextRing(7),
          ]));
      expect(NivaatIds.allRings(7), hasLength(3));
    });

    test('alarmIdOfRing decodes rings and nothing else', () {
      // The orphan sweep gets raw numbers back from `scheduledIds()` and
      // cancels whatever it decodes as a ring for an alarm that has left the
      // store. A check or card id mistaken for a ring would be cancelled by a
      // number that means something else entirely.
      for (final a in [1, 2, 42, NivaatIds.maxAlarmId]) {
        expect(NivaatIds.alarmIdOfRing(NivaatIds.ring(a)), a);
        expect(NivaatIds.alarmIdOfRing(NivaatIds.lateRing(a)), a);
        expect(NivaatIds.alarmIdOfRing(NivaatIds.nextRing(a)), a);
        for (var r = 0; r < CheckCascade.ladderMinutesBefore.length; r++) {
          expect(NivaatIds.alarmIdOfRing(NivaatIds.check(a, r)), isNull);
        }
        expect(NivaatIds.alarmIdOfRing(NivaatIds.card(a)), isNull);
      }
      // Alarm ids start at 1, so a bare block number is not a ring — and
      // reading it as one would decode to alarm 0 and cancel by that number.
      expect(NivaatIds.alarmIdOfRing(NivaatIds.ringBlock), isNull);
      expect(NivaatIds.alarmIdOfRing(NivaatIds.nextRingBlock), isNull);
      // Nothing outside the blocks, in either direction.
      expect(NivaatIds.alarmIdOfRing(0), isNull);
      expect(NivaatIds.alarmIdOfRing(-1), isNull);
      expect(
          NivaatIds.alarmIdOfRing(
              NivaatIds.nextRingBlock + NivaatIds.maxAlarmId + 1),
          isNull);
    });

    test('ringRoleOf maps each locker and ignores non-rings', () {
      expect(NivaatIds.ringRoleOf(NivaatIds.ring(7)), RingLockerRole.ring);
      expect(
          NivaatIds.ringRoleOf(NivaatIds.lateRing(7)), RingLockerRole.lateRing);
      expect(
          NivaatIds.ringRoleOf(NivaatIds.nextRing(7)), RingLockerRole.nextRing);
      expect(NivaatIds.ringRoleOf(NivaatIds.check(7, 0)), isNull);
      expect(NivaatIds.ringRoleOf(NivaatIds.check(7, 8)), isNull);
      expect(NivaatIds.ringRoleOf(NivaatIds.card(7)), isNull);
      expect(NivaatIds.ringRoleOf(NivaatIds.ringBlock), isNull);
    });

    test('different alarms never share a locker', () {
      expect(NivaatIds.ring(7), isNot(NivaatIds.ring(8)));
      expect(NivaatIds.lateRing(7), isNot(NivaatIds.lateRing(8)));
      expect(NivaatIds.nextRing(7), isNot(NivaatIds.nextRing(8)));
      expect(NivaatIds.ring(8), isNot(NivaatIds.lateRing(7)),
          reason: 'blocks must not overlap across roles either');
      expect(NivaatIds.lateRing(8), isNot(NivaatIds.nextRing(7)));
    });
  });
}

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
      claim(NivaatIds.check(a), 'check($a)');
      claim(NivaatIds.headsUp(a), 'headsUp($a)');
      claim(NivaatIds.skip(a), 'skip($a)');
    }
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

    test('allRings covers both lockers an alarm can ever use', () {
      expect(NivaatIds.allRings(7),
          containsAll(<int>[NivaatIds.ring(7), NivaatIds.lateRing(7)]));
      expect(NivaatIds.allRings(7), hasLength(2));
    });

    test('different alarms never share a locker', () {
      expect(NivaatIds.ring(7), isNot(NivaatIds.ring(8)));
      expect(NivaatIds.lateRing(7), isNot(NivaatIds.lateRing(8)));
      expect(NivaatIds.ring(8), isNot(NivaatIds.lateRing(7)),
          reason: 'blocks must not overlap across roles either');
    });
  });
}

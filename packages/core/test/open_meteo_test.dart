import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('slotKey', () {
    test('keys the play slot in UTC, floored to the quarter hour', () {
      expect(OpenMeteo.slotKey(DateTime.utc(2026, 7, 13, 14, 17)),
          '2026-07-13T14:15');
      expect(OpenMeteo.slotKey(DateTime.utc(2026, 7, 13, 14, 0)),
          '2026-07-13T14:00');
      expect(OpenMeteo.slotKey(DateTime.utc(2026, 7, 13, 14, 59)),
          '2026-07-13T14:45');
    });

    test('a local instant is converted before it is floored', () {
      // Round-trips regardless of the test machine's timezone, so a court in
      // another zone still maps to the right slot rather than to the phone's
      // wall-clock hour.
      final local = DateTime.utc(2026, 7, 13, 23, 5).toLocal();
      expect(OpenMeteo.slotKey(local), '2026-07-13T23:00');
    });

    test('a half-hour zone keeps its own minutes — the India skew (2026-08-25)',
        () {
      // **The bug this replaced.** The old lookup floored to the UTC HOUR, and
      // India is UTC+5:30 — so a 06:00 IST alarm asked for 00:00 UTC, which is
      // 05:30 IST: half an hour before the alarm, systematically, for every
      // Indian user, on every far check.
      //
      // 06:30 IST (the default play start for a 06:00 alarm) is 01:00 UTC. On
      // the quarter-hour grid that is exact, because every world offset is a
      // whole number of quarter hours — there is no zone where this skews.
      final playStart = DateTime.utc(2026, 7, 13, 1, 0);
      expect(OpenMeteo.slotKey(playStart), '2026-07-13T01:00');
      // And the half-hour offset itself lands on the grid, not between it.
      expect(OpenMeteo.slotKey(DateTime.utc(2026, 7, 13, 0, 30)),
          '2026-07-13T00:30');
    });
  });

  group('unknownModelIn', () {
    test('lifts the rejected model name out of a real 400 body', () {
      // Recorded from the live API on 2026-08-25. A name Open-Meteo does not
      // recognise fails the WHOLE request, so this string is the only notice
      // that a hard-coded model has been retired — there is no endpoint that
      // lists them.
      const body = '{"error":true,"reason":"Data corrupted at path \'\'. '
          'Cannot initialize MultiDomains from invalid String value '
          'this_model_does_not_exist."}';
      expect(OpenMeteo.unknownModelIn(body), 'this_model_does_not_exist');
    });

    test('an unrelated failure names nothing, so nothing gets pruned', () {
      const body = '{"error":true,"reason":"Latitude must be in range of '
          '-90 to 90°. Given: 999.0."}';
      expect(OpenMeteo.unknownModelIn(body), isNull);
    });
  });

  group('windowFrom — the mean across the models that answered', () {
    // Recorded from live responses (2026-08-30), not invented: the suffix rule
    // below is the API's, and it is the whole reason this group exists.
    Map<String, dynamic> block(Map<String, dynamic> series) => {
          'minutely_15': {
            'time': ['2026-08-30T06:30', '2026-08-30T06:45'],
            ...series,
          }
        };

    test('several models answering come back suffixed, and are averaged', () {
      final out = OpenMeteo.windowFrom(
        block({
          'wind_speed_10m_ecmwf_ifs': [10, 20],
          'wind_gusts_10m_ecmwf_ifs': [30, 40],
          'wind_speed_10m_cma_grapes_global': [20, 30],
          'wind_gusts_10m_cma_grapes_global': [50, 60],
        }),
        ['ecmwf_ifs', 'cma_grapes_global'],
      );
      expect(out.map((s) => s.rawSpeedKmh), [15, 25]);
      expect(out.map((s) => s.rawGustKmh), [40, 50]);
      expect(out.first.slotAt,
          DateTime.parse('2026-08-30T06:30Z').toLocal());
    });

    test('ONE model answering comes back UNSUFFIXED, even when we asked for '
        'several', () {
      // The keys below are a live response, and the rule they encode — and the
      // bug it caused — is on `windowFrom`'s fallback branch.
      //
      // **The probe used a name that is NOT in `defaultWindModels`**, because a
      // regional model is the cheapest way to make one of two requested models
      // have no local data. So this pins the API's rule, not a recording of
      // the seven-name call production actually makes.
      final out = OpenMeteo.windowFrom(
        block({
          'wind_speed_10m': [11.1, 11.1],
          'wind_gusts_10m': [19.1, 19.4],
        }),
        ['dwd_icon_d2', 'ecmwf_ifs'],
      );
      expect(out.map((s) => s.rawSpeedKmh), [11.1, 11.1]);
      expect(out.map((s) => s.rawGustKmh), [19.1, 19.4]);
    });

    test('a model with wind but no gusts takes no part at all', () {
      // Gusts are half the decision, and letting it into the speed mean alone
      // would silently average two different model sets.
      final out = OpenMeteo.windowFrom(
        block({
          'wind_speed_10m_ecmwf_ifs': [10, 10],
          'wind_gusts_10m_ecmwf_ifs': [30, 30],
          'wind_speed_10m_jma_gsm': [100, 100],
        }),
        ['ecmwf_ifs', 'jma_gsm'],
      );
      expect(out.map((s) => s.rawSpeedKmh), [10, 10],
          reason: 'the gustless model is not in the mean');
    });

    test('a slot no model has is skipped, not zeroed', () {
      final out = OpenMeteo.windowFrom(
        block({
          'wind_speed_10m_ecmwf_ifs': [10, null],
          'wind_gusts_10m_ecmwf_ifs': [30, null],
        }),
        ['ecmwf_ifs'],
      );
      expect(out, hasLength(1));
      expect(out.single.slotAt, DateTime.parse('2026-08-30T06:30Z').toLocal());
    });

    test('nothing answering is an exception, never an empty window', () {
      // `decide` asserts on an empty window — no-data is the engine's own
      // branch, and it reaches it by catching this.
      expect(
        () => OpenMeteo.windowFrom(block(const {}), ['ecmwf_ifs']),
        throwsA(isA<OpenMeteoException>()),
      );
    });
  });

  group('regionLabel', () {
    test('district then state — what separates same-state results', () {
      // The whole reason for the change: `Koramangala` returns three places
      // that all read `Karnataka, India` under the old admin1+country label.
      expect(
        OpenMeteo.regionLabel(
            {'name': 'Koramangala', 'admin1': 'Karnataka', 'admin2': 'Bengaluru Urban'}),
        'Bengaluru Urban, Karnataka',
      );
      expect(
        OpenMeteo.regionLabel(
            {'name': 'Koramangala', 'admin1': 'Karnataka', 'admin2': 'Bengaluru Rural'}),
        'Bengaluru Rural, Karnataka',
      );
    });

    test('a district that repeats the place name is dropped', () {
      // Tonk's district is also called Tonk; `Tonk, Rajasthan` under a row
      // already titled `Tonk` says the name twice.
      expect(
        OpenMeteo.regionLabel(
            {'name': 'Tonk', 'admin1': 'Rajasthan', 'admin2': 'Tonk'}),
        'Rajasthan',
      );
    });

    test('missing parts leave no dangling comma', () {
      expect(OpenMeteo.regionLabel({'name': 'X', 'admin1': 'Karnataka'}),
          'Karnataka');
      expect(OpenMeteo.regionLabel({'name': 'X', 'admin2': 'Bengaluru Urban'}),
          'Bengaluru Urban');
      expect(OpenMeteo.regionLabel({'name': 'X'}), '');
    });

    test('the country is deliberately gone — accepted cost, locked', () {
      // Samyak, 2026-08-25: you do not need the country to recognise your own
      // area. The price is that `Jayanagar` in Nepal and in Karnataka no
      // longer name their countries; pinned here so it reads as a decision
      // rather than as something that slipped.
      expect(
        OpenMeteo.regionLabel({
          'name': 'Jayanagar',
          'admin1': 'Bagmati Province',
          'admin2': 'Chitwan',
          'country': 'Nepal',
        }),
        'Chitwan, Bagmati Province',
      );
    });
  });
}

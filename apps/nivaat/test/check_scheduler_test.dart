import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/check_scheduler.dart';

void main() {
  test('AndroidCheckScheduler.initialize swallows plugin Exceptions', () async {
    final scheduler = AndroidCheckScheduler(
      entrypoint: () {},
      initializePlugin: () async => throw Exception('r8/plugin boom'),
    );
    // A throw here used to abort main() before runApp ("keeps stopping").
    await expectLater(scheduler.initialize(), completes);
  });

  test('AndroidCheckScheduler.initialize lets Errors propagate', () async {
    final scheduler = AndroidCheckScheduler(
      entrypoint: () {},
      initializePlugin: () async => throw StateError('programming boom'),
    );
    await expectLater(scheduler.initialize(), throwsStateError);
  });

  test('AndroidCheckScheduler.initialize succeeds when plugin does', () async {
    var called = false;
    final scheduler = AndroidCheckScheduler(
      entrypoint: () {},
      initializePlugin: () async {
        called = true;
        return true;
      },
    );
    await scheduler.initialize();
    expect(called, isTrue);
  });

  test('cancelling one alarm never touches the shared iOS task', () async {
    // REVIEW #8. There is exactly ONE BGProcessing task for the whole app, so
    // cancelling it for one alarm took away every other alarm's near-T wakeup
    // — disable the 06:00 at 05:40 and the 07:00 lost its next check too.
    //
    // "Never touches it" is checked by reaching for the plugin being fatal
    // here: Workmanager is unregistered on the test host, so anything that
    // calls through raises an UnimplementedError — an Error, which the
    // Exception guards deliberately do not swallow. `scheduleChecks` is the
    // control: it proves the plugin really is reachable-and-fatal on this
    // path, so `cancelChecks` completing is a fact about cancelChecks and not
    // about the harness.
    final scheduler = IosCheckScheduler();
    await expectLater(
      scheduler.scheduleChecks(
          1, {0: DateTime.now().add(const Duration(hours: 1))}),
      throwsUnimplementedError,
      reason: 'booking DOES go to the shared task — if this ever stops being '
          'true the assertion below stops meaning anything',
    );
    await expectLater(scheduler.cancelChecks(1), completes);
  });

  test('the Android booking never falls back to an INEXACT wakeup', () {
    // Read off the source, because the rule is an ABSENCE — the same trick
    // `location_picker_test` uses for `getLastKnownPosition`, and the only way
    // to assert a call that isn't there. The fallback existed until
    // 2026-08-15 and could never run: `AlarmService.setOneShot` returns void
    // and books nothing when `canScheduleExactAlarms()` is false, while the
    // channel handler answers `result.success(true)` unconditionally — so
    // `oneShotAt` reported success and the retry was unreachable. Re-adding it
    // would restore dead code, not resilience. Full argument on
    // `AndroidCheckScheduler.scheduleChecks`.
    final source = File('lib/src/check_scheduler.dart').readAsStringSync();
    final code = source
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//') &&
            !l.trimLeft().startsWith('///'))
        .join('\n');
    expect(code, isNot(contains('exact: false')));
    // The control: the EXACT booking is still there, so the assertion above
    // can't pass by the call site having been deleted wholesale.
    expect(code, contains('exact: true'));
  });

  test('the iOS periodic backstop really asks for 15 min — in the Swift', () {
    // **This used to read the Dart constant, and that proved nothing** (fixed
    // 2026-08-30): `frequency:` is ignored on iOS, so the constant said 15 for
    // a fortnight while the Swift asked 30 and the test passed throughout.
    // Reading the file is the only assertion that can fail for the right
    // reason — the same off-disk trick `channel_parity_test` and
    // `ring_manifest_test` use for facts no Dart reference can reach. Why 15,
    // and why Dart cannot set it: `IosCheckScheduler.refreshFrequency`.
    final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final registration = RegExp(
      r'registerPeriodicTask\(\s*withIdentifier:\s*"com\.samyak\.nivaat\.refresh",\s*'
      r'frequency:\s*NSNumber\(value:\s*(\d+)\s*\*\s*60\)',
    ).firstMatch(swift);
    expect(registration, isNotNull,
        reason: 'the periodic task must still be registered in AppDelegate, '
            'in the `NSNumber(value: N * 60)` shape this test reads');
    final swiftFrequency = Duration(minutes: int.parse(registration!.group(1)!));
    // **Two assertions, and they catch different things.** The equality is the
    // sync — it is what the Dart-only version of this test could not do, and
    // what let iOS ask for 30 while the constant read 15. But equality alone
    // passes if BOTH sides drift back to 30, so the value is pinned too: a
    // longer floor is a deliberate red, not a quiet one (2026-08-30).
    expect(swiftFrequency, IosCheckScheduler.refreshFrequency,
        reason: 'the Swift is what iOS obeys; the Dart constant documents it');
    expect(swiftFrequency, const Duration(minutes: 15),
        reason: 'raising it asks iOS for less than the plugin would have asked '
            'for on its own');
  });
}

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
    // Exception guards deliberately do not swallow. `scheduleCheck` is the
    // control: it proves the plugin really is reachable-and-fatal on this
    // path, so `cancelCheck` completing is a fact about cancelCheck and not
    // about the harness.
    final scheduler = IosCheckScheduler();
    await expectLater(
      scheduler.scheduleCheck(1, DateTime.now().add(const Duration(hours: 1))),
      throwsUnimplementedError,
      reason: 'booking DOES go to the shared task — if this ever stops being '
          'true the assertion below stops meaning anything',
    );
    await expectLater(scheduler.cancelCheck(1), completes);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/check_scheduler.dart';

void main() {
  test('AndroidCheckScheduler.initialize swallows plugin failures', () async {
    final scheduler = AndroidCheckScheduler(
      entrypoint: () {},
      initializePlugin: () async => throw StateError('r8/plugin boom'),
    );
    // A throw here used to abort main() before runApp ("keeps stopping").
    await expectLater(scheduler.initialize(), completes);
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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/ui_resync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pingNivaatUiResync is a no-op when the UI port is unregistered', () {
    // Background isolate may finish after the UI has already torn down —
    // must never throw (and must not require a controller).
    expect(pingNivaatUiResync, returnsNormally);
  });
}

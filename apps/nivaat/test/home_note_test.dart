import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/home_screen.dart';

void main() {
  // Properties only. The literal wording lives in `screen_message_test`, which
  // renders the real footer — it was duplicated here too, and on 2026-07-31 an
  // edit to N13 updated one copy and left the other red.
  test('N13 background note soft-wraps (no hard newlines)', () {
    expect(nivaatBackgroundNote.contains('\n'), isFalse,
        reason: 'large accessibility text must reflow — a hard break '
            'overflowed at 2x (2026-07-21)');
  });
}

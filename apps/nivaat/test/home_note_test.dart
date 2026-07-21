import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/home_screen.dart';

void main() {
  test('N10 background note soft-wraps (no hard newlines)', () {
    expect(nivaatBackgroundNote.contains('\n'), isFalse);
    expect(
      nivaatBackgroundNote,
      'Keep the phone charged and online before your '
      'alarm — the background wind check needs both.',
    );
  });
}

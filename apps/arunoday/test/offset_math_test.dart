import 'package:arunoday/src/settings_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bumpOffset — hard stop at ±12h, never wraps', () {
    test('moves within range', () {
      expect(bumpOffset(0, 60), 60);
      expect(bumpOffset(60, -60), 0);
      expect(bumpOffset(700, 60), 720); // clamps to the edge, not past
    });
    test('holds at the edges', () {
      expect(bumpOffset(720, 60), 720); // +12h edge holds
      expect(bumpOffset(-720, -60), -720); // −12h edge holds
    });
  });

  group('offsetAtLimit — feedback for disabling the button', () {
    test('flags only the edge in the bump direction', () {
      expect(offsetAtLimit(720, 60), isTrue); // +1h disabled at +12h
      expect(offsetAtLimit(720, -60), isFalse); // −1h still allowed at +12h
      expect(offsetAtLimit(-720, -60), isTrue); // −1h disabled at −12h
      expect(offsetAtLimit(0, 60), isFalse);
    });
  });

  group('signedBedtimeOffset — folds absolute time to (−720, 720]', () {
    test('near auto', () {
      expect(signedBedtimeOffset(60, 0), 60); // +1h
      expect(signedBedtimeOffset(0, 60), -60); // 00:00 vs 01:00 auto → −1h
    });
    test('the ±12h fold', () {
      expect(signedBedtimeOffset(720, 0), 720); // 12:00 vs 00:00 → +12h
      expect(signedBedtimeOffset(780, 0), -660); // 13:00 → −11h (nearest)
    });
  });

  test('REGRESSION: bedtime +1h at the +12h edge stays put (no −11h flip)', () {
    const auto = 0;
    const atEdge = 720; // 12:00, +12h from auto 00:00
    final off = bumpOffset(signedBedtimeOffset(atEdge, auto), 60); // stays 720
    final absolute = ((auto + off) % 1440 + 1440) % 1440;
    expect(absolute, 720, reason: 'must remain 12:00, NOT flip to 13:00');
    // ...and the button that would do nothing is reported as at-limit.
    expect(offsetAtLimit(signedBedtimeOffset(atEdge, auto), 60), isTrue);
  });

  // The dialog now holds the signed offset directly (like wake), so repeated
  // bumps hard-stop symmetrically instead of wrapping around the clock forever.
  test('REGRESSION: repeated −1h bumps hard-stop at −12h (no infinite wrap)',
      () {
    var off = 0;
    for (var i = 0; i < 30; i++) {
      off = bumpOffset(off, -60);
    }
    expect(off, -720, reason: 'stops at −12h; earlier it folded and looped');
  });

  test('repeated +1h bumps hard-stop at +12h', () {
    var off = 0;
    for (var i = 0; i < 30; i++) {
      off = bumpOffset(off, 60);
    }
    expect(off, 720);
  });

  test('offsetAtLimit disables BOTH ends for a signed offset', () {
    expect(offsetAtLimit(-720, -60), isTrue, reason: '−12h → −1h disabled');
    expect(offsetAtLimit(720, 60), isTrue, reason: '+12h → +1h disabled');
  });
}

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('forecastHourKey keys the alarm instant in UTC, not device-local time',
      () {
    // 14:17 UTC falls in the 14:00 UTC hourly bucket.
    expect(OpenMeteo.forecastHourKey(DateTime.utc(2026, 7, 13, 14, 17)),
        '2026-07-13T14:00');
    // A local DateTime is converted to UTC first — this round-trips regardless
    // of the test machine's timezone, so a court in another tz still maps to
    // the correct hour instead of the phone's wall-clock hour.
    final local = DateTime.utc(2026, 7, 13, 23, 5).toLocal();
    expect(OpenMeteo.forecastHourKey(local), '2026-07-13T23:00');
  });
}

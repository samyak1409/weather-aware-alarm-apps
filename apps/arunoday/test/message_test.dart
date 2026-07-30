import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/home_screen.dart';
import 'package:arunoday/src/messages.dart';
import 'package:arunoday/src/settings_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_test.dart' show FakeScheduler;

/// **Every Arunoday string in MESSAGES.md, locked here.**
///
/// Nivaat's messages have been asserted since 2026-07-22; Arunoday's were not,
/// and the gap was invisible until `nivaatDeleteCourtWarning` shipped an
/// ungrammatical singular that its own doc entry had hidden behind an
/// `{n} alarm(s)` shorthand (2026-07-26). Nothing was stopping the same thing
/// here, in a longer set of branchier strings.
///
/// Two mechanisms, on purpose:
/// * **Composed** strings (branches, counts, optional clauses) are pure
///   builders in `messages.dart` and asserted directly — every branch, since a
///   branch no test renders is a branch nobody reads.
/// * **Static** labels are asserted by rendering the real widget, which also
///   proves the string is actually reachable on screen.
///
/// Worked examples match MESSAGES.md exactly: Jaipur, dawn 06:51, wake offset
/// +0:20 (⇒ 07:11), bedtime 21:56.
void main() {
  final dawn = DateTime(2026, 7, 18, 6, 51);
  final wake = DateTime(2026, 7, 18, 7, 11);

  group('A1 — wake ring', () {
    test('title', () => expect(kArunodayWakeTitle, 'Arunoday · Dawn'));

    test('body names first light only when the wake IS the dawn', () {
      expect(arunodayWakeBody('Jaipur', 0),
          'First light at Jaipur. Good morning.');
    });

    test('body with an offset, never spaced off the word it modifies', () {
      expect(arunodayWakeBody('Jaipur', 20),
          'Dawn+0:20 at Jaipur. Good morning.');
      expect(arunodayWakeBody('Jaipur', -30),
          'Dawn−0:30 at Jaipur. Good morning.');
      expect(arunodayWakeBody('Jaipur', 20), contains('Dawn+0:20 at'),
          reason: '"Dawn +0:20" would read as two values (2026-07-22)');
    });
  });

  group('A2/A3 — bedtime rings', () {
    test('both share one title; the bodies differ', () {
      expect(kArunodayBedtimeTitle, 'Arunoday · Bedtime');
      expect(kArunodayBedtimeBody, 'Wind down — dawn comes early.');
      expect(kArunodayBedtimeAgainBody, 'Second call — dawn does not snooze.');
    });
  });

  group('A4 — bedtime ritual (ring screen)', () {
    test('TOMORROW for the usual evening bedtime', () {
      expect(
        arunodayRitualWakeLine(wake, now: DateTime(2026, 7, 17, 21, 56)),
        'WAKE TOMORROW 07:11',
      );
    });

    test('TODAY when the bedtime itself ran past midnight', () {
      expect(
        arunodayRitualWakeLine(wake, now: DateTime(2026, 7, 18, 0, 30)),
        'WAKE TODAY 07:11',
        reason: 'a post-midnight bedtime wakes you the same calendar day',
      );
    });
  });

  group('A6 — wake line', () {
    test('enabled, counting down', () {
      expect(
        arunodayWakeLine(
          offsetMinutes: 20,
          enabled: true,
          nextWake: wake,
          now: DateTime(2026, 7, 17, 23, 49),
        ),
        'WAKE · DAWN+0:20 · IN 7H 22M',
      );
    });

    test('disabled says OFF instead — never both, never neither', () {
      expect(
        arunodayWakeLine(
            offsetMinutes: 20, enabled: false, nextWake: wake, now: dawn),
        'WAKE · DAWN+0:20 · OFF',
      );
    });

    test('enabled with nothing to count down to just ends', () {
      expect(arunodayWakeLine(offsetMinutes: 0, enabled: true),
          'WAKE · DAWN+0:00');
    });
  });

  group('A7 — bedtime line, five optional clauses', () {
    final bedtime = DateTime(2026, 7, 17, 21, 56);

    test('auto with an offset, sleep tonight, counting down', () {
      expect(
        arunodayBedtimeLine(
          mode: 'Auto+0:30',
          enabled: true,
          sleepMinutes: 525,
          nextRing: bedtime.add(const Duration(hours: 3, minutes: 5)),
          now: bedtime,
        ),
        'BEDTIME · AUTO+0:30 · 8H 45M TONIGHT · IN 3H 05M',
      );
    });

    test('with a pending re-ring, which sits between mode and sleep', () {
      expect(
        arunodayBedtimeLine(
          mode: 'Auto',
          enabled: true,
          again: DateTime(2026, 7, 17, 22, 56),
          sleepMinutes: 495,
          nextRing: bedtime.add(const Duration(minutes: 45)),
          now: bedtime,
        ),
        'BEDTIME · AUTO · AGAIN 22:56 · 8H 15M TONIGHT · IN 0H 45M',
      );
    });

    test('bare — no offset, no re-ring, no sleep, switched off', () {
      expect(
        arunodayBedtimeLine(mode: 'Auto', enabled: false),
        'BEDTIME · AUTO · OFF',
      );
    });

    test('the mode is upper-cased here, not by the caller', () {
      expect(arunodayBedtimeLine(mode: 'Auto+0:30', enabled: true),
          startsWith('BEDTIME · AUTO+0:30'));
    });
  });

  group('A6/A7 — the shared IN label', () {
    test('minute-truncated, so it agrees with the clock above it', () {
      expect(
        arunodayInLabel(wake, now: DateTime(2026, 7, 17, 23, 49, 59)),
        ' · IN 7H 22M',
        reason: 'the stray 59s must not round the minute up',
      );
    });

    test('empty when there is nothing ahead', () {
      expect(arunodayInLabel(null), '');
      expect(arunodayInLabel(dawn, now: wake), '',
          reason: 'already past — no negative countdown');
    });

    test('ALL-CAPS, unlike Nivaat\'s sentence-case twin', () {
      final label = arunodayInLabel(wake, now: dawn);
      expect(label, label.toUpperCase());
    });
  });

  group('A8 — footer', () {
    test('today, with sunrise', () {
      expect(
        arunodayFooterLine(dawn, DateTime(2026, 7, 18, 7, 18), rolled: false),
        'Dawn today 06:51 · Sunrise 07:18',
      );
    });

    test('rolled on to tomorrow once today\'s dawn has passed', () {
      expect(
        arunodayFooterLine(dawn, DateTime(2026, 7, 18, 7, 18), rolled: true),
        'Dawn tomorrow 06:51 · Sunrise 07:18',
      );
    });

    test('no sunrise → no dangling separator', () {
      expect(arunodayFooterLine(dawn, null, rolled: false), 'Dawn today 06:51');
    });
  });

  group('A13/A14/A15 — settings text', () {
    test('A13 yearly sleep readout', () {
      expect(
        arunodaySleepReadout(const SleepPlanResult(
          bedtimeMinutes: 1316,
          minSleepMinutes: 453,
          maxSleepMinutes: 507,
          feasible: true,
        )),
        'Year here: sleep 7h 33m (summer) to 8h 27m (winter) — the natural '
        'swing of dawn at this latitude.',
      );
    });

    test('A14 bedtime hint quotes the plan\'s own bedtime', () {
      // The anchor, not the current setting: it stays quotable — and quoted —
      // however far you have nudged bedtime off it. (A nullable argument here
      // used to render `manual`, naming a state this hint has nothing to do
      // with; removed 2026-07-31.)
      expect(arunodayBedtimePickerHint(1316),
          'auto is 21:56 · tap the time to pick exactly');
    });

    test('A15 wake-offset hint reads anchor first, then result', () {
      expect(arunodayWakeOffsetHint(dawn, 20), 'dawn 06:51 · wake 07:11');
      expect(arunodayWakeOffsetHint(dawn, -30), 'dawn 06:51 · wake 06:21',
          reason: 'a negative offset wakes you before dawn');
    });
  });

  test('X3 — the notifications-off banner names what Arunoday loses', () {
    expect(
      kArunodayNotificationsOff,
      'Notifications are off — a ringing alarm shows nothing on screen '
      '(sound only, no Stop).',
    );
    expect(kArunodayNotificationsOff, isNot(contains('bedtime')),
        reason: 'the bedtime is an ALARM (A2/A3), not a separate reminder — '
            'it still rings, and the ring clause already covers it '
            '(2026-07-31)');
    expect(kArunodayNotificationsOff, isNot(contains('skip')),
        reason: "Arunoday has no wind skips to explain — that wording is "
            "Nivaat's");
  });

  // ── Static labels, asserted by rendering the real widget ──────────────────

  Future<ArunodayController> controller({ArunodaySettings? settings}) async {
    SharedPreferences.setMockInitialValues({});
    final store = ArunodayStore();
    if (settings != null) await store.save(settings);
    final c = ArunodayController(store: store, scheduler: FakeScheduler());
    await c.init();
    return c;
  }

  group('A16 — place-picker refusals', () {
    // Unasserted until 2026-07-31, and worse, duplicated verbatim in the home
    // screen and the settings sheet — two inline copies of one string, neither
    // reachable by a test where it sat. One copy now, on the controller.
    test('polar places are refused before they can be named', () async {
      final c = await controller();
      expect(c.placeRefusal(78.22, 15.63), // Longyearbyen, 78° N
          'No daily dawn here (polar) — Arunoday needs a real dawn.');
      expect(c.placeRefusal(26.91, 75.79), isNull, reason: 'Jaipur is fine');
    });

    test('a second place with the same dawn is refused, and names the first',
        () async {
      final c = await controller(
        settings: const ArunodaySettings(
          locations: [
            SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79)
          ],
          activeLocationId: 'l1',
        ),
      );
      expect(c.placeRefusal(26.91, 75.79),
          'Same dawn as Jaipur — already added.');
      expect(c.placeRefusal(19.08, 72.88), isNull,
          reason: 'Mumbai has its own dawn');
    });
  });

  testWidgets('A5/A9 — empty home names the app and invites a location',
      (tester) async {
    final c = await controller();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pump();

    expect(find.text('ARUNODAY'), findsOneWidget);
    expect(find.text('Wake with the dawn.'), findsOneWidget);
    expect(
      find.text('Add your location — the alarm follows its real dawn, '
          'every day of the year.'),
      findsOneWidget,
    );
    expect(find.text('Add location'), findsOneWidget);

    // Height parity with Nivaat's N14 — the other half of the same claim, see
    // `screen_message_test` (2026-07-31).
    final title = tester.getRect(find.text('Wake with the dawn.'));
    final screen = tester.getRect(find.byType(Scaffold).first);
    expect(title.top, lessThan(screen.height * 0.4),
        reason: 'measured 0.28 — this is the reference the Nivaat side was '
            'brought in line with, so it has to hold here too');
  });

  testWidgets('A10/A11/A12 — settings header, rows and hints', (tester) async {
    // Tall viewport: the settings page is one long ListView, and a child that
    // never scrolls into the 600pt default is never mounted, so `find.text`
    // can't see it. Layout is `design_test`'s job; this test is about strings.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Everything switched on and nudged off its default, because three of
    // these rows only exist when there is something to undo: both long-press
    // hints appear only once an offset is set, and `Bedtime again` only while
    // a "not sleepy" re-ring is pending.
    final c = await controller(
      settings: ArunodaySettings(
        locations: const [
          SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79)
        ],
        activeLocationId: 'l1',
        wakeOffsetMinutes: 20,
        bedtimeOffsetMinutes: 30,
        bedtimeDelayedUntil: DateTime.now().add(const Duration(minutes: 30)),
      ),
    );
    // The settings page is private and pushed by `showSettingsSheet`, so open
    // it the way the app does rather than reaching past the front door.
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSettingsSheet(context, c),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('SETTINGS'), findsOneWidget);
    for (final row in [
      'Wake alarm',
      'Wake offset from dawn',
      'Bedtime alarm',
      'Bedtime',
      'Bedtime again',
      'Alarm sound',
    ]) {
      expect(find.text(row), findsOneWidget, reason: 'A11 row "$row"');
    }
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('LOCATIONS'), findsOneWidget);
    expect(find.text('Not sleepy — tonight only'), findsOneWidget,
        reason: "A11's `Bedtime again` subtitle");
    expect(find.text('Long-press wake offset to reset to dawn.'),
        findsOneWidget);
    expect(find.text('Long-press bedtime to return to auto.'), findsOneWidget);
    // The tone name rides as the row's trailing value (X6's default).
    expect(find.text('Dawn Bells'), findsOneWidget);
  });

  testWidgets('A14/A15 — both pickers, opened the way the app opens them',
      (tester) async {
    // Rendering these two beats asserting their builders alone, and not for
    // coverage: both hints had a second branch documented as what you see
    // "with no location", and neither could ever appear, because there is no
    // settings page without a location. A test that opens the real dialog can
    // only assert what actually renders (2026-07-31).
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final c = await controller(
      settings: const ArunodaySettings(
        locations: [
          SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79)
        ],
        activeLocationId: 'l1',
        wakeOffsetMinutes: 20,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showSettingsSheet(context, c),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // A15 — wake-offset picker. Real dawn, so the clocks are matched by shape.
    await tester.tap(find.text('Wake offset from dawn'));
    await tester.pumpAndSettle();
    expect(find.text('WAKE OFFSET'), findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('· wake ')).data,
      matches(RegExp(r'^dawn \d{2}:\d{2} · wake \d{2}:\d{2}$')),
    );
    expect(find.text('tap the offset to pick the wake time'), findsOneWidget,
        reason: 'the invitation is unconditional — the tap always works');
    for (final b in ['−1h', '+1h', 'Cancel', 'Save']) {
      expect(find.text(b), findsOneWidget, reason: 'A15 button "$b"');
    }
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // A14 — bedtime picker. `find.text` is exact, so this hits the `Bedtime`
    // row, not `Bedtime alarm` or `Bedtime again`.
    await tester.tap(find.text('Bedtime'));
    await tester.pumpAndSettle();
    expect(find.text('BEDTIME'), findsOneWidget);
    expect(
      tester.widget<Text>(find.textContaining('tap the time to pick')).data,
      matches(RegExp(r'^auto is \d{2}:\d{2} · tap the time to pick exactly$')),
    );
    for (final b in ['−1h', '+1h', 'Cancel', 'Save']) {
      expect(find.text(b), findsOneWidget, reason: 'A14 button "$b"');
    }
  });
}

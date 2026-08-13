import 'package:alarm/alarm.dart';
import 'package:arunoday/src/bedtime_actions.dart';
import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/home_screen.dart';
import 'package:arunoday/src/ids.dart';
import 'package:arunoday/src/messages.dart';
import 'package:arunoday/src/settings_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  /// A whole picker countdown line — the number itself is whatever the real
  /// dawn makes it, so the pickers are asserted on the shape.
  final inLabel = RegExp(r'^in \d+h \d{2}m$');

  group('A1 — wake ring', () {
    test('title, with no app name in it', () {
      // The shade already prints "Arunoday" above this line, and iOS shows it
      // inside Arunoday's own AlarmKit alert — so naming the app here read as
      // a stutter (2026-08-13). Nivaat's titles have followed the same rule
      // since 2026-07-22; asserted, not just observed, because the prefix is
      // the kind of thing that grows back.
      expect(kArunodayWakeTitle, 'Dawn');
      expect(kArunodayWakeTitle, isNot(contains('Arunoday')));
    });

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
      expect(kArunodayBedtimeTitle, 'Bedtime');
      expect(kArunodayBedtimeTitle, isNot(contains('Arunoday')));
      expect(kArunodayBedtimeBody, 'Wind down — dawn comes early.');
      // The re-ring counts: `+1h` can be taken again on every re-ring, so a
      // fixed "Second call" was wrong from the third push on (2026-08-13).
      expect(arunodayBedtimeAgainBody(2), 'Second call — dawn does not snooze.');
      expect(arunodayBedtimeAgainBody(3), 'Third call — dawn does not snooze.');
      expect(
          arunodayBedtimeAgainBody(8), 'Eighth call — dawn does not snooze.');
      // The ceiling is worked out, not guessed: pushes are an hour each and
      // refused at the wake, and a bedtime is at most 24h from the wake it
      // protects — wake 00:00 with bedtime 00:01 makes 23:01 the twenty-
      // fourth call and its own push lands past the wake.
      expect(arunodayBedtimeAgainBody(24),
          'Twenty-fourth call — dawn does not snooze.');
      // Past the ordinals — out of reach while the wake alarm is ON, and
      // reachable the moment it is off, since the cap IS the wake.
      expect(arunodayBedtimeAgainBody(25), 'Still up — dawn does not snooze.');
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

  group('A14/A15 — the pickers\' countdown', () {
    test('stands alone, sentence-case, on the same minute-truncated number',
        () {
      // Nivaat's editor exactly, not home's caps strip: it sits under the
      // dialog's own clock among lower-case hints, with no ` · ` to join.
      expect(arunodayPickerInLabel(wake, now: DateTime(2026, 7, 17, 23, 49)),
          'in 7h 22m');
      expect(arunodayPickerInLabel(wake, now: DateTime(2026, 7, 17, 23, 49, 59)),
          'in 7h 22m', reason: 'the stray 59s must not round the minute up');
    });

    test('empty is DEFENCE — neither picker can actually reach it', () {
      // Kept for the same reason home's `—` clocks are (see A6/A7): the
      // honest alternative is a force-unwrap. A bedtime is a clock time and
      // always has a next occurrence, and a drafted wake offset walks the
      // whole window, so even −12h lands on the following morning.
      expect(arunodayPickerInLabel(null), '');
      expect(arunodayPickerInLabel(dawn, now: wake), '');
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

  testWidgets('A4 — the ring-screen ritual: SLEEP LATE, +1h, and the wake it '
      'protects', (tester) async {
    // The wake line had a builder and a test; the two labels beside it were
    // only ever asserted through a stand-in `Text` in core's X1 case, so this
    // widget's own words were unlocked until 2026-08-13 — the day one of them
    // changed. `NOT SLEEPY` named a feeling and read as an excuse; `SLEEP
    // LATE` names the choice (Samyak).
    final c = await controller(
      settings: const ArunodaySettings(
        locations: [
          SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79)
        ],
        activeLocationId: 'l1',
      ),
    );
    // Rebuilt rather than pumped after the edit below: these actions are
    // built once, when the ring screen appears, and nothing changes the wake
    // mid-ring in the app.
    Future<void> show() => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: BedtimeActions(
              controller: c,
              ringingAlarm: AlarmSettings(
                id: ArunodayIds.bedtimeAgain,
                dateTime: DateTime(2026, 7, 17, 21, 56),
                assetAudioPath: 'assets/sounds/arunoday_dawn.wav',
                volumeSettings: VolumeSettings.fixed(),
                notificationSettings: const NotificationSettings(
                  title: 'Bedtime',
                  body: 'Second call — dawn does not snooze.',
                ),
              ),
            ),
          ),
        ));
    // Aim the wake hours out first. Without this the test reads differently
    // at 5am than at 5pm: within an hour of the wake there is no room for a
    // push and the row is deliberately gone (the second half below).
    Future<void> aimWake(int minutes) async {
      final dawn = c.nextWake!
          .subtract(Duration(minutes: c.settings.wakeOffsetMinutes));
      await c.update(c.settings.copyWith(
          wakeOffsetMinutes: DateTime.now()
              .add(Duration(minutes: minutes))
              .difference(dawn)
              .inMinutes));
    }

    await aimWake(360);
    await show();

    expect(find.text('SLEEP LATE'), findsOneWidget,
        reason: 'the label the user reads at bedtime');
    expect(find.text('+1h'), findsOneWidget, reason: 'the only action here');
    expect(find.textContaining('WAKE '), findsOneWidget,
        reason: 'which wake this bedtime is protecting (A4)');

    // With less than an hour left before the wake there is nothing to offer:
    // a push would ring after you were meant to be up (2026-08-13). The wake
    // line stays — that is the sentence the whole ritual is about.
    await aimWake(30);
    await show();
    expect(find.text('SLEEP LATE'), findsNothing);
    expect(find.text('+1h'), findsNothing);
    expect(find.textContaining('WAKE '), findsOneWidget);
  });

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

  testWidgets('A9 — the intro survives a small phone at large text',
      (tester) async {
    // The hero went to 64 on 2026-08-13 and the 1:2 spacer rhythm has no give
    // in it: measured 55px over the bottom of a 375pt phone at 1.3x, and the
    // OLD 28px was already 432px over at 2x — so this was broken for anyone
    // with large text before the size was ever touched. It fills the screen
    // when it fits and scrolls when it does not.
    tester.view.physicalSize = const Size(375, 667); // the smallest we support
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await controller();

    for (final scale in [1.0, 1.3, 2.0]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: HomeScreen(controller: c),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflowed at ${scale}x');
      expect(find.text('Wake with the dawn.'), findsOneWidget);
    }
  });

  testWidgets('A6/A7/A8 — the ARMED home survives large text too',
      (tester) async {
    // The empty intro got its fills-or-scrolls guard first, and the armed
    // screen — which carries a 72pt clock, a 40pt one and four label lines —
    // did not. Measured on a 375pt phone it ran 30px over at 1.3x (a break
    // this size pass introduced) and 718px at 2x (483px before it).
    tester.view.physicalSize = const Size(375, 667);
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

    for (final scale in [1.0, 1.3, 2.0]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: HomeScreen(controller: c),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflowed at ${scale}x');
      expect(find.textContaining('WAKE · DAWN'), findsOneWidget);
      // The hero is `FittedBox`ed like the ring clock, so it shrinks rather
      // than wrapping — and a wrap would be silent now that this column
      // scrolls. `maxLines: 1` is what turns a wrap into this flag.
      final hero = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(FittedBox), matching: find.byType(RichText)));
      expect(hero.didExceedMaxLines, isFalse,
          reason: 'the wake clock must never wrap at ${scale}x');
    }
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
    // a "sleep late" re-ring is pending.
    final c = await controller(
      settings: const ArunodaySettings(
        locations: [
          SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79)
        ],
        activeLocationId: 'l1',
        wakeOffsetMinutes: 20,
      ),
    );
    // The bedtime is pinned ten minutes BEHIND now, which is where a bedtime
    // that has just rung sits — a pending re-ring is dropped when the bedtime
    // moves past it (2026-08-13), so a fixed offset would delete this row for
    // an hour every evening and the test would fail only then.
    final auto = c.plan!.bedtimeMinutes.round();
    final justRang = DateTime.now().subtract(const Duration(minutes: 10));
    await c.update(c.settings.copyWith(
      bedtimeOffsetMinutes: () =>
          (justRang.hour * 60 + justRang.minute - auto) % 1440,
      bedtimeDelayedUntil: () => DateTime.now().add(const Duration(minutes: 30)),
    ));
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
    expect(find.text('Sleep late — tonight only'), findsOneWidget,
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
    // The countdown to what this offset would ARM, live under the offset
    // itself (2026-08-13). By shape, since the real dawn decides the number —
    // and exactly one, because the slot is built even when it is empty.
    expect(find.textContaining(inLabel), findsOneWidget,
        reason: 'A15 countdown');
    // Nudging redraws it: this is feedback on the draft, not a readout of
    // what is already saved.
    final before = tester.widget<Text>(find.textContaining(inLabel)).data;
    await tester.tap(find.text('+1h'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.textContaining(inLabel)).data,
        isNot(before));
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
    expect(find.textContaining(inLabel), findsOneWidget,
        reason: 'A14 countdown — a bedtime always has a next occurrence');
    for (final b in ['−1h', '+1h', 'Cancel', 'Save']) {
      expect(find.text(b), findsOneWidget, reason: 'A14 button "$b"');
    }
  });
}

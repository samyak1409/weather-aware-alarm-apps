import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/main.dart';
import 'package:nivaat/src/alarm_sheet.dart';
import 'package:nivaat/src/background_banner.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/courts_sheet.dart';
import 'package:nivaat/src/history_sheet.dart';
import 'package:nivaat/src/home_screen.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// **Nivaat's on-screen strings (MESSAGES.md N12–N22), locked by rendering.**
///
/// The notification and history *text* has been asserted since 2026-07-22
/// (`notification_message_test`, `morning_story_test`); the screens had not
/// been, so a label could drift from its doc entry unnoticed — the same gap
/// that let `nivaatDeleteCourtWarning` ship an ungrammatical singular. Every
/// composed string still belongs in a builder; these are the flat labels, and
/// rendering them also proves each one is actually reachable.
void main() {
  const court =
      SavedLocation(id: 'c1', name: 'Society Court', lat: 26.17, lon: 75.79);

  Future<NivaatController> controller({
    List<SavedLocation> courts = const [],
    List<NivaatAlarm> alarms = const [],
  }) async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    if (courts.isNotEmpty) await store.saveCourts(courts);
    if (alarms.isNotEmpty) await store.saveAlarms(alarms);
    final c = NivaatController(engine: silentEngine(store));
    await c.init();
    return c;
  }

  /// Opens a sheet the way the app does, rather than reaching past its door.
  Future<void> openVia(
    WidgetTester tester,
    void Function(BuildContext) open,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('N12/N14 — empty home names the app and the promise',
      (tester) async {
    final c = await controller();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pump();

    expect(find.text('NIVAAT'), findsOneWidget);
    expect(find.text('The windless alarm.'), findsOneWidget);
    expect(
      find.text('Rings only when the wind at your court is low enough to '
          'play. The calmer the morning, the louder it rings.'),
      findsOneWidget,
    );

    // Height parity with Arunoday's A9 (2026-07-31): both intros sit a third
    // down, not centred. Asserted from both sides — `message_test`'s A9 case
    // pins the same bound — because "the same screen in two apps" is a claim
    // no single app's test can make, and this one drifted once already.
    final title = tester.getRect(find.text('The windless alarm.'));
    final screen = tester.getRect(find.byType(Scaffold).first);
    expect(title.top, lessThan(screen.height * 0.4),
        reason: 'measured 0.35 with the 1:2 rhythm, 0.46 when centred — the '
            'bound sits between so centring cannot come back');
  });

  testWidgets('N14 — the intro survives a small phone at large text',
      (tester) async {
    // Twin of Arunoday's A9 case, and for the same reason: the hero went to
    // 64 on 2026-08-13, the 1:2 spacer rhythm has no give, and at a raised
    // system text size the sentence ran off the bottom — already true at the
    // old 28px at 2x. Fills when it fits, scrolls when it does not.
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
      expect(find.text('The windless alarm.'), findsOneWidget);
    }
  });

  testWidgets('N13 — the background caveat rides the armed home', (tester) async {
    final c = await controller(
      courts: [court],
      alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
    );
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
    await tester.pump();

    expect(find.text(nivaatBackgroundNote), findsOneWidget);
    expect(
        nivaatBackgroundNote,
        'Make sure the phone has enough battery and is connected to the '
        'internet before your alarm — the background wind check needs both.');
    expect(nivaatBackgroundNote, isNot(contains('online')),
        reason: '"online" reads as SIGNED IN to a general user, and this app '
            'has no account to sign in to (2026-07-31)');
  });

  testWidgets('N11 — an alarm row does not overrun at large text',
      (tester) async {
    // The row's clock went 28 → 40 on 2026-08-13 and clock + countdown +
    // switch then overran the row by 34px at 1.3x on a 375pt phone. (The
    // outer column still overflows at 2.0x — that predates the size change
    // and is not what this pins.)
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await controller(
      courts: [court],
      alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
    );

    for (final scale in [1.0, 1.3]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: HomeScreen(controller: c),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflowed at ${scale}x');
      expect(find.text('06:00'), findsOneWidget);
      // **Whole, not ellipsized.** `findsOneWidget` above passes either way —
      // a `Text` truncated to `06:…` still carries the full string — and no
      // exception is thrown for an ellipsis, so the squeeze has to be checked
      // by measuring: the clock is `FittedBox`ed, so it scales down inside its
      // share instead of losing digits.
      final painted = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text('06:00'), matching: find.byType(RichText)));
      expect(painted.didExceedMaxLines, isFalse,
          reason: 'the time must never be cut short at ${scale}x');
    }
  });

  test('N16 — both background-throttled variants', () {
    expect(
      kNivaatBackgroundThrottledAndroid,
      "Battery optimisation can delay or skip Nivaat's background wind "
      'checks — it could miss a wind change and ring on a windy morning, or '
      'stay silent on a calm one.',
    );
    expect(
      kNivaatBackgroundThrottledIos,
      'Background App Refresh is off — Nivaat can only check the wind while '
      'the app is open.',
    );
  });

  testWidgets('N19 — courts sheet header and empty state', (tester) async {
    final c = await controller();
    await openVia(tester, (context) => showCourtsSheet(context, c));

    expect(find.text('COURTS'), findsOneWidget);
    expect(
      find.text('Save your courts — each alarm checks the wind at its own '
          'court.'),
      findsOneWidget,
    );
  });

  testWidgets('N19 — a saved court shows its name over its coordinates',
      (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showCourtsSheet(context, c));

    expect(find.text('Society Court'), findsOneWidget);
    expect(find.text('26.170, 75.790'), findsOneWidget,
        reason: 'three decimals — MESSAGES.md N19');
  });

  test('N21 — a second court in the same area is refused, naming the first',
      () async {
    // Extracted off the courts sheet on 2026-07-31: it was built inline in a
    // `validate:` closure, so nothing could name it. The radius is ~100 m and
    // 0.001° of latitude is ~111 m, which is what these coordinates step by.
    final c = await controller(courts: [court]);
    expect(c.courtRefusal(26.17, 75.79),
        'Same area as Society Court — already added.');
    expect(c.courtRefusal(26.1705, 75.79), isNotNull,
        reason: '~56 m away is the same court');
    expect(c.courtRefusal(26.1715, 75.79), isNull,
        reason: '~167 m away is a different one — courts do sit close');
  });

  testWidgets('history sheet header and empty state', (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showHistorySheet(context, c));

    expect(find.text('HISTORY'), findsOneWidget);
    expect(
      find.text('Every ring and skip lands here, with the wind that caused '
          'it.'),
      findsOneWidget,
    );
  });

  testWidgets('N22 — settings page tiles, in their locked order',
      (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showSettingsSheet(context, c));

    expect(find.text('SETTINGS'), findsOneWidget);
    for (final tile in ['Courts', 'Alarm sound', 'History']) {
      expect(find.text(tile), findsOneWidget, reason: 'tile "$tile"');
    }
    expect(find.text('Court Call'), findsOneWidget,
        reason: "the default tone name rides as Alarm sound's trailing (X6)");
    expect(find.text('APPEARANCE'), findsOneWidget);
    // Configure → observe → decorate: courts, tone, log, then appearance.
    expect(
      tester.getCenter(find.text('Courts')).dy,
      lessThan(tester.getCenter(find.text('History')).dy),
    );
  });

  testWidgets('N17 — the alarm editor names every control', (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showAlarmSheet(context, c, alarm: null));

    expect(find.text('NEW ALARM'), findsOneWidget);
    expect(find.text('Court'), findsOneWidget);
    expect(find.text('Max wind at court'), findsOneWidget);
    // The gust guard is derived, not chosen: 2.2 × (limit / 0.6). A NEW alarm
    // starts at the default limit 6 → ≤22; MESSAGES.md's `≤15` example is the
    // worked example's limit 4, asserted in the edit test below.
    expect(find.text('Gust guard auto: ≤22 km/h'), findsOneWidget);
    expect(find.text('Keep checking'), findsOneWidget);
    expect(find.text('Rings late if the wind drops in time.'), findsOneWidget,
        reason: 'the hint states the payoff — why 60m over 30m');
    for (final segment in ['30m', '60m']) {
      expect(find.text(segment), findsOneWidget);
    }
    expect(find.text('1m'), findsNothing,
        reason: 'a one-minute window is a testing tool — it appears only '
            'behind core DevMode\'s seven-tap gate (2026-08-06)');
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Delete'), findsNothing,
        reason: 'a new alarm has nothing to delete');
  });

  group('N17 — the dev-gated one-minute window', () {
    // A static notifier outlives the test that flipped it; a leaked `true`
    // would make the assertion above pass or fail depending on test order.
    tearDown(() => DevMode.enabled.value = false);

    testWidgets('the gate open puts 1m back in the control', (tester) async {
      DevMode.enabled.value = true;
      final c = await controller(courts: [court]);
      await openVia(tester, (ctx) => showAlarmSheet(ctx, c, alarm: null));

      for (final segment in ['1m', '30m', '60m']) {
        expect(find.text(segment), findsOneWidget, reason: 'segment $segment');
      }
    });

    testWidgets('an alarm already on 1m still shows it with the gate shut',
        (tester) async {
      // Otherwise the control would draw with no segment selected and
      // misrepresent the alarm — the 1m is real until you change it, and the
      // cascade goes on honouring it whatever the editor offers.
      final c = await controller(courts: [court]);
      const short = NivaatAlarm(
          id: 1, hour: 6, minute: 0, courtId: 'c1', retryMinutesAfter: 1);
      await openVia(tester, (ctx) => showAlarmSheet(ctx, c, alarm: short));

      expect(DevMode.enabled.value, isFalse, reason: 'the gate is shut');
      expect(find.text('1m'), findsOneWidget);
    });
  });

  testWidgets('N17 — day chips are Mon-first single letters', (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showAlarmSheet(context, c, alarm: null));

    // M T W T F S S — T and S each appear twice, which is the point of
    // documenting them rather than assuming a reader infers the order.
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);
    expect(find.text('T'), findsNWidgets(2));
    expect(find.text('S'), findsNWidgets(2));
  });

  testWidgets('N17 — editing an existing alarm offers Delete', (tester) async {
    final c = await controller(
      courts: [court],
      alarms: const [
        NivaatAlarm(
            id: 1, hour: 6, minute: 0, courtId: 'c1', courtSpeedLimitKmh: 4)
      ],
    );
    await openVia(tester,
        (context) => showAlarmSheet(context, c, alarm: c.alarms.first));

    expect(find.text('EDIT ALARM'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Gust guard auto: ≤15 km/h'), findsOneWidget,
        reason: "MESSAGES.md's worked example — limit 4");
  });

  testWidgets('the ring gate sits ABOVE the settings page (2026-08-13)',
      (tester) async {
    // Device-caught in both apps: `RingGate` wrapped `home:`, which is the
    // first ROUTE, so an open settings page covered the ring screen — the
    // alarm sounded with nothing on screen until you pressed back, and
    // tapping the ring notification looked like it did nothing. It lives in
    // `MaterialApp.builder` now, above the Navigator. Structural, because
    // only a device can make the plugin actually ring.
    final c = await controller(
      courts: [court],
      alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
    );
    await tester.pumpWidget(NivaatApp(
      controller: c,
      permissionFlow: Future<void>.value(),
      batteryFlow: Future<void>.value(),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
          of: find.byType(RingGate), matching: find.text('SETTINGS')),
      findsOneWidget,
      reason: 'a pushed route must sit INSIDE the gate, or the ring screen '
          'cannot cover it',
    );

    // See off the scrollbar's flash (a `Future.delayed`, so unmounting will
    // not cancel it) and then the home ticker, which dispose does.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('X1 — the court the ring screen names', () {
    // `main` hands `RingGate.alarmLabel` this lookup; core renders it above
    // the clock (`shared_message_test`). What lands here is the number the
    // plugin gives the ring screen, which is a LOCKER id, not an alarm id.
    Future<NivaatController> armed() => controller(
          courts: [court],
          alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
        );

    test('every ring locker resolves to the same court', () async {
      final c = await armed();
      for (final id in NivaatIds.allRings(1)) {
        expect(c.courtNameForRing(id), 'Society Court', reason: 'locker $id');
      }
    });

    test('checks and cards are not rings, and neither is a gone alarm',
        () async {
      final c = await armed();
      // Same alarm, different blocks: reading one of these as a ring would
      // put another alarm's court on the screen.
      expect(c.courtNameForRing(NivaatIds.check(1)), isNull);
      expect(c.courtNameForRing(NivaatIds.card(1)), isNull);
      // Deleted mid-ring, or a ring left over from a build ago: the label is
      // the one thing on this screen that may be missing, so it goes quiet
      // rather than guessing.
      expect(c.courtNameForRing(NivaatIds.ring(2)), isNull);
    });
  });
}

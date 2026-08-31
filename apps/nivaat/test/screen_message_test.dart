import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/main.dart';
import 'package:nivaat/src/alarm_sheet.dart';
import 'package:nivaat/src/background_banner.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/courts.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/history_sheet.dart';
import 'package:nivaat/src/home_screen.dart';
import 'package:nivaat/src/ids.dart';
import 'package:nivaat/src/settings_sheet.dart';
import 'package:nivaat/src/skip_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// **Nivaat's on-screen strings (MESSAGES.md N12–N22), locked by rendering.**
///
/// The notification and history *text* has been asserted since 2026-07-22
/// (`notification_message_test`, `occurrence_story_test`); the screens had not
/// been, so a label could drift from its doc entry unnoticed — the same gap
/// that let `nivaatDeleteCourtWarning` ship an ungrammatical singular. Every
/// composed string still belongs in a builder; these are the flat labels, and
/// rendering them also proves each one is actually reachable.
void main() {
  const court =
      SavedLocation(id: 'c1', name: 'Society Court', lat: 26.17, lon: 75.79);

  // **Reduce motion is on for this whole file.**
  //
  // The home row's live dot breathes forever (`_HomeScreenState._breath`), and
  // an endless animation schedules frames forever, so `pumpAndSettle` never
  // settles — it spins until it times out, which is exactly how this arrived.
  // Flipping the platform switch is the honest fix rather than teaching the
  // widget it is under test: it is the same setting someone sensitive to
  // looping motion turns on, the widget already obeys it, and obeying it is
  // itself worth testing. The one test that has to watch the dot move turns
  // the switch back off for itself.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  });

  Future<NivaatController> controller({
    List<SavedLocation> courts = const [],
    List<NivaatAlarm> alarms = const [],
    OpenMeteo? api,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    if (courts.isNotEmpty) await store.saveCourts(courts);
    if (alarms.isNotEmpty) await store.saveAlarms(alarms);
    final c = NivaatController(engine: silentEngine(store, api: api));
    await c.init();
    return c;
  }

  /// Opens a sheet the way the app does, rather than reaching past its door.
  ///
  /// [tall] gives the settings page room: it is one long `ListView` and COURTS
  /// is its last section, so on the default 600pt viewport those rows are never
  /// mounted and `find.text` cannot see them. Layout is `design_test`'s job;
  /// these tests are about strings.
  Future<void> openVia(
    WidgetTester tester,
    void Function(BuildContext) open, {
    bool tall = false,
  }) async {
    if (tall) {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }
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
          'play. The calmer the wind, the louder it rings.'),
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
          // A fresh `MediaQueryData` drops the ambient reduce-motion flag
          // the file's `setUp` turned on, so say it again here.
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
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
          // A fresh `MediaQueryData` drops the ambient reduce-motion flag
          // the file's `setUp` turned on, so say it again here.
          data: MediaQueryData(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
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
      "checks — it could miss a wind change and ring when it's windy, or stay "
      "silent when it's calm.",
    );
    expect(
      kNivaatBackgroundThrottledIos,
      'Background App Refresh is off — Nivaat can only check the wind while '
      'the app is open.',
    );
  });

  testWidgets('N19 — COURTS is a section of settings, with its empty state',
      (tester) async {
    // It was a bottom sheet behind a `Courts` tile until 2026-08-15. The tile
    // and the sheet are both gone: the section lives on the settings page the
    // way Arunoday's LOCATIONS always has.
    final c = await controller();
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    expect(find.text('COURTS'), findsOneWidget);
    expect(find.text(kNivaatNoCourtsYet), findsOneWidget);
    expect(kNivaatNoCourtsYet,
        'Save your courts — each alarm checks the wind at its own court.');
    expect(find.text('Courts'), findsNothing,
        reason: 'the tile that used to open the sheet is gone with it');
  });

  testWidgets('N19 — a saved court shows its name over its coordinates',
      (tester) async {
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    expect(find.text('Society Court'), findsOneWidget);
    expect(find.text('26.170, 75.790'), findsOneWidget,
        reason: 'three decimals — MESSAGES.md N19');
  });

  testWidgets('X5 — the ⓘ on a court says where it came from', (tester) async {
    // The row shows the name you saved and the coordinates; neither says
    // whether those came off the map or off the phone, and two courts you
    // named the same thing are indistinguishable without it (2026-08-15).
    final c = await controller(courts: [
      const SavedLocation(
        id: 'c1',
        name: 'Society Court',
        lat: 26.17,
        lon: 75.79,
        region: 'Rajasthan, India',
      ),
    ]);
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Rajasthan, India'), findsOneWidget);

    // See the toast off, or its timer outlives the test.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('X5 — a GPS court says so instead', (tester) async {
    final c = await controller(courts: [
      const SavedLocation(
        id: 'c1',
        name: 'Home Court',
        lat: 26.17,
        lon: 75.79,
        source: PlaceSource.gps,
      ),
    ]);
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.text('Saved using GPS'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('N19 — a court row survives a narrow phone at large text',
      (tester) async {
    // The row grew a second trailing button on 2026-08-15 (the ⓘ beside the
    // bin) on top of a two-line title, and this exact shape is what tripped
    // `ListTile`'s trailing-overflow assert on the Court row of the alarm
    // editor at 2x on a 390pt phone. 375 wide is the narrowest we support;
    // tall so COURTS — the page's last section — is mounted at all.
    tester.view.physicalSize = const Size(375, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final c = await controller(courts: [court]);

    for (final scale in [1.0, 1.3, 2.0]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettingsSheet(context, c),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflowed at ${scale}x');
      expect(find.text('Society Court'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('N20 — deleting a court asks first, and Cancel keeps it',
      (tester) async {
    final c = await controller(
      courts: [court],
      alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
    );
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text('DELETE COURT'), findsOneWidget);
    expect(find.text(nivaatDeleteCourtWarning('Society Court', 1, 0)),
        findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.courts, hasLength(1), reason: 'Cancel means cancel');
  });

  testWidgets('N20 — a court with nothing on it is asked about too',
      (tester) async {
    // It used to delete straight away when there were no alarms and no
    // history (2026-08-15, Samyak). The row does not say whether an alarm
    // points here, so "nothing to warn about" was a decision the app was in
    // no position to make on the user's behalf.
    final c = await controller(courts: [court]);
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text(nivaatDeleteCourtWarning('Society Court', 0, 0)),
        findsOneWidget);
    expect(c.courts, hasLength(1), reason: 'nothing gone before the answer');

    // The control — without it this would pass against a bin that had been
    // disabled outright.
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(c.courts, isEmpty);
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
    await openVia(tester, (context) => showSettingsSheet(context, c), tall: true);

    expect(find.text('SETTINGS'), findsOneWidget);
    for (final tile in ['Alarm sound', 'History']) {
      expect(find.text(tile), findsOneWidget, reason: 'tile "$tile"');
    }
    expect(find.text('Court Call'), findsOneWidget,
        reason: "the default tone name rides as Alarm sound's trailing (X6)");
    expect(find.text('APPEARANCE'), findsOneWidget);
    // X4 rides every screen, not just home (2026-08-15) — and it carries the
    // seven-tap developer gate, so a copy of the LINE would not do.
    // **Pinned, not scrolled** (2026-08-15): the mark sits outside the
    // ListView, the way it does on home, so a long courts list cannot push it
    // off the page and the seven-tap gate stays reachable.
    expect(find.byType(CraftedBy), findsOneWidget);
    expect(
      find.ancestor(of: find.byType(CraftedBy), matching: find.byType(ListView)),
      findsNothing,
      reason: 'inside the ListView it scrolls away with the last section',
    );
    // Log, tone, appearance, then the saved places — the running order
    // Arunoday's page has, which ends on LOCATIONS (2026-08-15, Samyak).
    // History leads because it is the row you open this page to READ.
    // Asserted as a chain: any pair alone would survive the wrong order.
    final order = [
      for (final label in ['History', 'Alarm sound', 'APPEARANCE', 'COURTS'])
        tester.getCenter(find.text(label)).dy
    ];
    for (var i = 1; i < order.length; i++) {
      expect(order[i - 1], lessThan(order[i]),
          reason: 'settings section $i is out of order');
    }
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
    // States the CONDITION as well as the payoff. "Rings late if the wind
    // drops in time." said what it does but never what triggers it, and
    // "rings late" read as a defect rather than a rescue (Samyak, 2026-08-25).
    expect(
        find.text("If it's too windy, keep watching this long and ring when "
            'the wind drops.'),
        findsOneWidget);

    // The play window (2026-08-25). The hint leads with the ANCHOR: it used
    // to open with the activities and name what they were measured from only
    // in its second sentence, so `in 23h 45m` two rows above won and 30m read
    // as half an hour from NOW.
    expect(find.text('Time until you play'), findsOneWidget);
    expect(
        find.text('Starts when the alarm rings — getting ready, travel, '
            'warm-up.'),
        findsOneWidget);
    expect(find.text('Minimum play time'), findsOneWidget);
    expect(
        find.text(
            'The alarm only rings if the wind stays low for this whole time.'),
        findsOneWidget);

    // Three rows offer the same two segments now, so the count IS the
    // assertion — one per row, and no stray fourth control.
    for (final segment in ['30m', '60m']) {
      expect(find.text(segment), findsNWidgets(3), reason: 'segment $segment');
    }
    expect(find.text('15m'), findsNothing,
        reason: 'a 15-minute window is a testing tool — it appears only '
            'behind core DevMode\'s seven-tap gate (2026-08-06)');
    expect(find.text('1m'), findsNothing,
        reason: 'the dev window became 15m on 2026-08-25 — retries land every '
            '15 minutes, so a one-minute window holds no retry at all');
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Delete'), findsNothing,
        reason: 'a new alarm has nothing to delete');
  });

  group('N17 — IF YOU SAVE THIS, the timeline above Save (2026-08-25)', () {
    // Everything hangs off the alarm going off at its SET time. The first
    // draft did not, and read `04:00 – 04:30 keeps checking` above `04:30
    // you're on court` — which says the alarm may ring at 04:30 and that you
    // are on court at 04:30, with a half hour of lead time between them.
    // Caught by Samyak; this group is what stops it coming back.
    const alarm = NivaatAlarm(
      id: 1,
      hour: 4,
      minute: 0,
      courtId: 'c1',
      courtSpeedLimitKmh: 6,
    );

    test('three steps, anchored on the alarm ringing at its set time', () {
      final timeline = nivaatAlarmTimeline(alarm);
      expect(timeline.steps, [
        ('04:00', 'alarm'),
        ('04:30', "you're on court"),
        ('04:30 – 05:00', 'wind must stay ≤6 km/h'),
      ]);
      // ≤, not "under": `decideSlot` skips on `> limit`, so exactly 6 rings.
      expect(timeline.steps.last.$2, contains('≤'));
    });

    test('the retry note is a footnote on the ring, not a fourth step', () {
      expect(nivaatAlarmTimeline(alarm).note,
          "if it's too windy, it keeps checking until 04:30 — "
          'the times below move with it');
    });

    test('"the times below move with it" is literally true', () {
      // The note is a promise about the engine, so check it against the
      // engine: `playWindow` is measured from the moment the alarm REALLY
      // rings, so a ring rescued a quarter hour late moves the whole
      // window a quarter hour later — not a simplification.
      final onTime = alarm.playWindow(DateTime(2026, 8, 25, 4, 0));
      final rescued = alarm.playWindow(DateTime(2026, 8, 25, 4, 15));
      expect(rescued.$1.difference(onTime.$1), const Duration(minutes: 15));
      expect(rescued.$2.difference(onTime.$2), const Duration(minutes: 15));
    });

    test('every step moves when the setting behind it moves', () {
      // One assertion per row, so a row wired to the wrong field is caught
      // rather than a whole timeline that happens to look plausible.
      expect(
          nivaatAlarmTimeline(alarm.copyWith(timeUntilPlayMinutes: 60)).steps,
          [
            ('04:00', 'alarm'),
            ('05:00', "you're on court"),
            ('05:00 – 05:30', 'wind must stay ≤6 km/h'),
          ]);
      expect(nivaatAlarmTimeline(alarm.copyWith(minPlayMinutes: 60)).steps.last,
          ('04:30 – 05:30', 'wind must stay ≤6 km/h'));
      expect(nivaatAlarmTimeline(alarm.copyWith(retryMinutesAfter: 60)).note,
          contains('until 05:00'));
      expect(
          nivaatAlarmTimeline(alarm.copyWith(courtSpeedLimitKmh: 4))
              .steps
              .last
              .$2,
          'wind must stay ≤4 km/h');
    });

    test('a late-evening alarm reads 00:15, never 24:15', () {
      // Going through `DateTime` rather than adding minutes to an hour is the
      // whole reason — the same wrap `nivaatSeedAlarmTime` needs.
      expect(nivaatAlarmTimeline(alarm.copyWith(hour: 23, minute: 30)).steps,
          [
            ('23:30', 'alarm'),
            ('00:00', "you're on court"),
            ('00:00 – 00:30', 'wind must stay ≤6 km/h'),
          ]);
    });

    testWidgets('it renders above Save, in the editor\'s own numbers',
        (tester) async {
      final c = await controller(courts: [court]);
      await openVia(
          tester,
          (ctx) => showAlarmSheet(ctx, c,
              alarm: const NivaatAlarm(
                  id: 1,
                  hour: 4,
                  minute: 0,
                  courtId: 'c1',
                  courtSpeedLimitKmh: 6)));

      // Not "YOUR MORNING": the codebase called an occurrence a morning
      // everywhere, and that leaked onto a screen where it is simply wrong —
      // nothing stops you setting this alarm for 15:00 (Samyak, 2026-08-25;
      // the prose behind it was swept on 2026-08-30).
      // And not the "WHAT HAPPENS" that first replaced it: this block
      // describes the DRAFT on screen, not an alarm as saved.
      expect(find.text('IF YOU SAVE THIS'), findsOneWidget);
      expect(find.textContaining('MORNING'), findsNothing);
      final timeline = nivaatAlarmTimeline(alarm);
      for (final step in timeline.steps) {
        expect(find.text(step.$2), findsOneWidget, reason: step.$2);
      }
      expect(find.text(timeline.note), findsOneWidget);
      expect(find.text('04:30 – 05:00'), findsOneWidget,
          reason: 'the play window reads as one range, not two times');
    });
  });

  group('N17 — the dev-gated short window', () {
    // A static notifier outlives the test that flipped it; a leaked `true`
    // would make the assertion above pass or fail depending on test order.
    tearDown(() => DevMode.enabled.value = false);

    testWidgets('the gate open puts 15m back in the control', (tester) async {
      // 15, not 1, since 2026-08-25: retries land every 15 minutes, so a
      // one-minute window would hold no retry at all and test nothing.
      DevMode.enabled.value = true;
      final c = await controller(courts: [court]);
      await openVia(tester, (ctx) => showAlarmSheet(ctx, c, alarm: null));

      // **All three minutes rows gain it** (Samyak, 2026-08-25). It was Keep
      // checking's alone, which made a test occurrence only half-fast: the
      // retry window shrank to a quarter hour while the play window it was
      // retrying stayed half an hour out and half an hour long.
      for (final segment in ['15m', '30m', '60m']) {
        expect(find.text(segment), findsNWidgets(3), reason: 'segment $segment');
      }
    });

    testWidgets('an alarm already on 15m still shows it with the gate shut',
        (tester) async {
      // Otherwise the control would draw with no segment selected and
      // misrepresent the alarm — the 15m is real until you change it, and the
      // cascade goes on honouring it whatever the editor offers.
      final c = await controller(courts: [court]);
      const short = NivaatAlarm(
          id: 1, hour: 6, minute: 0, courtId: 'c1', retryMinutesAfter: 15);
      await openVia(tester, (ctx) => showAlarmSheet(ctx, c, alarm: short));

      expect(DevMode.enabled.value, isFalse, reason: 'the gate is shut');
      // Exactly one: the alarm holding 15m, not the other two rows — the gate
      // decides what is OFFERED, and it is shut.
      expect(find.text('15m'), findsOneWidget);
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

  group('N17 — Delete asks first (2026-08-15)', () {
    test('the warning names the alarm, and what survives it', () {
      // Rows outlive their alarm — only deleting the COURT removes them — so
      // the count is the reassuring half, not decoration.
      expect(nivaatDeleteAlarmWarning('06:00', 'Society Court', 0),
          'The 06:00 alarm at Society Court will be deleted. Continue?');
      // The verb agrees with the count, which is the exact thing N20's
      // singular got wrong for a fortnight.
      expect(
        nivaatDeleteAlarmWarning('06:00', 'Society Court', 1),
        'The 06:00 alarm at Society Court will be deleted. Its 1 history '
        'entry stays in the log. Continue?',
      );
      expect(
        nivaatDeleteAlarmWarning('06:30', 'Society Court', 12),
        'The 06:30 alarm at Society Court will be deleted. Its 12 history '
        'entries stay in the log. Continue?',
      );
      // The no-court branch was cut on 2026-08-15: deleting a court deletes
      // its alarms in the same step and only the UI isolate writes the alarm
      // list, so an alarm cannot outlive its court.
      expect(nivaatDeleteAlarmWarning('06:00', 'Society Court', 0),
          contains('at Society Court'));
    });

    test('the count is the ALARM\'s own rows, not its court\'s', () async {
      // Two alarms on one court, and the dialog must not count the other
      // alarm's rows in what it quotes. Alarm ids are never reissued (REVIEW
      // #9), so this survives every edit to time and court.
      final c = await controller(courts: [court]);
      await c.upsertAlarm(
          const NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'));
      await c.upsertAlarm(
          const NivaatAlarm(id: 2, hour: 7, minute: 0, courtId: 'c1'));
      for (final row in [
        (1, DateTime(2026, 8, 14, 6)),
        (1, DateTime(2026, 8, 15, 6)),
        (2, DateTime(2026, 8, 15, 7)),
      ]) {
        await c.store.upsertHistory(HistoryRecord(
          alarmId: row.$1,
          courtId: 'c1',
          at: row.$2,
          outcome: CheckOutcome.rang,
          checkedAt: row.$2,
          pushSeq: 1,
        ));
      }
      await c.resync();

      expect(c.historyForAlarm(1), 2);
      expect(c.historyForAlarm(2), 1);
      expect(c.historyForCourt('c1'), 3,
          reason: 'the court total is the sum — and NOT what this dialog says');
    });

    testWidgets('Cancel keeps the alarm; Delete takes it', (tester) async {
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      Future<void> open() => openVia(tester,
          (ctx) => showAlarmSheet(ctx, c, alarm: c.alarms.first));

      // The sheet scrolls, and the play-window rows (2026-08-25) pushed the
      // buttons past the fold on this surface — scroll to them rather than
      // widening the test viewport, since a real phone scrolls too.
      Future<void> reachButtons() async {
        await tester.scrollUntilVisible(
            find.widgetWithText(TextButton, 'Delete').first, 200,
            scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
      }

      await open();
      await reachButtons();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('DELETE ALARM'), findsOneWidget);
      expect(find.text(nivaatDeleteAlarmWarning('06:00', 'Society Court', 0)),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.alarms, hasLength(1), reason: 'Cancel means cancel');

      // The control: without it the assertion above would pass just as well
      // against a Delete button that had been disabled outright.
      await reachButtons();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete').last);
      await tester.pumpAndSettle();
      expect(c.alarms, isEmpty);
    });
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
      expect(c.courtNameForRing(NivaatIds.retryCheck(1)), isNull);
      expect(c.courtNameForRing(NivaatIds.card(1)), isNull);
      // Deleted mid-ring, or a ring left over from a build ago: the label is
      // the one thing on this screen that may be missing, so it goes quiet
      // rather than guessing.
      expect(c.courtNameForRing(NivaatIds.ring(2)), isNull);
    });
  });

  group('N15 — the live verdict on a home row (2026-08-25)', () {
    final checkedAt = DateTime(2026, 8, 25, 16, 0);

    /// A forecast with real numbers behind it. Every field is required on the
    /// model on purpose — a forecast is only ever written from a decision, so
    /// there is no state where the answer exists and its readings do not — and
    /// this keeps the tests that only care about the WORDS readable.
    AlarmForecast forecast({
      WindVerdict verdict = WindVerdict.ring,
      DateTime? at,
      double courtSpeed = 4,
      double gust = 9,
      int limit = 6,
      double gustLimit = 13,
      DateTime? slotAt,
    }) =>
        AlarmForecast(
          verdict: verdict,
          checkedAt: at ?? checkedAt,
          courtSpeedKmh: courtSpeed,
          rawGustKmh: gust,
          courtSpeedLimitKmh: limit,
          rawGustLimitKmh: gustLimit,
          slotAt: slotAt ?? DateTime(2026, 8, 25, 16, 45),
        );

    test('the words name the verdict AND the check time', () {
      // The time is never optional. A bare coloured dot is a promise with no
      // expiry — accent at 10pm about a 6am alarm reads as settled fact when it
      // is a forecast nobody has revised yet.
      expect(
        nivaatForecastLine(forecast(), now: checkedAt),
        'Going to ring · as per 16:00 check',
      );
    });

    test('nothing checked yet reads as Checking…, never as a verdict', () {
      expect(nivaatForecastLine(null), 'Checking…');
    });

    test('a check from another day carries its date', () {
      // Otherwise last night's answer reads as this afternoon's.
      expect(
        nivaatForecastLine(forecast(verdict: WindVerdict.tooWindy),
            now: DateTime(2026, 8, 26, 9, 0)),
        'Not going to ring · as per 25 Aug 16:00 check',
      );
    });

    test('the detail is the CARD\'s sentence, not a second vocabulary', () {
      // It said `Worst at 16:45` — accurate, and a phrasing belonging to no
      // other screen in the app. The card has named this exact fact since the
      // window rule landed, so both now read it from `nivaatWindWord`
      // (Samyak, 2026-08-25).
      expect(nivaatForecastDetail(forecast(verdict: WindVerdict.tooWindy)),
          'Too windy at 16:45 · wind 4 (≤6) · gusts 9 (≤13) km/h');
      expect(nivaatForecastDetail(forecast(verdict: WindVerdict.tooGusty)),
          'Too gusty at 16:45 · wind 4 (≤6) · gusts 9 (≤13) km/h');
    });

    test('the same words the card uses, from the same builder', () {
      // The point of sharing is that these cannot drift, so check them
      // against the card rather than against another literal.
      final record = HistoryRecord(
        alarmId: 1,
        courtId: 'c1',
        at: checkedAt,
        outcome: CheckOutcome.skippedWindy,
        courtSpeedKmh: 4,
        rawGustKmh: 9,
        courtSpeedLimitKmh: 6,
        rawGustLimitKmh: 13,
        slotAt: DateTime(2026, 8, 25, 16, 45),
        checkedAt: checkedAt,
      );
      expect(
        nivaatSkippedBody(record).split(' · ').first,
        nivaatForecastDetail(forecast(verdict: WindVerdict.tooWindy))
            .split(' · ')
            .first,
      );
    });

    test('a ring names no slot at all — just the numbers', () {
      // It said `Calm at 16:45` for a day, and that was wrong twice over
      // (Samyak, 2026-08-25): a skip is caused by ONE slot and can be pinned
      // to it, but a ring is the whole window clearing — so the time pointed
      // at a moment that was never special and implied the rest of the window
      // was not calm. `Calm from 16:30 to 17:00` would have been true and
      // would have said nothing the numbers beside it do not.
      expect(nivaatForecastDetail(forecast()),
          'wind 4 (≤6) · gusts 9 (≤13) km/h');
      expect(nivaatForecastDetail(forecast()), isNot(contains(' at ')));
    });

    test('a slot from another day carries its date', () {
      // Last night's reading behind a 06:00 alarm: a bare `22:00` would read
      // as the alarm's own day, sixteen hours after the check it came from.
      expect(
        nivaatForecastDetail(forecast(
            verdict: WindVerdict.tooWindy,
            at: DateTime(2026, 8, 26, 6),
            slotAt: DateTime(2026, 8, 25, 22, 0))),
        'Too windy at 25 Aug 22:00 · wind 4 (≤6) · gusts 9 (≤13) km/h',
      );
    });

    testWidgets('tapping the live line shows the detail, and only that',
        (tester) async {
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pumpAndSettle();
      final detail = nivaatForecastDetail(c.forecasts[1]!);
      expect(find.text(detail), findsNothing, reason: 'not until you ask');

      await tester.tap(find.textContaining('to ring · as per'));
      await tester.pumpAndSettle();
      expect(find.text(detail), findsOneWidget);
      // **And the editor did NOT open.** The card behind this line opens a
      // screen with a Delete button on it; a detail glance must not be one
      // twitch away from that.
      expect(find.text('EDIT ALARM'), findsNothing);

      // **On the row you tapped, not mid-screen.** `_line` is a method on the
      // State, so the bare `context` inside its tap handler was the State's —
      // the whole Scaffold — and `findRenderObject` on that measured the
      // screen, parking the pill dead centre over the list. A `Builder` gives
      // the handler a context below the gesture.
      final line = tester.getRect(find.textContaining('to ring · as per'));
      final pill = tester.getRect(
          find.ancestor(of: find.text(detail), matching: find.byType(Material))
              .first);
      expect(pill.center.dy, closeTo(line.center.dy, 12),
          reason: 'the pill answers for THIS row');
      // The control: it must not merely be somewhere sensible — the screen's
      // own middle is what it used to be, and on this fixture that is far
      // from the first row.
      final screen = tester.getRect(find.byType(Scaffold));
      expect((pill.center.dy - screen.center.dy).abs(), greaterThan(40),
          reason: 'centred on the screen is the bug this replaced');

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('the row still opens the editor everywhere else',
        (tester) async {
      // The control for the test above: `HitTestBehavior.opaque` on one line
      // must not swallow the card's own tap.
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('06:00'));
      await tester.pumpAndSettle();
      expect(find.text('EDIT ALARM'), findsOneWidget);
    });

    testWidgets('an enabled row renders it; a switched-off row does not',
        (tester) async {
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();
      // `silentEngine` answers every fetch, so init has already recorded a
      // verdict — which is the realistic state. Either wording is fine; what
      // the row must always carry is the CHECK TIME beside it.
      expect(find.textContaining('to ring · as per'), findsOneWidget);

      await c.toggleAlarm(1, false);
      await tester.pump();
      expect(find.textContaining('to ring · as per'), findsNothing,
          reason: 'a switched-off alarm cannot ring, so it claims nothing');
    });

    testWidgets('an OPEN retry window outranks the forecast on the row',
        (tester) async {
      // This is where N11 went. The banner used to speak for every alarm at
      // once — which is why it had to pick the soonest window and why tapping
      // it opened history to find out whose it was. On the row there is
      // nothing to disambiguate.
      final at = DateTime.now().subtract(const Duration(minutes: 5));
      final until = at.add(const Duration(minutes: 30));
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await c.store.upsertHistory(HistoryRecord(
        alarmId: 1,
        courtId: 'c1',
        at: at,
        outcome: CheckOutcome.skippedWindy,
        kind: HistoryKind.stillChecking,
        pushSeq: 1,
        checkedAt: at,
        watchedUntil: until,
      ));
      await c.store.saveCheckState(
          CheckState(alarmId: 1, alarmAt: at, cardShown: true));
      c.history = await c.store.loadHistory();
      c.checkStates = {1: (await c.store.loadCheckState(1))!};

      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();

      expect(find.textContaining('Still checking wind · until'), findsOneWidget,
          reason: 'the occurrence being live outranks any forecast verdict');
      expect(find.textContaining('to ring · as per'), findsNothing);
    });

    testWidgets('the dot breathes, and every row breathes together',
        (tester) async {
      // "Something is alive here" is the dot's whole job, and a printed dot
      // says it no better than the words beside it do (Samyak, 2026-08-25).
      //
      // The file's `setUp` holds the platform's reduce-motion switch ON so
      // `pumpAndSettle` can settle anywhere else; this is the one test about
      // the motion, so it turns the switch back off for itself.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      final c = await controller(
        courts: [court],
        alarms: const [
          NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'),
          NivaatAlarm(id: 2, hour: 7, minute: 0, courtId: 'c1'),
        ],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();

      final dots = find.descendant(
          of: find.byType(HomeScreen), matching: find.byType(FadeTransition));
      expect(dots, findsNWidgets(2), reason: 'one live dot per enabled row');

      // **One clock, not one per row.** Separate controllers start whenever
      // their row scrolls into view and drift apart within seconds, which
      // reads as flickering rather than as alive — and this is the cheapest
      // possible proof they share: the same object, not merely equal values
      // at the instant we looked.
      expect(tester.widget<FadeTransition>(dots.at(0)).opacity,
          same(tester.widget<FadeTransition>(dots.at(1)).opacity));

      final before = tester.widget<FadeTransition>(dots.first).opacity.value;
      await tester.pump(const Duration(milliseconds: 400));
      final after = tester.widget<FadeTransition>(dots.first).opacity.value;
      expect(after, isNot(before), reason: 'a still dot is a printed dot');
      // The full swing, 0 to 1 (Samyak, 2026-08-25). I argued for a floor —
      // a dot that reaches 0 reads as one that has GONE — and he took the
      // whole fade: the words never leave, so nothing is lost at the bottom.
      for (final v in [before, after]) {
        expect(v, inInclusiveRange(0, 1));
      }

      // Leave nothing running: an active ticker at the end of a test is an
      // error on its own, so the tree has to come down — and the scrollbar's
      // opening flash is a `Future.delayed` that unmounting will NOT cancel,
      // so it has to be seen off first. Same two steps as the ring-gate test.
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('reduce motion holds the dot still, at full strength',
        (tester) async {
      // "Remove animations" is a real accessibility switch — for people whom
      // looping motion makes ill, a dot that pulses forever is exactly what it
      // is there to stop. Held still it sits at FULL opacity, so the row says
      // the same thing either way rather than fading to a whisper.
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pumpAndSettle();

      final dot = find.descendant(
          of: find.byType(HomeScreen), matching: find.byType(FadeTransition));
      expect(tester.widget<FadeTransition>(dot).opacity.value, 1.0);
      // The control: with the switch off this settle would never return, and
      // the test above is what proves that.
    });

    testWidgets('a check YOU start says Checking…; opening the app never does',
        (tester) async {
      // Active vs passive, rendered — `NivaatController._rechecking` has the
      // rule and why it is one. Switching an alarm back on after a week used
      // to show last week's answer under the new switch, with nothing saying
      // a fresh check was running (Samyak, 2026-08-31).
      final api = _HeldApi();
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
        api: api,
      );

      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();
      expect(find.textContaining('to ring · as per'), findsOneWidget,
          reason: 'precondition: an answer on the row');

      // Passive — this is `resync`, the same call app open, resume, ring-stop
      // and a background check's ping all arrive through.
      api.hold = true;
      final opened = c.resync();
      await tester.pump();
      expect(find.text('Checking…'), findsNothing,
          reason: 'the last answer is what you opened the app to read');
      expect(find.textContaining('to ring · as per'), findsOneWidget);
      api.releaseAll();
      await opened;
      await tester.pump();

      // Active — the switch, off and then on again a while later.
      await c.toggleAlarm(1, false);
      await c.lastEvaluation;
      await tester.pump();
      api.hold = true;
      await c.toggleAlarm(1, true);
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.textContaining('to ring · as per'), findsNothing,
          reason: 'the verdict it is about to replace is withheld, not shown');
      // And no ⓘ beside it: the row cannot half-say `Checking…` and still
      // offer the numbers from the answer it is in the middle of replacing.
      expect(find.byIcon(Icons.info_outline), findsNothing);

      api.releaseAll();
      await c.lastEvaluation;
      await tester.pump();
      expect(find.textContaining('to ring · as per'), findsOneWidget,
          reason: 'the fresh answer takes the word back down');
    });

    testWidgets('and the answer landing does not move the rows below it',
        (tester) async {
      // Samyak, 2026-08-31, on a device: "some shift has been happening".
      // `_line`'s 6pt of tap padding was on the forecast branch alone, so
      // `Checking…` rendered 12pt shorter than the verdict that replaced it
      // and everything under it jumped when the check landed. Always wrong,
      // but only ever visible for the seconds after creating an alarm — until
      // `Checking…` became what an active re-check shows too.
      //
      // Measured on the SECOND alarm's clock: a height that changes shows up
      // as the row below moving, which is the thing you actually see.
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final api = _HeldApi();
      final c = await controller(
        courts: [court],
        alarms: const [
          NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1'),
          NivaatAlarm(id: 2, hour: 7, minute: 30, courtId: 'c1'),
        ],
        api: api,
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();
      final settled = tester.getRect(find.text('07:30')).top;

      api.hold = true;
      await c.toggleAlarm(1, true);
      await tester.pump();
      expect(find.text('Checking…'), findsOneWidget, reason: 'precondition');
      expect(tester.getRect(find.text('07:30')).top, settled,
          reason: 'the row below must not move while the check runs');

      api.releaseAll();
      await c.lastEvaluation;
      await tester.pump();
      expect(tester.getRect(find.text('07:30')).top, settled,
          reason: 'nor when the answer arrives');
    });

    testWidgets('the old top-of-screen watching cue is gone (N11 retired)',
        (tester) async {
      // It moved onto the row it was always about. Nothing at the top of home
      // speaks for every alarm at once any more.
      final c = await controller(
        courts: [court],
        alarms: const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')],
      );
      await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: c)));
      await tester.pump();
      expect(find.textContaining('Still checking wind'), findsNothing);
    });
  });
}

/// [SilentApi] that can be held mid-fetch, so a test can look at the SCREEN
/// while a check is genuinely in flight rather than inferring it afterwards.
class _HeldApi extends SilentApi {
  /// Hold every call from here on. Off by default so setup fetches freely.
  bool hold = false;

  /// One gate, shared by whatever parks on it — see `_GatedApi` next door.
  Completer<void>? _gate;

  void releaseAll() {
    hold = false;
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<List<WindSample>> windWindow(
    double lat,
    double lon,
    DateTime from,
    DateTime to, {
    List<String> models = OpenMeteo.defaultWindModels,
  }) async {
    if (hold) await (_gate ??= Completer<void>()).future;
    return super.windWindow(lat, lon, from, to, models: models);
  }
}

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/alarm_sheet.dart';
import 'package:nivaat/src/background_banner.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/courts_sheet.dart';
import 'package:nivaat/src/history_sheet.dart';
import 'package:nivaat/src/home_screen.dart';
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
        reason: 'the hint states the payoff — why 60m over 1m');
    for (final segment in ['1m', '30m', '60m']) {
      expect(find.text(segment), findsOneWidget);
    }
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Delete'), findsNothing,
        reason: 'a new alarm has nothing to delete');
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
}

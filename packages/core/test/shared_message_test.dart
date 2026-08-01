import 'package:alarm/alarm.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **Every shared string in MESSAGES.md (X1–X7), locked here.**
///
/// These live in `core` and render in BOTH apps, so a change here is a change
/// in two places at once — and until 2026-07-26 only X4's `CRAFTED WITH` was
/// asserted anywhere. The prompt was `nivaatDeleteCourtWarning` shipping an
/// ungrammatical singular that its own doc entry had hidden; nothing was
/// stopping the same silence here.
///
/// Anything with a branch is a pure builder and asserted directly; the rest is
/// asserted by rendering the real widget, which also proves the string is
/// reachable rather than merely present in the source.
void main() {
  group('X1 — ring screen (both apps, Android only)', () {
    // RingGate decides WHEN this shows from the `alarm` plugin's stream, which
    // no host test can drive; RingScreen is what it SAYS, and that is just
    // widgets. The split exists for exactly this (2026-07-26).
    Widget screen({
      String appName = 'ARUNODAY',
      Widget Function(BuildContext, AlarmSettings)? actions,
      Future<void> Function()? onStop,
    }) =>
        MaterialApp(
          home: RingScreen(
            appName: appName,
            alarms: [
              AlarmSettings(
                id: 1,
                dateTime: DateTime(2026, 7, 18, 7, 11),
                assetAudioPath: 'assets/sounds/arunoday_dawn.wav',
                volumeSettings: VolumeSettings.fixed(),
                notificationSettings: const NotificationSettings(
                  title: 'Arunoday · Dawn',
                  body: 'Dawn+0:20 at Jaipur. Good morning.',
                ),
              )
            ],
            onStop: onStop ?? () async {},
            actionsBuilder: actions,
          ),
        );

    testWidgets('STOP actually stops — the button is wired to onStop',
        (tester) async {
      // The one thing this screen has to DO. Splitting `RingScreen` out of
      // `RingGate` (2026-07-26) moved that wire, and every other test here
      // passes a no-op callback, so a severed one would have gone unnoticed
      // — on the button you hit at 6am, half awake (2026-07-31).
      var stopped = 0;
      await tester.pumpWidget(screen(onStop: () async => stopped++));
      await tester.tap(find.text('STOP'));
      await tester.pump();
      expect(stopped, 1);
    });

    testWidgets('names the app, the alarm time, its body, and STOP',
        (tester) async {
      await tester.pumpWidget(screen());

      expect(find.text('ARUNODAY'), findsOneWidget);
      expect(find.text('07:11'), findsOneWidget,
          reason: "the alarm's scheduled time, not the wall clock");
      expect(find.text('Dawn+0:20 at Jaipur. Good morning.'), findsOneWidget,
          reason: 'the ring notification\'s own body, never a second wording');
      expect(find.text('STOP'), findsOneWidget);
    });

    testWidgets('is the same screen for Nivaat, which adds no actions',
        (tester) async {
      await tester.pumpWidget(screen(appName: 'NIVAAT'));
      expect(find.text('NIVAAT'), findsOneWidget);
      expect(find.text('STOP'), findsOneWidget);
    });

    testWidgets('app actions sit above STOP (Arunoday A4)', (tester) async {
      await tester.pumpWidget(screen(
        actions: (_, alarm) => const Text('NOT SLEEPY'),
      ));
      expect(find.text('NOT SLEEPY'), findsOneWidget);
      expect(
        tester.getCenter(find.text('NOT SLEEPY')).dy,
        lessThan(tester.getCenter(find.text('STOP')).dy),
      );
    });
  });

  group('X2 — alarms-off banner', () {
    test('names the app that cannot ring', () {
      expect(
        alarmsOffMessage('Arunoday'),
        "Alarms are turned off — Arunoday can't ring until you allow alarms "
        'for it in Settings.',
      );
      expect(alarmsOffMessage('Nivaat'), contains('Nivaat can\'t ring'));
    });

    testWidgets('renders through NudgeBanner with its Open Settings action',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NudgeBanner(
            message: alarmsOffMessage('Arunoday'),
            actionLabel: 'Open Settings',
            onAction: () {},
            accent: AppPalette.dawn,
          ),
        ),
      ));
      expect(find.textContaining('Alarms are turned off'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);
    });
  });

  group('X3 — notifications-off banner', () {
    testWidgets('carries the app-supplied text and one fixed action',
        (tester) async {
      // The three message variants belong to the apps (each names what IT
      // loses), so they are asserted in the app suites; the action label is
      // core's and is the same everywhere.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NudgeBanner(
            message: 'Notifications are off — …',
            actionLabel: 'Turn on notifications',
            onAction: () {},
            accent: AppPalette.wind,
          ),
        ),
      ));
      expect(find.text('Turn on notifications'), findsOneWidget);
    });
  });

  group('X4 — maker\'s mark', () {
    testWidgets('reads CRAFTED WITH ♥ BY SAMYAK, heart as an icon',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: CraftedBy(accent: AppPalette.dawn)),
      ));
      expect(find.textContaining('CRAFTED WITH', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('BY SAMYAK', findRichText: true),
          findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsOneWidget,
          reason: 'a text heart is promoted to the red emoji on Android');
    });
  });

  group('X5 — location picker', () {
    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showLocationSearch(context),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    // X5's three GPS errors are NOT locked anywhere: each needs a real device
    // geolocation result, which a host test cannot produce, so they stay
    // device-smoke-test territory — said plainly rather than faked with an
    // assertion that proves nothing. The name dialog is NOT in that group
    // (corrected 2026-07-31): it opens on a host through
    // `showNamePlaceDialogForTest`, and `location_picker_test` locks its
    // title, its default, and the Save rule.
    testWidgets('offers GPS and search, with the offline caption',
        (tester) async {
      await open(tester);
      expect(find.text('Use my current location'), findsOneWidget);
      expect(find.text('Works offline'), findsOneWidget);
      expect(find.text('Or search a place…'), findsOneWidget);
    });

    test('a failed geocode says so only for Exceptions', () {
      expect(locationSearchErrorMessage(Exception('down')),
          'Search failed — check network');
      expect(locationSearchErrorMessage(StateError('bug')), isNull,
          reason: 'programming Errors are rethrown, not shown as a message');
    });

  });

  group('X6 — sound picker', () {
    testWidgets('header, and the default tone name each app passes in',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSoundPicker(context, selectedPath: null),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('ALARM SOUND'), findsOneWidget);
    });

    test('default tone names', () {
      expect(SoundLibrary.displayName(null, defaultName: 'Court Call'),
          'Court Call');
      expect(SoundLibrary.displayName(null, defaultName: 'Dawn Bells'),
          'Dawn Bells');
    });
  });

  group('X7 — appearance settings', () {
    testWidgets('bold-type toggle names what it does', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: HeavyTypeSwitch()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Bold clocks & titles'), findsOneWidget);
      expect(find.text('Heavier type on the home screen'), findsOneWidget);
    });

    testWidgets('icon picker labels — three per app', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AppIconPicker(
            accent: AppPalette.wind,
            appName: 'Nivaat',
            choices: [
              AppIconChoice(
                  id: '1', label: 'Shuttle', asset: 'assets/icons/1.png'),
              AppIconChoice(
                  id: '2', label: 'Calm', asset: 'assets/icons/2.png'),
              AppIconChoice(
                  id: '3', label: 'Crest', asset: 'assets/icons/3.png'),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('App icon'), findsOneWidget);
      for (final label in ['Shuttle', 'Calm', 'Crest']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    test('Android close warning blames Android and names the app', () {
      expect(appIconRestartWarning('Nivaat'),
          'Android will close Nivaat to apply the new icon.');
      expect(appIconRestartWarning('Arunoday'),
          'Android will close Arunoday to apply the new icon.');
      // One sentence, deliberately: see the builder's doc. A regression here
      // is someone re-explaining Android in a dialog nobody wants to read.
      expect(appIconRestartWarning('Nivaat').split('.').length - 1, 1);
    });

    testWidgets('…and it really is what the picker puts on screen',
        (tester) async {
      // Rendered rather than asserted on the builder alone: this dialog is
      // the only warning the user gets before the app vanishes, so the test
      // has to prove the picker reaches it. Pin Android explicitly — the dialog
      // is Android-only, and the iOS path must stay a no-dialog.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: AppIconPicker(
              accent: AppPalette.dawn,
              appName: 'Arunoday',
              choices: [
                AppIconChoice(
                    id: '1', label: 'Horizon', asset: 'assets/icons/1.png'),
                AppIconChoice(
                    id: '2', label: 'Rays', asset: 'assets/icons/2.png'),
              ],
            ),
          ),
        ));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rays'));
        await tester.pumpAndSettle();

        expect(find.text('CHANGE APP ICON'), findsOneWidget);
        expect(find.text(appIconRestartWarning('Arunoday')), findsOneWidget);
        expect(find.text('OK'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

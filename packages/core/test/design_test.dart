import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hero type: ships thin, heavy behind the toggle (2026-07-20)', () {
    final thin = buildOledTheme(AppPalette.dawn).textTheme;
    final heavy = buildOledTheme(AppPalette.dawn, heavyType: true).textTheme;

    test('default is EXACTLY the original thin look', () {
      expect(thin.displayLarge!.fontWeight, FontWeight.w200);
      expect(thin.displayLarge!.letterSpacing, -1.5);
      expect(thin.displayLarge!.fontFeatures, isNull);
      expect(thin.headlineMedium!.fontWeight, FontWeight.w300);
    });

    test('heavy mode: bold heroes with tabular clock digits', () {
      expect(heavy.displayLarge!.fontWeight, FontWeight.w700);
      expect(heavy.headlineMedium!.fontWeight, FontWeight.w600);
      for (final style in [heavy.displayLarge!, heavy.headlineMedium!]) {
        expect(style.fontFeatures, [const FontFeature.tabularFigures()]);
      }
    });

    test('three clock sizes since 2026-08-13, and the middle one behaves',
        () {
      // `displayMedium` is the list/second-clock size — Nivaat's alarm rows
      // and Arunoday's bedtime, both of which were 28 and read as captions.
      // It follows headlineMedium's weights, not displayLarge's: w200 at 40px
      // is too fine to catch at a glance in a list.
      expect(thin.displayMedium!.fontSize, 40);
      expect(thin.displayMedium!.fontWeight, FontWeight.w300);
      expect(thin.displayMedium!.fontFeatures, isNull);
      expect(heavy.displayMedium!.fontWeight, FontWeight.w600);
      expect(heavy.displayMedium!.fontFeatures,
          [const FontFeature.tabularFigures()]);
      // Still a ladder, both ways round.
      for (final t in [thin, heavy]) {
        expect(t.displayLarge!.fontSize!, greaterThan(t.displayMedium!.fontSize!));
        expect(
            t.displayMedium!.fontSize!, greaterThan(t.headlineMedium!.fontSize!));
      }
    });

    test('body and labels stay w400 in BOTH modes — the contrast is the look',
        () {
      for (final t in [thin, heavy]) {
        expect(t.bodyMedium!.fontWeight, FontWeight.w400);
        expect(t.labelSmall!.fontWeight, FontWeight.w400);
        expect(t.titleMedium!.fontWeight, FontWeight.w400);
      }
    });
  });

  group('Appearance store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    // Back to the shipped value, not to `false` — leaking OFF into another
    // test would quietly hide the default this group exists to pin.
    tearDown(() => Appearance.heavyType.value = true);

    test('it ships ON (2026-08-13), from an empty disk as well as in memory',
        () async {
      // It shipped OFF from 2026-07-20 until the heroes grew — at 64/72/130 the
      // w200 thin face reads washed out where w700 reads deliberate (Samyak).
      // Both defaults have to agree: the notifier's seed is what a screen
      // built before `load` uses, the `??` is what a first run reads.
      Appearance.heavyType.value = false; // simulate a stale in-memory value
      await Appearance.load();
      expect(Appearance.heavyType.value, isTrue,
          reason: 'nothing stored yet — a first run gets bold');
    });

    test('setHeavyType persists and notifies; load restores', () async {
      // Off, since that is now the value a user has to CHOOSE.
      await Appearance.setHeavyType(false);
      expect(Appearance.heavyType.value, isFalse);

      Appearance.heavyType.value = true; // simulate a fresh process
      await Appearance.load();
      expect(Appearance.heavyType.value, isFalse,
          reason: 'a stored OFF must survive a restart, or the default would '
              'silently overrule the one person who turned it off');
    });

    testWidgets('HeavyTypeSwitch flips the store', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: HeavyTypeSwitch())));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(Appearance.heavyType.value, isFalse, reason: 'ON → tap → OFF');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(Appearance.heavyType.value, isTrue);
    });
  });

  group('motion pacing', () {
    tearDown(() => timeDilation = 1.0); // never leak dilation into other tests

    test('applyMotionPacing slows every ticker by the shared knob', () {
      applyMotionPacing();
      expect(timeDilation, kMotionSlowdown);
    });

    test('the knob is a slowdown, not a speedup or a no-op left behind', () {
      expect(kMotionSlowdown, greaterThan(1.0));
      // Locked at 50% slower (2026-07-22); bump the ceiling if Samyak tunes up.
      expect(kMotionSlowdown, 1.5);
    });
  });

  group('CraftedBy', () {
    testWidgets('renders the mark with an accent ICON heart (no emoji risk)',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildOledTheme(AppPalette.wind),
        home: const Scaffold(body: CraftedBy(accent: AppPalette.wind)),
      ));
      expect(find.textContaining('CRAFTED WITH', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('BY SAMYAK', findRichText: true),
          findsOneWidget);
      final heart = tester.widget<Icon>(find.byIcon(Icons.favorite));
      expect(heart.color, AppPalette.wind);
    });

    testWidgets('tapping SAMYAK opens the site', (tester) async {
      var opened = 0;
      await tester.pumpWidget(MaterialApp(
        theme: buildOledTheme(AppPalette.dawn),
        home: Scaffold(
          body: CraftedBy(
            accent: AppPalette.dawn,
            openSite: () async => opened++,
          ),
        ),
      ));
      await tester.tapOnText(find.textRange.ofSubstring('SAMYAK'));
      // Not on the tap itself: it could still turn out to be the first of the
      // seven-tap developer run, so the link waits that window out. What the
      // waiting buys, and what cancels it, is `dev_mode_test`'s.
      await tester.pump(CraftedBy.linkDelay);
      expect(opened, 1);
    });
  });

  group('FlashingScrollbar (settings pages)', () {
    Widget host(int items) => MaterialApp(
          home: Scaffold(
            body: FlashingScrollbar(
              builder: (scroll) => ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < items; i++) const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        );

    Scrollbar bar(WidgetTester tester) =>
        tester.widget<Scrollbar>(find.byType(Scrollbar).first);

    testWidgets('flashes ~1s on open when the content overflows',
        (tester) async {
      await tester.pumpWidget(host(60));
      await tester.pump(); // post-frame callback fires the flash
      expect(bar(tester).thumbVisibility, isTrue);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(bar(tester).thumbVisibility, isNull); // faded back to default
    });

    testWidgets('stays quiet when everything fits', (tester) async {
      await tester.pumpWidget(host(3));
      await tester.pump();
      expect(bar(tester).thumbVisibility, isNull);
    });
  });

  group('app icon channel + picker', () {
    const channel = MethodChannel('core/app_icon');
    final calls = <MethodCall>[];
    var nativeIcon = '1';

    setUp(() {
      calls.clear();
      nativeIcon = '1';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'get':
            return nativeIcon;
          case 'set':
            nativeIcon = (call.arguments as Map)['id'] as String;
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('missing channel degrades safely: default icon, refused switch',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      expect(await currentAppIcon(), '1');
      expect(await setAppIcon('2'), isFalse);
    });

    test('a throwing platform degrades the same way (PlatformException)',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'refused');
      });
      expect(await currentAppIcon(), '1');
      expect(await setAppIcon('2'), isFalse);
    });

    // The assets don't exist in the test bundle; the picker's errorBuilder
    // swallows that (by design).
    const choices = [
      AppIconChoice(id: '1', label: 'One', asset: 'assets/icons/1.png'),
      AppIconChoice(id: '2', label: 'Two', asset: 'assets/icons/2.png'),
      AppIconChoice(id: '3', label: 'Three', asset: 'assets/icons/3.png'),
    ];

    Future<void> pumpPicker(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildOledTheme(AppPalette.dawn),
        home: const Scaffold(
          body: AppIconPicker(
            accent: AppPalette.dawn,
            appName: 'Arunoday',
            choices: choices,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    /// Runs [body] with the platform pinned. Reset inside the body, not in a
    /// tearDown: the binding asserts every foundation debug var is back to
    /// null BEFORE tearDowns run.
    Future<void> onPlatform(
        TargetPlatform platform, Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    /// The accent ring marks the selected thumbnail.
    Color ringColor(WidgetTester tester, int index) {
      final box = tester.widget<Container>(
        find.ancestor(
          of: find.ancestor(
              of: find.byType(Image).at(index), matching: find.byType(ClipRRect)),
          matching: find.byType(Container),
        ),
      );
      return (box.decoration! as BoxDecoration).border!.top.color;
    }

    testWidgets('picker reads the native choice and switches on tap',
        (tester) async {
      // Pinned, not relying on flutter_test's Android default holding.
      await onPlatform(TargetPlatform.android, () async {
        nativeIcon = '2';
        await pumpPicker(tester);

        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        // Android warns first — OK acknowledges, it isn't a choice (2026-08-01).
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(nativeIcon, '3');
        expect(
          calls.map((c) => c.method),
          containsAllInOrder(['get', 'set']),
        );

        // Tapping the already-selected icon must not hit the platform again —
        // nor put a dialog up about a switch that isn't happening.
        final setsSoFar = calls.where((c) => c.method == 'set').length;
        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(calls.where((c) => c.method == 'set').length, setsSoFar);
      });
    });

    testWidgets('Android warns before the switch; dismissing changes nothing',
        (tester) async {
      await onPlatform(TargetPlatform.android, () async {
        await pumpPicker(tester);

        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        // Nothing has been asked of the platform yet — the dialog comes first.
        expect(calls.where((c) => c.method == 'set'), isEmpty);
        // One button, on purpose: there is no decision to offer.
        expect(find.widgetWithText(TextButton, 'OK'), findsOneWidget);
        expect(find.byType(TextButton), findsOneWidget);
        // Padding is pinned, not inherited: M3's defaults leave the single
        // button marooned in empty space on a two-line notice.
        final box = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(box.contentPadding, const EdgeInsets.fromLTRB(24, 12, 24, 8));
        expect(box.actionsPadding, const EdgeInsets.fromLTRB(24, 0, 16, 12));

        // Tap the barrier — the only way out now that Cancel is gone, so it
        // has to be a real one.
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(calls.where((c) => c.method == 'set'), isEmpty);
        expect(nativeIcon, '1');
        // And the ring never moved off the icon that's still installed.
        expect(ringColor(tester, 0), AppPalette.dawn);
      });
    });

    testWidgets('iOS switches straight away — the OS runs its own alert',
        (tester) async {
      await onPlatform(TargetPlatform.iOS, () async {
        await pumpPicker(tester);

        await tester.tap(find.text('Three'));
        await tester.pumpAndSettle();
        // No dialog of ours: iOS stays open and confirms it itself, so a
        // second one would be pure friction.
        expect(find.byType(AlertDialog), findsNothing);
        expect(nativeIcon, '3');
      });
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('ring reverts when the OS refuses (${platform.name})',
          (tester) async {
        await onPlatform(platform, () async {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, (call) async {
            return call.method == 'get' ? '1' : false; // every set fails
          });
          await pumpPicker(tester);

          await tester.tap(find.text('Two'));
          await tester.pumpAndSettle();
          if (platform == TargetPlatform.android) {
            await tester.tap(find.text('OK'));
            await tester.pumpAndSettle();
          }
          // Back on "One": the failed switch didn't leave a lying ring behind.
          expect(ringColor(tester, 0), AppPalette.dawn);
        });
      });
    }
  });
}

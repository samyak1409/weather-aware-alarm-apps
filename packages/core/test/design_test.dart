import 'package:core/core.dart';
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
    tearDown(() => Appearance.heavyType.value = false);

    test('setHeavyType persists and notifies; load restores', () async {
      await Appearance.setHeavyType(true);
      expect(Appearance.heavyType.value, isTrue);

      Appearance.heavyType.value = false; // simulate a fresh process
      await Appearance.load();
      expect(Appearance.heavyType.value, isTrue);
    });

    testWidgets('HeavyTypeSwitch flips the store', (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: HeavyTypeSwitch())));
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
      expect(kMotionSlowdown, lessThanOrEqualTo(1.5));
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

    testWidgets('picker reads the native choice and switches on tap',
        (tester) async {
      nativeIcon = '2';
      const choices = [
        // The assets don't exist in the test bundle; the picker's
        // errorBuilder swallows that (by design).
        AppIconChoice(id: '1', label: 'One', asset: 'assets/icons/1.png'),
        AppIconChoice(id: '2', label: 'Two', asset: 'assets/icons/2.png'),
        AppIconChoice(id: '3', label: 'Three', asset: 'assets/icons/3.png'),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: buildOledTheme(AppPalette.dawn),
        home: const Scaffold(
          body: AppIconPicker(accent: AppPalette.dawn, choices: choices),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Three'));
      await tester.pumpAndSettle();
      expect(nativeIcon, '3');
      expect(
        calls.map((c) => c.method),
        containsAllInOrder(['get', 'set']),
      );

      // Tapping the already-selected icon must not hit the platform again.
      final setsSoFar = calls.where((c) => c.method == 'set').length;
      await tester.tap(find.text('Three'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'set').length, setsSoFar);
    });

    testWidgets('selection is optimistic but reverts when the OS refuses',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        return call.method == 'get' ? '1' : false; // every set fails
      });
      const choices = [
        AppIconChoice(id: '1', label: 'One', asset: 'assets/icons/1.png'),
        AppIconChoice(id: '2', label: 'Two', asset: 'assets/icons/2.png'),
      ];
      await tester.pumpWidget(MaterialApp(
        theme: buildOledTheme(AppPalette.dawn),
        home: const Scaffold(
          body: AppIconPicker(accent: AppPalette.dawn, choices: choices),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Two'));
      await tester.pumpAndSettle();
      // Back on "One": the failed switch didn't leave a lying ring behind.
      Container ring(String label) => tester.widget<Container>(
            find.ancestor(
                of: find.ancestor(
                    of: find.byType(Image).at(label == 'One' ? 0 : 1),
                    matching: find.byType(ClipRRect)),
                matching: find.byType(Container)),
          );
      final one = (ring('One').decoration! as BoxDecoration).border!.top.color;
      expect(one, AppPalette.dawn);
    });
  });
}

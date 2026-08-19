import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The hidden developer gate (2026-08-06): seven taps on the maker's mark.
///
/// Two halves, tested apart for the usual reason — the counting rules need a
/// clock this test can move (a pause between taps is not something a widget
/// test can wait out), while the gesture and the toast need the real widget.
void main() {
  // A static notifier outlives the test that flipped it, and a leaked `true`
  // would make the gated Nivaat option appear in someone else's suite.
  tearDown(() => DevMode.enabled.value = false);

  group('counting a run of taps', () {
    // Real-looking timestamps; only the gaps matter.
    final t0 = DateTime(2026, 8, 6, 21, 30);
    DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

    test('the seventh tap flips it, and not the sixth', () {
      final run = DevTapRun();
      for (var i = 1; i < DevMode.tapsToToggle; i++) {
        expect(run.tap(at(i * 200)), isFalse, reason: 'tap $i is not enough');
      }
      expect(run.tap(at(DevMode.tapsToToggle * 200)), isTrue);
    });

    test('a run resets, so the NEXT seven flip it back', () {
      // The whole point of the gesture: the same seven taps turn it off again,
      // which needs the counter cleared by completing rather than by a pause.
      final run = DevTapRun();
      var flips = 0;
      for (var i = 1; i <= DevMode.tapsToToggle * 2; i++) {
        if (run.tap(at(i * 200))) flips++;
      }
      expect(flips, 2);
    });

    test('a pause longer than the gap forgets the run', () {
      // Without this the mark sits on the home screen collecting stray taps
      // for a week and then flips with nobody meaning to.
      final run = DevTapRun();
      for (var i = 1; i < DevMode.tapsToToggle; i++) {
        run.tap(at(i * 200));
      }
      final resumed = at(1200 + DevMode.tapGap.inMilliseconds + 1);
      expect(run.tap(resumed), isFalse, reason: 'the sixth tap is stale');
      // And it really started over: six more taps, still nothing.
      for (var i = 1; i < DevMode.tapsToToggle - 1; i++) {
        expect(run.tap(resumed.add(Duration(milliseconds: i * 200))), isFalse);
      }
      final seventh = resumed.add(
          Duration(milliseconds: (DevMode.tapsToToggle - 1) * 200));
      expect(run.tap(seventh), isTrue,
          reason: 'seven from the resumed tap, not seven counting stale ones');
    });

    test('the gap stays short on purpose', () {
      // Pinned so it cannot be quietly widened back; the why is on the
      // constant (Samyak, 2026-08-06, down from 2s).
      expect(DevMode.tapGap, const Duration(seconds: 1));
    });

    test('a pause of exactly the gap still continues', () {
      // The boundary has to fall somewhere and generous is the cheap side: a
      // missed unlock is one more tap, a stray one is a state change.
      final run = DevTapRun();
      var now = t0;
      for (var i = 1; i < DevMode.tapsToToggle; i++) {
        now = now.add(DevMode.tapGap);
        expect(run.tap(now), isFalse);
      }
      expect(run.tap(now.add(DevMode.tapGap)), isTrue);
    });
  });

  group('the switch itself', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('ships off, and survives a restart once turned on', () async {
      await DevMode.load();
      expect(DevMode.enabled.value, isFalse,
          reason: 'nobody gets it by default');

      await DevMode.setEnabled(true);
      expect(DevMode.enabled.value, isTrue);

      // Model the next cold start: forget the in-memory value, read the disk.
      DevMode.enabled.value = false;
      await DevMode.load();
      expect(DevMode.enabled.value, isTrue);
    });
  });

  group('showAppToast with nothing to centre on', () {
    testWidgets('falls back to just above the bottom edge', (tester) async {
      // The documented default for a caller with no anchor. CraftedBy always
      // has the mark, so it reaches this only if the line has not laid out —
      // defence, but defence has to degrade rather than throw, and a
      // `Positioned` with neither `top` nor `bottom` would do exactly that.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showAppToast(context, 'hello', accent: AppPalette.dawn),
              child: const Text('go'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final pill = tester.getRect(find
          .ancestor(of: find.text('hello'), matching: find.byType(Material))
          .first);
      expect(tester.getRect(find.byType(Scaffold)).bottom - pill.bottom,
          closeTo(10, 0.5),
          reason: 'the offset a floating SnackBar used, so a toast with no '
              'anchor lands where one always did');
    });
  });

  group('the gesture on the maker\'s mark', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    // `fab` models Nivaat's home, which has one, against Arunoday's, which
    // does not — the difference that made a SnackBar land in two places.
    Widget host({Future<void> Function()? openSite, bool fab = false}) =>
        MaterialApp(
          theme: buildOledTheme(AppPalette.wind),
          home: Scaffold(
            body: CraftedBy(accent: AppPalette.wind, openSite: openSite),
            floatingActionButton: fab
                ? FloatingActionButton(
                    onPressed: () {}, child: const Icon(Icons.add))
                : null,
          ),
        );

    Future<void> tapMark(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(find.byType(CraftedBy));
        await tester.pump();
      }
    }

    testWidgets('seven taps turn it on and say so, seven more turn it off',
        (tester) async {
      await tester.pumpWidget(host());

      await tapMark(tester, DevMode.tapsToToggle - 1);
      await tester.pump();
      expect(DevMode.enabled.value, isFalse, reason: 'six is not seven');
      expect(find.text(kDevModeOnMessage), findsNothing,
          reason: 'no half-way feedback — the gesture is meant to be hidden');

      await tapMark(tester, 1);
      await tester.pump();
      expect(DevMode.enabled.value, isTrue);
      expect(find.text(kDevModeOnMessage), findsOneWidget);

      // Straight into the next seven with the first toast still up, which
      // exercises two things at once. It is the replace path — `showAppToast`
      // removes the live entry outright rather than queueing behind it — and
      // it is the only place the toast's `IgnorePointer` is under load: the
      // pill is centred ON the mark, so without it these taps land on the pill
      // and the gate stays on. Settling is for the NEW toast's fade-in; the
      // old one does not animate away, it is simply gone.
      await tapMark(tester, DevMode.tapsToToggle);
      await tester.pumpAndSettle();
      expect(DevMode.enabled.value, isFalse);
      expect(find.text(kDevModeOffMessage), findsOneWidget,
          reason: 'the toast has to name the direction, or a hidden switch '
              'gives you no way to know which way it just went');
      expect(find.text(kDevModeOnMessage), findsNothing,
          reason: 'the stale message must not be sitting behind the new one');
    });

    testWidgets('the toast hugs its text, in the app\'s own accent',
        (tester) async {
      // Two apps share this widget, so a hardcoded colour would be right in
      // one and wrong in the other, on a surface neither app's tests see.
      await tester.pumpWidget(host());
      await tapMark(tester, DevMode.tapsToToggle);
      await tester.pumpAndSettle();

      // The RESOLVED style, not the one this file passed in: reading the Text
      // widget's own `style` would only echo the literal back, and the theme's
      // body style is what it has to win against.
      final painted = tester
          .widget<RichText>(find.descendant(
              of: find.text(kDevModeOnMessage),
              matching: find.byType(RichText)))
          .text
          .style;
      expect(painted?.color, AppPalette.wind);

      // Its text plus its padding and nothing else — what stops a short
      // message sitting in a wide box with slack (Samyak, 2026-08-06).
      final pill = tester.getSize(find
          .ancestor(
              of: find.text(kDevModeOnMessage), matching: find.byType(Material))
          .first);
      final text = tester.getSize(find.text(kDevModeOnMessage));
      expect(pill.width, closeTo(text.width + 36, 0.5),
          reason: 'the pill is the text plus 18pt each side, nothing more');
    });

    testWidgets('sits centred on the mark, FAB or no FAB', (tester) async {
      // Two rules in one measurement: the toast is the MARK's answer, so it
      // centres on the mark rather than floating above it (Samyak,
      // 2026-08-06), and it lands identically whether or not the app has a
      // FloatingActionButton — Nivaat's home does, Arunoday's does not, and
      // `showAppToast` explains what a SnackBar did about that.
      final offsets = <double>[];
      for (final fab in [false, true]) {
        await tester.pumpWidget(host(fab: fab));
        await tapMark(tester, DevMode.tapsToToggle);
        await tester.pumpAndSettle();

        final pill = tester.getRect(find
            .ancestor(
                of: find.text(kDevModeOnMessage),
                matching: find.byType(Material))
            .first);
        // The mark's LINE, not the widget box — that one carries the bottom
        // padding, so its middle sits below the text it is named for.
        final line = tester.getRect(find
            .descendant(
                of: find.byType(CraftedBy), matching: find.byType(RichText))
            .first);
        expect(pill.center.dy, closeTo(line.center.dy, 0.5),
            reason: 'centres must align, which is what puts the pill OVER the '
                'mark rather than above it (fab: $fab)');
        offsets.add(pill.center.dy);
        // Leave the switch as it was, so the second pass toggles the same way.
        await DevMode.setEnabled(false);
      }
      expect(offsets.first, offsets.last,
          reason: 'a FloatingActionButton must not move it — the whole reason '
              'this is an overlay and not a SnackBar');
    });

    testWidgets('what it flips is persisted, not just held in memory',
        (tester) async {
      await tester.pumpWidget(host());
      await tapMark(tester, DevMode.tapsToToggle);
      await tester.pumpAndSettle();

      DevMode.enabled.value = false;
      await DevMode.load();
      expect(DevMode.enabled.value, isTrue,
          reason: 'it must still be on after the app is killed and reopened');
    });

    Future<void> tapName(WidgetTester tester, int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tapOnText(find.textRange.ofSubstring('SAMYAK'));
        await tester.pump();
      }
    }

    testWidgets('a lone tap on SAMYAK opens the site, a run window later',
        (tester) async {
      // SAMYAK stays a link — it just stops being an instant one.
      var opened = 0;
      await tester.pumpWidget(host(openSite: () async => opened++));

      await tapName(tester, 1);
      await tester.pump(DevMode.tapGap);
      expect(opened, 0,
          reason: 'a tap landing on the gap still continues a run, so the '
              'site cannot have opened yet');

      await tester.pump(CraftedBy.linkDelay - DevMode.tapGap);
      expect(opened, 1);
      expect(DevMode.enabled.value, isFalse, reason: 'one tap is not seven');
    });

    testWidgets('a run that stalls short of seven opens nothing at all',
        (tester) async {
      // Giving up at three does not turn those three back into a link tap
      // (Samyak, 2026-08-20): only a run's FIRST tap ever arms the site, so an
      // abandoned gesture is silent rather than answered with a browser.
      var opened = 0;
      await tester.pumpWidget(host(openSite: () async => opened++));

      await tapName(tester, 3);
      await tester.pump(CraftedBy.linkDelay);
      expect(opened, 0);
      expect(DevMode.enabled.value, isFalse, reason: 'three is not seven');
      // That the NEXT tap reaches the site again is the run expiring, which
      // runs on the wall clock (`DateTime.now()`) and so cannot be pumped —
      // it is the counting group's, not this one's.
    });

    testWidgets('seven taps on SAMYAK flip the gate and open nothing',
        (tester) async {
      // Why the link waits at all (2026-08-20, Samyak): SAMYAK is the widest
      // target on the mark, so a thumb going for the gate lands on the word —
      // and it used to answer with seven browsers while the run stayed at
      // zero.
      var opened = 0;
      await tester.pumpWidget(host(openSite: () async => opened++));

      await tapName(tester, DevMode.tapsToToggle);
      expect(DevMode.enabled.value, isTrue);
      expect(find.text(kDevModeOnMessage), findsOneWidget);

      await tester.pump(CraftedBy.linkDelay);
      expect(opened, 0, reason: 'every tap cancelled the one waiting before '
          'it, and the seventh spent the run on the gate');
    });

    testWidgets('a run counts the same wherever on the mark its taps land',
        (tester) async {
      // The footer and the word are one surface for counting purposes, so a
      // thumb that drifts on and off the word still gets there.
      var opened = 0;
      await tester.pumpWidget(host(openSite: () async => opened++));

      await tapName(tester, 1);
      await tapMark(tester, DevMode.tapsToToggle - 2);
      await tapName(tester, 1);
      expect(DevMode.enabled.value, isTrue);

      await tester.pump(CraftedBy.linkDelay);
      expect(opened, 0,
          reason: 'the seventh tap was on SAMYAK and still owed nothing — it '
              'completed the run');
    });

    testWidgets('a tap on the footer calls off a waiting site visit',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(host(openSite: () async => opened++));

      await tapName(tester, 1);
      await tapMark(tester, 1);
      await tester.pump(CraftedBy.linkDelay);
      expect(opened, 0,
          reason: 'the second tap is a run building, not a link being '
              'followed — whichever half of the mark it landed on');
    });
  });
}

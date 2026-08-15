import 'package:arunoday/main.dart';
import 'package:arunoday/src/controller.dart';
import 'package:arunoday/src/messages.dart';
import 'package:arunoday/src/settings_sheet.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller_test.dart' show FakeScheduler;

/// Holds `c.update` open so a second tap lands before the first one's rebuild
/// — the whole of REVIEW #20. Armed only once the page is up: a widget test's
/// clock advances on `pump`, so a delay awaited by `init` never ends.
class _SlowScheduler extends FakeScheduler {
  bool slow = false;

  @override
  Future<Set<int>> scheduledIds() async {
    if (slow) await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.scheduledIds();
  }
}

const _jaipur =
    SavedLocation(id: 'l1', name: 'Jaipur', lat: 26.91, lon: 75.79);

/// The two settings-page actions that wrote straight past everything the page
/// otherwise enforces: the long-press resets (REVIEW #16) and the switches
/// (REVIEW #20).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ArunodayController> controller(
    ArunodaySettings settings, {
    FakeScheduler? scheduler,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final store = ArunodayStore();
    await store.save(settings);
    final c = ArunodayController(
        store: store, scheduler: scheduler ?? FakeScheduler());
    await c.init();
    return c;
  }

  /// Holds a press for [held], then lets go — `tester.longPress` holds for
  /// Flutter's `kLongPressTimeout` (500ms), which these two rows stopped
  /// answering to on 2026-08-13.
  Future<void> hold(
    WidgetTester tester,
    Finder finder, {
    Duration? held,
  }) async {
    final gesture = await tester.startGesture(tester.getCenter(finder));
    await tester.pump(held ?? kResetHoldDuration * 1.1);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  /// Opens the real settings page the way the app does — it is private, and
  /// only `showSettingsSheet` can push it.
  Future<void> open(WidgetTester tester, ArunodayController c) async {
    // Tall viewport: one ListView, and a row that never scrolls into the
    // default 600pt is never mounted for `find.text`.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
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
  }

  testWidgets('long-pressing the wake offset refuses a collision (REVIEW #16)',
      (tester) async {
    // The dialogs disable Save on a same-minute wake and bedtime (A16); the
    // long-press wrote straight through, so the one gesture that skipped
    // validation could arm two alarms on one minute — and the plugin queues
    // the second, so they sound back to back.
    final c = await controller(const ArunodaySettings(
      locations: [_jaipur],
      activeLocationId: 'l1',
      wakeOffsetMinutes: 60,
    ));
    // Park the bedtime exactly on the dawn this reset would fall back to.
    final anchor = c.nextWake!.subtract(const Duration(minutes: 60));
    final dawnMinute = anchor.hour * 60 + anchor.minute;
    final auto = c.plan!.bedtimeMinutes;
    await c.update(c.settings
        .copyWith(bedtimeOffsetMinutes: () => (dawnMinute - auto).round()));
    expect(c.bedtimeMinutes!.round(), dawnMinute,
        reason: 'the collision this test is about');

    await open(tester, c);
    await hold(tester, find.text('Wake offset from dawn'));

    expect(find.text("Wake time can't be the same as the bedtime."),
        findsOneWidget,
        reason: 'A16, and it says why rather than doing nothing');
    expect(c.settings.wakeOffsetMinutes, 60, reason: 'the reset was refused');
  });

  testWidgets('long-pressing bedtime refuses a collision (REVIEW #16)',
      (tester) async {
    final c = await controller(const ArunodaySettings(
      locations: [_jaipur],
      activeLocationId: 'l1',
      bedtimeOffsetMinutes: 60, // non-null, so the long-press is enabled
    ));
    // Park the wake on the auto bedtime — what this reset would fall back to.
    final autoMinute = c.plan!.bedtimeMinutes.round();
    final dawn = c.nextWake!; // offset is 0 here, so the wake IS the dawn
    await c.update(c.settings.copyWith(
        wakeOffsetMinutes: autoMinute - (dawn.hour * 60 + dawn.minute)));
    // Dawn drifts ~1 min/day, so which date `nextWake` lands on changes the
    // arithmetic. Measure and correct once rather than predict.
    var wakeMinute = c.nextWake!.hour * 60 + c.nextWake!.minute;
    if (wakeMinute != autoMinute) {
      await c.update(c.settings.copyWith(
          wakeOffsetMinutes:
              c.settings.wakeOffsetMinutes + (autoMinute - wakeMinute)));
      wakeMinute = c.nextWake!.hour * 60 + c.nextWake!.minute;
    }
    expect(wakeMinute, autoMinute,
        reason: 'the collision this test is about');

    await open(tester, c);
    await hold(tester, find.text('Bedtime'));

    expect(find.text("Bedtime can't be the same as the wake alarm."),
        findsOneWidget);
    expect(c.settings.bedtimeOffsetMinutes, 60,
        reason: 'the return to auto was refused');
  });

  testWidgets('a long-press that collides with nothing still resets',
      (tester) async {
    // The control: without it the two above would pass just as well against a
    // long-press that had been disabled outright.
    final c = await controller(const ArunodaySettings(
      locations: [_jaipur],
      activeLocationId: 'l1',
      wakeOffsetMinutes: 60,
      bedtimeOffsetMinutes: 45,
    ));
    await open(tester, c);

    await hold(tester, find.text('Wake offset from dawn'));
    expect(c.settings.wakeOffsetMinutes, 0);

    await hold(tester, find.text('Bedtime'));
    expect(c.settings.bedtimeOffsetMinutes, isNull);
  });

  testWidgets('a press let go at half a second resets nothing (2026-08-13)',
      (tester) async {
    // The reason the hold was lengthened: at Flutter's 500ms default a press
    // that merely lingered threw away an offset you set on purpose, with no
    // dialog in between. Pinned as a duration, not a feeling — and this is
    // the assertion that fails if the constant is quietly turned back down.
    expect(kResetHoldDuration, const Duration(seconds: 1));
    final c = await controller(const ArunodaySettings(
      locations: [_jaipur],
      activeLocationId: 'l1',
      wakeOffsetMinutes: 60,
    ));
    await open(tester, c);

    await hold(tester, find.text('Wake offset from dawn'),
        held: const Duration(milliseconds: 500));
    expect(c.settings.wakeOffsetMinutes, 60, reason: 'not held long enough');
    // Letting go early is a TAP, so the picker opens — that is the feedback,
    // and it is why an unfinished hold needs no message of its own.
    expect(find.text('WAKE OFFSET'), findsOneWidget);
  });

  testWidgets('the ring gate sits ABOVE the settings page (2026-08-13)',
      (tester) async {
    // Device-caught: with an alarm ringing while settings was open, the ring
    // screen was nowhere to be seen — you had to press back to find it, and
    // tapping the ring notification looked like it did nothing at all,
    // because the app was already in front showing settings.
    //
    // `RingGate` wrapped `home:`, which is the first ROUTE, so anything
    // pushed covered it. It lives in `MaterialApp.builder` now, above the
    // Navigator — asserted structurally rather than by ringing an alarm,
    // since only a device can make the plugin ring.
    final c = await controller(
        const ArunodaySettings(locations: [_jaipur], activeLocationId: 'l1'));
    await tester.pumpWidget(
        ArunodayApp(controller: c, permissionFlow: Future<void>.value()));
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

    // Two live timers to see off, since this is the whole app rather than one
    // page: the scrollbar's flash (a `Future.delayed`, so unmounting will not
    // cancel it) and home's minute ticker (which dispose does).
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('deleting a location (2026-08-15)', () {
    testWidgets('asks first, and Cancel keeps it', (tester) async {
      // The bin was one tap from gone, and on the last location that tap
      // silently switched the wake and bedtime off — the most destructive
      // gesture in the app, with the least in front of it.
      final c = await controller(const ArunodaySettings(
          locations: [_jaipur], activeLocationId: 'l1'));
      await open(tester, c);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('DELETE LOCATION'), findsOneWidget);
      expect(find.text(arunodayDeleteLocationWarning('Jaipur', isActive: true)),
          findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(c.settings.locations, hasLength(1), reason: 'Cancel means cancel');
      expect(find.text('Wake alarm'), findsOneWidget);
    });

    testWidgets('the last one goes, and the page STAYS', (tester) async {
      // It used to pop, because settings was unreachable without a location
      // and staying would have stranded you. Settings opens from the empty
      // home now, so popping would throw away the page you were working on —
      // and what is left is exactly the section you need next.
      final c = await controller(const ArunodaySettings(
          locations: [_jaipur], activeLocationId: 'l1'));
      await open(tester, c);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      // The dialog's own Delete, not the row's bin icon.
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(c.settings.locations, isEmpty);
      expect(c.settings.activeLocationId, isNull,
          reason: 'nothing left to be active');
      expect(find.text('SETTINGS'), findsOneWidget,
          reason: 'the page must not pop out from under the user');
      // And the rows that needed a location are gone with it, live — this is
      // the same page, rebuilt, not a fresh one.
      expect(find.text('Wake alarm'), findsNothing);
      expect(find.text('Bedtime'), findsNothing);
      expect(find.text(kArunodayNoLocationsYet), findsOneWidget);
    });
  });

  testWidgets('two quick switch taps do not undo each other (REVIEW #20)',
      (tester) async {
    // `c.update` notifies only after saving AND re-arming the whole window, so
    // the second tap arrives before the page rebuilds. Against the frame's
    // captured snapshot the second `copyWith` was built on pre-first-tap state
    // and Wake came back on.
    final slow = _SlowScheduler();
    final c = await controller(
      const ArunodaySettings(locations: [_jaipur], activeLocationId: 'l1'),
      scheduler: slow,
    );
    await open(tester, c);
    expect(c.settings.wakeEnabled, isTrue);
    expect(c.settings.bedtimeEnabled, isTrue);
    slow.slow = true;

    await tester.tap(find.text('Wake alarm'));
    // Zero duration: microtasks and a frame, but the clock does not move, so
    // the first update is still inside the scheduler when tap two lands.
    // Settling here would rebuild the page and prove nothing.
    await tester.pump();
    await tester.tap(find.text('Bedtime alarm'));
    await tester.pumpAndSettle();

    expect(c.settings.wakeEnabled, isFalse, reason: 'the first tap survived');
    expect(c.settings.bedtimeEnabled, isFalse);
  });
}

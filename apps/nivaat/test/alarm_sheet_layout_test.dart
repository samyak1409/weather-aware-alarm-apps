import 'package:core/core.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/alarm_sheet.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// The alarm editor's live countdown sits in a slot that must not move the
/// controls under it, and must not crop itself when the phone's text is large.
/// Both were real: a collapsing box threw the day chips 24px up the moment you
/// deselected your last weekday, and the fixed height that fixed THAT clipped
/// the label at accessibility scales (at 2x it wants 40 logical pixels, not 32).
// flutter_test's font draws every glyph a full em wide, so text here is much
// wider than real Roboto — a useful stress, but it means the wide surfaces
// below stand in for ordinary phone widths. [phone] is the one case measured at
// a true 390pt, where the geometry has to hold with room to spare.
const Size phone = Size(390, 844);

void main() {
  late NivaatController controller;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    await store.saveCourts(
        [const SavedLocation(id: 'c1', name: 'Home', lat: 12.9, lon: 77.6)]);
    controller = NivaatController(engine: silentEngine(store));
    await controller.init();
  });

  Future<void> openSheet(
    WidgetTester t,
    NivaatAlarm? alarm, {
    double scale = 1.0,
  }) async {
    await t.pumpWidget(MaterialApp(
      // Fresh Navigator each call: without it the previously opened sheet is
      // still on the stack and the next tap lands on its modal barrier.
      key: UniqueKey(),
      theme: buildOledTheme(AppPalette.wind),
      // Scale via MaterialApp.builder: it wraps the Navigator, so the sheet's
      // own route inherits it. (Below `home` it would not — and building a
      // MediaQueryData from scratch would zero out `size`, which this sheet
      // reads for its height cap.)
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showAlarmSheet(context, controller, alarm: alarm),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  // Weekdays empty → no occurrence to count down to → the label goes blank.
  // That is the state that used to collapse the slot.
  const filled = NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1');
  const blank = NivaatAlarm(
      id: 1, hour: 6, minute: 0, courtId: 'c1', weekdays: <int>{});

  // The wheel IS the clock since 2026-08-25 — there is no `06:00` text at the
  // top of the sheet any more, only two spinning columns and a colon.
  Finder heroClock() => find.byType(CupertinoDatePicker);

  Finder countdown() => find.byWidgetPredicate(
      (w) => w is Text && w.data != null && w.data!.startsWith('in '));

  testWidgets('a blank countdown does not resize the sheet', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // Measured wheel→Court, not screen coordinates: a bottom sheet is anchored
    // to the bottom edge, so a slot that collapses leaves everything BELOW it
    // in place and shoves the wheel and title down instead (24px, the slot's
    // whole height). Screen-absolute positions of the rows underneath
    // therefore prove nothing.
    await openSheet(t, filled);
    expect(countdown(), findsOneWidget, reason: 'fixture shows a countdown');
    final withLabel =
        t.getRect(find.text('Court')).top - t.getRect(heroClock()).bottom;

    await openSheet(t, blank);
    expect(countdown(), findsNothing, reason: 'no weekday can fire');
    final withoutLabel =
        t.getRect(find.text('Court')).top - t.getRect(heroClock()).bottom;

    expect(withoutLabel, withLabel,
        reason: 'an empty Text still lays out a full line box, so the slot is '
            'the same height either way — nothing jumps');
  });

  testWidgets('the countdown grows with accessibility text, never cropped',
      (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await openSheet(t, filled);
    final atNormal = t.getRect(countdown()).height;

    await openSheet(t, filled, scale: 2.0);
    final atLarge = t.getRect(countdown()).height;

    expect(atLarge, greaterThan(atNormal * 1.9),
        reason: 'a fixed 32px slot capped this at 32 — the label wants ~40');
  });

  testWidgets('a switched-off alarm still counts down HERE, unlike its home row',
      (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // Deliberate asymmetry (Samyak, 2026-07-26): the editor is where you pick a
    // time, so the time left is the feedback that makes the choice — on or off.
    // The home row for the very same alarm stays silent, because there the
    // switch is the statement.
    await openSheet(t, filled.copyWith(enabled: false));
    expect(countdown(), findsOneWidget,
        reason: 'editing a time shows the time left, switch or no switch');
    expect(nivaatNextRingAt(filled.copyWith(enabled: false), null), isNull,
        reason: 'home is the other half of the pair — no ring advertised');
  });

  testWidgets('the sheet lays out on a real phone at 2x text', (t) async {
    // The Court row used to cap its dropdown at 0.67 of the SCREEN while
    // ListTile divides the TILE and the title's width never entered the sum.
    // At 2x text on a 390pt phone the title needs room the row cannot give,
    // and ListTile asserts — a debug crash on an ordinary phone with large
    // type. Flex negotiates the split now, so the title is squeezed, not
    // starved (2026-07-26).
    await t.binding.setSurfaceSize(phone);
    addTearDown(() => t.binding.setSurfaceSize(null));

    for (final scale in [1.0, 1.3, 2.0]) {
      await openSheet(t, filled, scale: scale);
      expect(t.takeException(), isNull, reason: 'no layout assert at ${scale}x');
      final title = t.getRect(find.text('Court'));
      expect(title.width, greaterThan(0),
          reason: 'the title must keep real width at ${scale}x');
      expect(find.text('Save'), findsOneWidget,
          reason: 'the whole sheet still builds at ${scale}x');
    }
  });

  testWidgets('the three setting labels share one type style', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await openSheet(t, filled);

    // "Max wind at court" gets bodyLarge from ListTile; Court and Keep checking
    // are plain Rows and have to ask for it. Court learned that the hard way —
    // moving it out of ListTile (to stop a trailing-overflow assert) silently
    // dropped it to bodyMedium: 14px secondary grey beside two white 16px
    // labels, a demotion nothing in the diff pointed at.
    TextStyle styleOf(String label) => t
        .widget<RichText>(find.descendant(
            of: find.text(label), matching: find.byType(RichText)))
        .text
        .style!;

    final reference = styleOf('Max wind at court');
    for (final label in ['Court', 'Keep checking']) {
      final s = styleOf(label);
      expect(s.fontSize, reference.fontSize, reason: '$label size');
      expect(s.color, reference.color, reason: '$label colour');
      expect(s.letterSpacing, reference.letterSpacing, reason: '$label tracking');
      expect(s.fontWeight, reference.fontWeight, reason: '$label weight');
    }
  });

  testWidgets('retry segments never crop their labels at large text',
      (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await openSheet(t, filled, scale: 2.0);

    // "60m" is three glyphs in a box sized like a one-glyph day chip — the
    // tightest text in the sheet, and the ClipRRect around it turns any
    // overflow into a silent crop rather than a visible stripe.
    //
    // Compare INTRINSIC width against the space available, not the laid-out
    // rect: the rect is clamped to its parent, so a label that needs 79px in a
    // 52px segment still measures 52 and looks fine. Clamped IS clipped.
    //
    // Three rows carry these segments (the play-window pair joined Keep
    // checking on 2026-08-25), and since the dev extra became shared they are
    // the same control with the same options — so any of them measures the
    // fit. `.last` is Keep checking, kept only because the divisor below is
    // written from ITS value.
    expect(find.text('60m'), findsNWidgets(3),
        reason: 'one per minutes row — if this changes, so does `.last`');
    final label = t.renderObject<RenderBox>(find.text('60m').last);
    final box = t.getRect(find
        .ancestor(of: find.text('60m').last, matching: find.byType(ClipRRect))
        .first);
    // Derived from the same call the widget builds from, not the base list:
    // the control also renders the dev-gated option and any value the alarm
    // already holds, so an off-list alarm WOULD lay out three segments and a
    // fixed divisor of 2 would measure a width that is not on screen. (This
    // fixture takes the default 30, so today it really is two.)
    final perSegment = box.width /
        minuteOptionsFor(
          base: CheckCascade.retryMinutesOptions,
          devMode: DevMode.enabled.value,
          selected: filled.retryMinutesAfter,
        ).length;
    expect(label.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(perSegment),
        reason: 'the label needs more room than its segment gives it');
    expect(label.getMinIntrinsicHeight(perSegment),
        lessThanOrEqualTo(box.height),
        reason: 'the label is taller than the control');
  });

  group('where a new alarm opens (2026-08-25)', () {
    // Pure and top-level so this can be asserted at all — the draft used to be
    // computed inline from `TimeOfDay.now()`, where no test could reach it and
    // the floor shipped unnoticed.
    test('the next slot, never the one just gone', () {
      // 03:45 opened on 03:30 until 2026-08-25 — a time already past, so the
      // countdown under the clock read "in 23h 45m" and a brand-new alarm's
      // first impression was one a whole day away.
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 3, 45)), (4, 0));
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 3, 1)), (3, 30));
    });

    test('a slot boundary moves on, it does not stand still', () {
      // Ceiling the MINUTE is not enough: at 03:30:20 the ceiling of 30 is 30,
      // twenty seconds in the past, and the day-away countdown comes back.
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 3, 30)), (4, 0));
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 3, 30, 20)), (4, 0));
    });

    test('the last slot of the day wraps to midnight', () {
      // Modular arithmetic on the hour would give 24 here — a value
      // `NivaatAlarm` would store and `CupertinoDatePicker` would assert on.
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 23, 45)), (0, 0));
      expect(nivaatSeedAlarmTime(DateTime(2026, 8, 25, 23, 59, 59)), (0, 0));
    });

    test('every minute of the day lands on the grid, strictly ahead', () {
      // The property the three cases above are examples of, and the one that
      // fails the moment anyone floors again: 720 of these seeds are the same
      // minute the clock is on.
      final midnight = DateTime(2026, 8, 25);
      for (var m = 0; m < 24 * 60; m++) {
        final now = midnight.add(Duration(minutes: m));
        final (hour, minute) = nivaatSeedAlarmTime(now);
        expect(minute % kNivaatAlarmMinuteInterval, 0,
            reason: 'the picker only offers the grid ($now)');
        final seeded = DateTime(now.year, now.month, now.day, hour, minute);
        final ahead = seeded.isAfter(now)
            ? seeded
            // Past midnight the seed belongs to tomorrow.
            : seeded.add(const Duration(days: 1));
        expect(ahead.difference(now).inMinutes,
            inInclusiveRange(1, kNivaatAlarmMinuteInterval),
            reason: 'ahead, and by less than one slot ($now)');
      }
    });
  });

  test('the wheel keeps the clock\'s size until a phone cannot hold it', () {
    // `CupertinoDatePicker` does not shrink to fit: given too little width it
    // overlaps its own columns, reports a layout error in debug and says
    // nothing in release. So the size is chosen before it is handed over.
    //
    // Widths here are the SHEET's content width — screen less its 24 of
    // padding either side — since the wheel moved inline (2026-08-25).
    for (final width in [312.0, 342.0, 364.0, 382.0]) {
      expect(nivaatWheelFontSize(full: 64, available: width), 64,
          reason: 'a ${width + 48}pt phone holds the clock\'s own type');
    }
    final small = nivaatWheelFontSize(full: 64, available: 232);
    expect(small, lessThan(64));
    expect(small, greaterThan(0), reason: 'shrunk, never inverted');
    // Monotone, so there is no width where asking for more room gives a
    // smaller wheel.
    var last = 0.0;
    for (var w = 160.0; w <= 460; w += 5) {
      final size = nivaatWheelFontSize(full: 64, available: w);
      expect(size, greaterThanOrEqualTo(last), reason: 'at ${w}pt');
      last = size;
    }
  });

  testWidgets('an off-grid saved alarm opens the wheel rather than tripping it',
      (t) async {
    // `CupertinoDatePicker` ASSERTS its initial minute is on `minuteInterval`,
    // so an off-grid stored value would crash the editor open — and the wheel
    // is the sheet's only display of the time now, so showing 06:00 over a
    // draft that still said 06:17 would save the 17 back.
    //
    // Nothing has written an off-grid minute since the grid landed; this is
    // about the two seed paths agreeing, which is what stops the day the grid
    // changes from being a crash.
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await openSheet(
        t, const NivaatAlarm(id: 1, hour: 6, minute: 17, courtId: 'c1'));

    expect(t.takeException(), isNull, reason: 'the wheel drew at all');
    expect(find.text('06:00'), findsOneWidget,
        reason: "the timeline's first step is the SNAPPED draft");
    expect(find.text('06:17'), findsNothing);
  });

  testWidgets('a clashing time TAKES the countdown\'s slot, and moves nothing',
      (t) async {
    // The message went above Save first, in the same grey as the timeline's
    // footnote at the far end of a sheet that now scrolls; then here as an
    // extra line in brighter type, which shifted the whole sheet the instant
    // it appeared. It replaces the countdown now — which is meaningless
    // anyway, since this time cannot be saved (Samyak, 2026-08-25).
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // Derived from `now`, never a literal: the seed IS the next half-hour
    // slot, so this is the one time a new sheet is guaranteed to open on.
    final (hour, minute) = nivaatSeedAlarmTime(DateTime.now());

    await openSheet(t, null);
    expect(countdown(), findsOneWidget, reason: 'nothing clashes yet');
    final clear = t.getRect(find.text('Court')).top - t.getRect(heroClock()).bottom;

    await controller.upsertAlarm(
        NivaatAlarm(id: 1, hour: hour, minute: minute, courtId: 'c1'));
    await openSheet(t, null);

    expect(countdown(), findsNothing,
        reason: 'the clash speaks instead, not as well');
    expect(find.textContaining('Another alarm'), findsOneWidget);
    expect(
      t.getRect(find.text('Court')).top - t.getRect(heroClock()).bottom,
      clear,
      reason: 'one line either way — the sheet must not jump when it appears',
    );
    // And it is the quiet caption type, like the countdown it replaced: a
    // brighter one was the other half of what Samyak turned down.
    final style = t
        .widget<RichText>(find.descendant(
            of: find.textContaining('Another alarm'),
            matching: find.byType(RichText)))
        .text
        .style!;
    expect(style.color, buildOledTheme(AppPalette.wind).textTheme.bodyMedium!.color);
  });

  testWidgets('spinning the wheel moves the draft, with nothing to confirm',
      (t) async {
    // The wheel used to live in a dialog behind a `Set` button, so the
    // countdown under it — the whole reason the time sits at the top of this
    // sheet — was hidden by the modal answering it, and only caught up when
    // you pressed Set. Inline, it moves as you spin.
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await openSheet(t, filled);

    expect(find.text('Set'), findsNothing,
        reason: 'the draft IS the sheet state; Save is the only commit');
    expect(find.text('06:00'), findsOneWidget,
        reason: "the timeline's first step, which is the draft's own time");

    // On the HOUR column, not the picker's centre — the centre is the colon,
    // which is a plain `Text` and scrolls nothing.
    await t.drag(find.text('06'), const Offset(0, -100));
    await t.pumpAndSettle();

    expect(find.text('06:00'), findsNothing,
        reason: 'the wheel took the drag and the sheet followed it');
    // And the sheet did not scroll away under the gesture instead.
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
  });

  testWidgets('the wheel is the clock, in the clock\'s own type', (t) async {
    // It was a `TextButton` reading `04:00` that opened a dialog holding a
    // 22px wheel, so touching the biggest thing on the screen produced the
    // smallest. Now the wheel sits where that text was — and there is no
    // dialog to confirm, which is why nothing here taps anything.
    //
    // A PIN, in `check_scheduler_test`'s sense: it cannot prove 64 looks
    // right, only that shrinking it again is deliberate. The WIDTH this costs
    // is budgeted in `nivaatWheelFontSize` from Roboto's metrics and can only
    // be confirmed on a device — flutter_test's font draws every glyph a full
    // em wide, so nothing measured here stands in for a real phone.
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await openSheet(t, filled);

    expect(find.byType(CupertinoDatePicker), findsOneWidget,
        reason: 'no tap: the wheel is already there');
    // Read off the PAINTED digits rather than the theme handed to the wheel:
    // the clamp and the Cupertino theme both sit between the two, and it is
    // what lands on screen that was wrong.
    final clock = buildOledTheme(AppPalette.wind).textTheme.displayLarge!;
    final wheel = t
        .renderObject<RenderParagraph>(find.descendant(
            of: find.byType(CupertinoDatePicker),
            matching: find.descendant(
                of: find.text('06'), matching: find.byType(RichText))))
        .text
        .style!;
    expect(wheel.fontSize, clock.fontSize);
    expect(wheel.fontWeight, clock.fontWeight);
    expect(wheel.letterSpacing, clock.letterSpacing);
    expect(find.descendant(of: find.byType(CupertinoDatePicker),
        matching: find.text(':')), findsOneWidget,
        reason: 'the colon is what makes it the clock you tapped');

    final picker =
        t.widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker));
    expect(picker.itemExtent, greaterThanOrEqualTo(clock.fontSize! * 1.2),
        reason: 'a row shorter than its line box clips the digits');
    expect(picker.minuteInterval, kNivaatAlarmMinuteInterval);
  });
}

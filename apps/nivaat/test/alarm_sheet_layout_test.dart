import 'package:core/core.dart';
import 'package:flutter/material.dart';
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
    NivaatAlarm alarm, {
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

  Finder countdown() => find.byWidgetPredicate(
      (w) => w is Text && w.data != null && w.data!.startsWith('in '));

  testWidgets('a blank countdown does not resize the sheet', (t) async {
    await t.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // Measured clock→Court, not screen coordinates: a bottom sheet is anchored
    // to the bottom edge, so a slot that collapses leaves everything BELOW it
    // in place and shoves the hero clock and title down instead (24px, the
    // slot's whole height). Screen-absolute positions of the rows underneath
    // therefore prove nothing.
    await openSheet(t, filled);
    expect(countdown(), findsOneWidget, reason: 'fixture shows a countdown');
    final withLabel =
        t.getRect(find.text('Court')).top - t.getRect(find.text('06:00')).bottom;

    await openSheet(t, blank);
    expect(countdown(), findsNothing, reason: 'no weekday can fire');
    final withoutLabel =
        t.getRect(find.text('Court')).top - t.getRect(find.text('06:00')).bottom;

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
    final label = t.renderObject<RenderBox>(find.text('60m'));
    final box = t.getRect(find
        .ancestor(of: find.text('60m'), matching: find.byType(ClipRRect))
        .first);
    // Derived from the same call the widget builds from, not the base list:
    // the control also renders the dev-only 1m and any value the alarm already
    // holds, so a fixture on a 1m window lays out THREE segments and a fixed
    // divisor of 2 would measure a per-segment width that is not on screen.
    final perSegment = box.width /
        CheckCascade.retryOptionsFor(
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
}

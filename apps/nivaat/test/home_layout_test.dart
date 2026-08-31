import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivaat/src/controller.dart';
import 'package:nivaat/src/engine.dart';
import 'package:nivaat/src/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'silent_fakes.dart';

/// **The home list is bracketed, and both brackets keep the same distance**
/// (Samyak, 2026-08-31, on a device: a nudge sat almost on top of a 40pt
/// clock, while the caveat at the foot of the screen had visible black above
/// it). The caveat had its own 20pt; the nudges had only the 12 the component
/// carries between them. Asserted against EACH OTHER rather than against 20,
/// so a future retune keeps the two sides in step.
void main() {
  const court =
      SavedLocation(id: 'c1', name: 'Society Court', lat: 26.17, lon: 75.79);

  /// A real phone, and reduce-motion on: the home row's dot breathes forever,
  /// so a settling pump would never return.
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
  });

  /// [denied] decides whether any nudge is up at all — the notification one
  /// is the only one a test host can reach (alarms-denied is iOS-only and
  /// battery is a platform channel), and one is all this needs.
  Future<NivaatController> armed({required bool denied}) async {
    SharedPreferences.setMockInitialValues({});
    final store = NivaatStore();
    await store.saveCourts([court]);
    await store.saveAlarms(
        const [NivaatAlarm(id: 1, hour: 6, minute: 0, courtId: 'c1')]);
    final c = NivaatController(
      engine: NivaatEngine(
        store: store,
        scheduler: SilentRing(),
        api: SilentApi(),
        checks: SilentChecks(),
        notifier: denied ? _DeniedNotifier() : SilentNotifier(),
      ),
    );
    await c.init();
    return c;
  }

  Future<void> pumpHome(WidgetTester tester, NivaatController c) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildOledTheme(AppPalette.wind),
      home: HomeScreen(controller: c),
    ));
    // Twice: the nudge decides whether to draw in an async check on mount.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a nudge clears the list by what the caveat below it does',
      (tester) async {
    await pumpHome(tester, await armed(denied: true));

    // The card itself, not the `NudgeBanner` box — that one includes the 12pt
    // margin between stacked nudges, which is a different measurement and the
    // one that used to be doing this job on its own.
    final card = tester.getRect(find.descendant(
        of: find.byType(NudgeBanner), matching: find.byType(DecoratedBox)));
    final list = tester.getRect(find.byType(ListView));
    final caveat = tester.getRect(find.text(nivaatBackgroundNote));

    final above = list.top - card.bottom;
    final below = caveat.top - list.bottom;
    expect(above, below,
        reason: 'the nudge stack and the caveat sit either side of the same '
            'list and must hold it off by the same amount');
    expect(above, greaterThan(12),
        reason: "12 is the nudges' own margin — the point is that the last "
            'one clears the list by more than it clears its neighbour');
  });

  testWidgets('and none of it shows when there is no nudge', (tester) async {
    // The gap belongs to a nudge, so a home screen with every permission in
    // order — which is most of them — must not be pushed down by it. This is
    // the whole reason `_NoticeStack` measures its child instead of padding
    // it: nothing at build time knows whether a nudge is up.
    await pumpHome(tester, await armed(denied: false));
    expect(find.byType(NudgeBanner), findsNothing, reason: 'precondition');

    final bar = tester.getRect(
        find.ancestor(of: find.text('NIVAAT'), matching: find.byType(Row)).first);
    final list = tester.getRect(find.byType(ListView));
    expect(list.top - bar.bottom, 8,
        reason: "the top bar's own 8pt and nothing else — an unconditional "
            'gap here would open black under a nudge that is not there');
  });
}

/// The one nudge a test host can raise: notifications reported as denied.
class _DeniedNotifier extends SilentNotifier {
  @override
  Future<bool> notificationsDenied() async => true;
}

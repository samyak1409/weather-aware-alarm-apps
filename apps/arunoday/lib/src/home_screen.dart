import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'controller.dart';
import 'messages.dart';
import 'notifications.dart';
import 'screenshot_harness.dart';
import 'settings_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.permissionFlow,
  });

  final ArunodayController controller;

  /// The startup notification-permission request; its completion re-checks
  /// the denied-banner (see [NotificationPermissionBanner.recheckAfter]).
  final Future<void>? permissionFlow;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  ArunodayController get c => widget.controller;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.addListener(_onChanged);
    // The "in Xh Ym" countdowns age by the minute.
    _ticker = Timer.periodic(
        const Duration(minutes: 1), (_) => _onChanged());
    if (kScreenshotHarness) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(runScreenshotHarness(context, c));
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.resync();
  }

  Future<void> _addLocation() async {
    final place = await showLocationSearch(context, validate: c.placeRefusal);
    if (place == null || !mounted) return;
    final loc = place.toSavedLocation();
    await c.update(c.settings.copyWith(
      locations: [...c.settings.locations, loc],
      activeLocationId: () => loc.id,
    ));
  }

  /// The one top bar, built the same on both branches (2026-08-15, Samyak).
  ///
  /// The tune icon used to appear only once there was a location, so the empty
  /// screen had no way into settings at all — you could not change the tone or
  /// the app icon until you had added a place, and the one screen that most
  /// wants a way forward had only the button in the middle of it. Nivaat's has
  /// always been on both, which is the shape this follows.
  /// The 8pt below it is Nivaat's `fromLTRB(28, 24, 28, 8)`, which this now
  /// matches exactly: 24 above the label, 8 under the bar. It had none, so the
  /// first banner sat 8pt tighter to the bar here than there — the same bar,
  /// the same banner, two apps.
  Widget _topBar(TextTheme text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('ARUNODAY', style: text.labelSmall),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            color: AppPalette.textSecondary,
            onPressed: () => showSettingsSheet(context, c),
          ),
        ],
      ),
    );
  }

  /// Active "sleep late" re-ring, if one is pending.
  DateTime? get _delayedUntil {
    final d = c.settings.bedtimeDelayedUntil;
    return (d != null && d.isAfter(DateTime.now())) ? d : null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!c.loaded) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final loc = c.activeLocation;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              Expanded(
                child: loc == null ? _empty(text) : _main(text, loc),
              ),
              // Below every branch, so the maker's mark never disappears.
              const CraftedBy(accent: AppPalette.dawn),
            ],
          ),
        ),
      ),
    );
  }

  /// A9. **Fills the screen when it fits, scrolls when it doesn't**
  /// (2026-08-13, with the 64px hero): the 1:2 spacer rhythm has no give in
  /// it, so the sentence plus its body ran off the bottom of a 375pt phone the
  /// moment the system text size went up — 55px over at 1.3x, and 432px over
  /// at 2x even at the old 28px, so this was already broken for anyone using
  /// large text. `IntrinsicHeight` under a `minHeight` of the viewport is what
  /// lets the Spacers keep their rhythm on every screen that fits.
  Widget _empty(TextTheme text) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: _introBody(text)),
        ),
      ),
    );
  }

  Widget _introBody(TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _topBar(text),
        const Spacer(),
        // The hero size, in step with Nivaat's N14 (2026-08-13, Samyak): on
        // the empty screen this one sentence IS the app, so it gets the same
        // 64 the wake clock gets once there is a wake to show.
        Text('Wake with the dawn.', style: text.displayLarge),
        const SizedBox(height: 12),
        Text(
          'Add your location — the alarm follows its real dawn, every day of the year.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.tonal(
          onPressed: _addLocation,
          child: const Text('Add location'),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  /// The armed home. **Fills or scrolls, exactly like [_empty]** — and for a
  /// sharper reason: this column carries a 72pt clock, a 40pt one, four label
  /// lines and up to two banners, with no flex in any of it. Measured on a
  /// 375pt phone it ran 30px over at 1.3x text and 718px over at 2x (the 2x
  /// break predates the bigger type — it was 483px over at the old 64/28).
  Widget _main(TextTheme text, SavedLocation loc) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: _mainBody(text, loc)),
        ),
      ),
    );
  }

  Widget _mainBody(TextTheme text, SavedLocation loc) {
    final nextWake = c.nextWake;
    // Which dawn the footer names — always the next one, decided on the
    // controller so a test can stand either side of it (2026-08-13).
    final footer = c.footerDawnAt(DateTime.now());
    final bed = c.bedtimeMinutes;
    final sleep = c.tonightSleepMinutes;
    final offset = c.settings.wakeOffsetMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        _topBar(text),
        if (!kScreenshotHarness) ...[
          // Armed-home only (location set) — empty intro stays clean
          // (2026-07-22, same rule as Nivaat's ≥1-alarm gate).
          // **Vertical rhythm matched to Nivaat's** (2026-08-15). Both apps
          // stack the same two banners under the same top bar, and these
          // carried `top: 16, bottom: 4` against the shared default's
          // `bottom: 12` — so a pair of banners was 20pt apart here and 12pt
          // apart there, and the gap to what followed was 4 against 12. Only
          // the horizontal is app-specific: this column is already inset 28,
          // where Nivaat's children inset themselves.
          const AlarmPermissionBanner(
            appName: 'Arunoday',
            accent: AppPalette.dawn,
            margin: EdgeInsets.only(bottom: 12),
          ),
          // Android-only: the iOS rings are AlarmKit's own full-screen alerts,
          // so Arunoday posts nothing through this permission there. On Android
          // a denied permission leaves the ring as bare sound — no card, no
          // full-screen, no Stop outside the app.
          if (Platform.isAndroid)
            NotificationPermissionBanner(
              accent: AppPalette.dawn,
              margin: const EdgeInsets.only(bottom: 12),
              denied: notificationsDenied,
              recheckAfter: widget.permissionFlow,
              message: kArunodayNotificationsOff,
            ),
        ],
        const Spacer(),
        // **`!`, not a `—` fallback** (Samyak, 2026-08-15). This branch needs
        // a location, and a location with no daily dawn is refused when you
        // add it (A16), so dawn — and everything derived from it — resolves.
        // No-location is the empty intro above (A9). The `—` was defence
        // against a state no screen can render, and neither app has shipped:
        // a crash here is a bug report, where a `—` is a wrong number nobody
        // ever finds out about.
        // 72, above the theme's 64 (2026-08-13, Samyak). Local rather than a
        // bump to `displayLarge`, because that style is also both settings
        // pickers' — this is the one place on a home screen that wants the
        // biggest number there is. `scaleDown` for the same reason the ring
        // clock has one: at double system text five characters at 72 no longer
        // fit a 375pt phone, and a clock that WRAPS is worse than one that
        // shrinks (the column scrolls now, so nothing would flag it).
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            fmtClock(nextWake!),
            maxLines: 1,
            style: text.displayLarge!.copyWith(fontSize: 72),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          arunodayWakeLine(
            offsetMinutes: offset,
            enabled: c.settings.wakeEnabled,
            nextWake: nextWake,
          ),
          style: text.labelSmall,
        ),
        const SizedBox(height: 40),
        Text(
          fmtMinutesOfDay(bed!),
          // The second clock moves 28 → 40 with it, so the pair keeps its
          // relationship instead of the bedtime shrinking away beside a
          // bigger wake.
          style: text.displayMedium,
        ),
        const SizedBox(height: 4),
        Text(
          arunodayBedtimeLine(
            mode: c.bedtimeModeDescription,
            enabled: c.settings.bedtimeEnabled,
            again: _delayedUntil,
            sleepMinutes: sleep,
            nextRing: c.nextBedtimeRing,
          ),
          style: text.labelSmall,
        ),
        const Spacer(flex: 2),
        if (footer != null) ...[
          Text(
            arunodayFooterLine(footer.dawn, footer.sunrise,
                rolled: footer.rolled),
            style: text.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(loc.name, style: text.bodyMedium),
        ],
        // Gap above CraftedBy — keep the mark parked, push the dawn/location
        // lines up (2026-07-20, Samyak: was reading too tight).
        const SizedBox(height: 40),
      ],
    );
  }
}

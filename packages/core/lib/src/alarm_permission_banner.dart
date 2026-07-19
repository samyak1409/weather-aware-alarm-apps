import 'package:flutter/material.dart';

import 'alarmkit_scheduler.dart';
import 'nudge_banner.dart';
import 'system_settings.dart';

/// Shown when the user has **denied** AlarmKit on iOS. Since iOS has no
/// `alarm`-package fallback (by design), a denied permission means nothing can
/// ring — so this banner tells the user plainly and opens Settings to fix it.
///
/// Self-contained: it checks [alarmSchedulingDenied] on mount and on every app
/// resume (so returning from Settings hides it), and renders nothing when
/// alarms are allowed or on Android. Drop it into a home screen's column.
class AlarmPermissionBanner extends StatefulWidget {
  const AlarmPermissionBanner({
    super.key,
    required this.appName,
    required this.accent,
    this.margin = const EdgeInsets.fromLTRB(28, 0, 28, 12),
  });

  /// e.g. 'Arunoday' / 'Nivaat' — named in the message.
  final String appName;

  /// The app's accent (`AppPalette.dawn` / `.wind`) for the action.
  final Color accent;

  /// Outer margin. Defaults to 28-inset for screens whose column isn't already
  /// padded; pass a no-horizontal margin where the parent already insets.
  final EdgeInsetsGeometry margin;

  @override
  State<AlarmPermissionBanner> createState() => _AlarmPermissionBannerState();
}

class _AlarmPermissionBannerState extends State<AlarmPermissionBanner>
    with WidgetsBindingObserver {
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check when the user comes back — e.g. after toggling the setting.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final denied = await alarmSchedulingDenied();
    if (mounted && denied != _denied) setState(() => _denied = denied);
  }

  @override
  Widget build(BuildContext context) {
    if (!_denied) return const SizedBox.shrink();
    return NudgeBanner(
      message: 'Alarms are turned off — ${widget.appName} can\'t ring until '
          'you allow alarms for it in Settings.',
      actionLabel: 'Open Settings',
      // The banner is iOS-only, so this never runs on Android.
      onAction: openIosAppSettings,
      accent: widget.accent,
      margin: widget.margin,
    );
  }
}

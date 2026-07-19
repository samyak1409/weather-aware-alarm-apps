import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'alarmkit_scheduler.dart';
import 'theme.dart';

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
    final text = Theme.of(context).textTheme;
    return Container(
      margin: widget.margin,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alarms are turned off — ${widget.appName} can\'t ring until you '
            'allow alarms for it in Settings.',
            style: text.bodyMedium!.copyWith(color: AppPalette.textPrimary),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            // iOS `app-settings:` opens this app's Settings page (the banner is
            // iOS-only, so this never runs on Android).
            onTap: () => launchUrl(Uri.parse('app-settings:')),
            child: Text(
              'Open Settings',
              style: text.labelSmall!.copyWith(color: widget.accent),
            ),
          ),
        ],
      ),
    );
  }
}

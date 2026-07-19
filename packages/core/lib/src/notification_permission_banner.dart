import 'package:flutter/material.dart';

import 'nudge_banner.dart';
import 'system_settings.dart';

/// Shown when the user has **denied** notification permission. Alarms still
/// ring on both platforms (sound isn't gated by it), but everything the app
/// SAYS through notifications is silently dropped — and on Android that
/// includes the ring's own card/full-screen UI, leaving sound with no visible
/// way to stop it. The OS stops re-showing the permission dialog after the
/// second deny, so this banner is the durable way back (via Settings).
///
/// [denied] is injected because the notifications plugin lives in the apps,
/// not in core. It must return true only for a real denial — never before the
/// user has answered the first-run prompt, or the banner would flash behind
/// that dialog (the apps gate it on an "asked" flag).
///
/// Re-checks on mount, on every app resume (so returning from Settings hides
/// it), and when [recheckAfter] completes — pass the startup
/// permission-request future so the user's answer updates the banner the
/// moment the dialog closes.
class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({
    super.key,
    required this.message,
    required this.accent,
    required this.denied,
    this.recheckAfter,
    this.margin = const EdgeInsets.fromLTRB(28, 0, 28, 12),
  });

  /// App- and platform-specific consequence, in plain words (what the user
  /// loses — e.g. Nivaat's skip cards, Arunoday's ring card).
  final String message;

  /// The app's accent (`AppPalette.dawn` / `.wind`) for the action.
  final Color accent;

  /// Whether notification permission is definitively denied right now.
  final Future<bool> Function() denied;

  /// Optional: a future whose completion should trigger a re-check (the
  /// startup permission request).
  final Future<void>? recheckAfter;

  final EdgeInsetsGeometry margin;

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> with WidgetsBindingObserver {
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    widget.recheckAfter?.whenComplete(_refresh);
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
    final denied = await widget.denied();
    if (mounted && denied != _denied) setState(() => _denied = denied);
  }

  @override
  Widget build(BuildContext context) {
    if (!_denied) return const SizedBox.shrink();
    return NudgeBanner(
      message: widget.message,
      actionLabel: 'Turn on notifications',
      onAction: openNotificationSettings,
      accent: widget.accent,
      margin: widget.margin,
    );
  }
}

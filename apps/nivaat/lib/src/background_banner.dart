import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import 'battery_optimization.dart';

/// Shown while the OS is set to throttle the background wind checks — battery
/// optimisation not exempted (Android) or Background App Refresh off (iOS).
/// The startup dialog asks only once; denying it must not be the end of the
/// story (user decision 2026-07-19), so this keeps the fix one tap away:
/// Android re-shows the system dialog (allowed any number of times), iOS
/// opens the app's Settings page. Re-checks on every resume and when
/// [recheckAfter] (the startup once-ask flow) settles — and stays hidden
/// while that flow's dialog is up ([batteryAskInFlight]), so it never
/// flashes behind it.
class BackgroundChecksBanner extends StatefulWidget {
  const BackgroundChecksBanner({
    super.key,
    this.recheckAfter,
    this.margin = const EdgeInsets.fromLTRB(28, 0, 28, 12),
  });

  /// Optional: a future whose completion should trigger a re-check (the
  /// startup [requestBatteryExemptionOnce] flow).
  final Future<void>? recheckAfter;

  final EdgeInsetsGeometry margin;

  @override
  State<BackgroundChecksBanner> createState() => _BackgroundChecksBannerState();
}

class _BackgroundChecksBannerState extends State<BackgroundChecksBanner>
    with WidgetsBindingObserver {
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
    // Covers every path here: the answered first-run dialog (which also ends
    // its suppression window), back from the re-shown dialog, back from
    // Settings.
    if (state == AppLifecycleState.resumed) {
      batteryAskInFlight = false;
      _refresh();
    }
  }

  Future<void> _refresh() async {
    // The first-run dialog may be on screen right now — showing the banner
    // behind it is noise; the resume its answer fires re-checks honestly.
    if (batteryAskInFlight) return;
    final denied = await backgroundWorkDenied();
    if (mounted && denied != _denied) setState(() => _denied = denied);
  }

  @override
  Widget build(BuildContext context) {
    if (!_denied) return const SizedBox.shrink();
    return NudgeBanner(
      message: Platform.isAndroid
          ? 'Battery optimisation can delay or skip Nivaat\'s background '
              'wind checks — it could miss a wind change and ring on a windy '
              'morning, or stay silent on a calm one.'
          : 'Background App Refresh is off — Nivaat can only check the wind '
              'while the app is open.',
      actionLabel:
          Platform.isAndroid ? 'Allow background use' : 'Open Settings',
      onAction: requestBackgroundWork,
      accent: AppPalette.wind,
      margin: widget.margin,
    );
  }
}

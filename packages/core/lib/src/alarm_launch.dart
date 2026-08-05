import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Did an ALARM put this app on screen? Served by a tiny MethodChannel that
/// BOTH apps' MainActivities implement (core is app-agnostic, so the channel
/// name is shared — keep the Kotlin in sync).
const MethodChannel _launchChannel = MethodChannel('core/alarm_launch');

/// The id of the alarm whose ring opened the app, or null when the user did.
///
/// **Consumed, not read** — the platform clears it as it hands it over, so the
/// next ring cannot inherit this one's answer.
///
/// This replaced a timer (`kRingForegroundGrace`, deleted 2026-08-05). Until
/// `alarm` 5.7.0 the plugin opened the launcher intent, byte-identical to
/// tapping the icon, so Dart could only guess from how recently the app had
/// resumed — and the guess was wrong in both directions. Declaring the
/// plugin's `RING` action on the launcher activities (see either
/// AndroidManifest) means the alarm now arrives as its own action carrying the
/// alarm id, and `MainActivity` records it **only when it was not already on
/// screen**. So "the alarm opened us" is a fact from the OS rather than a
/// window we picked.
///
/// **Android only, and there is nothing to port.** iOS rings are AlarmKit
/// system alerts that never open the app, so there is no launch to attribute —
/// the same reason `sendAppToBackground` (app_window.dart) is Android-only.
/// [defaultTargetPlatform] rather than `Platform.isAndroid` so both branches
/// stay host-testable.
Future<int?> consumeAlarmLaunch() async {
  if (defaultTargetPlatform != TargetPlatform.android) return null;
  try {
    return await _launchChannel.invokeMethod<int>('consumeAlarmLaunch');
  } on PlatformException {
    // The platform refused. Same rule as everywhere on this path: the ring has
    // already stopped, which is the part that mattered.
    return null;
  } on MissingPluginException {
    // Host app forgot the channel.
    return null;
  }
}

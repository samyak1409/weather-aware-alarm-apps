import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hides the app again after a ring the user never asked to open it — served
/// by a tiny MethodChannel that BOTH apps' MainActivities implement (core is
/// app-agnostic, so the channel name is shared — keep the Kotlin in sync).
const MethodChannel _windowChannel = MethodChannel('core/app_window');

/// Puts the app back behind whatever was on screen before it appeared.
///
/// `moveTaskToBack`, not `finish`: the task survives, so the next open is warm
/// and any alarm still ringing keeps its notification. What this undoes is the
/// full-screen intent's side effect — it opens the app to show the ring screen,
/// and without this you unlock at 6:05 to find it sitting there.
///
/// **Android only, and there is nothing to port.** iOS ships no API for an app
/// to background itself (`exit(0)` is a rejection) and needs none: rings there
/// are AlarmKit system alerts, so a ring never opens the app at all — its
/// `StopIntent` is a `LiveActivityIntent` with no `openAppWhenRun` (read in
/// flutter_alarmkit's Swift, not assumed). [defaultTargetPlatform] rather than
/// `Platform.isAndroid` so both branches are reachable in host tests.
Future<void> sendAppToBackground() async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await _windowChannel.invokeMethod<void>('moveTaskToBack');
  } on PlatformException {
    // Nothing to hide, or the platform refused. Never worth surfacing — the
    // ring has already stopped, which is the part that mattered.
  } on MissingPluginException {
    // Host app forgot the channel; same rule.
  }
}

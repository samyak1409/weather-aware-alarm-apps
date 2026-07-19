import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Channel served by MainActivity.kt (Android) and AppDelegate.swift (iOS) —
/// both sides answer `isExempt` ("may background work run un-throttled?").
const MethodChannel _channel = MethodChannel('nivaat/battery');
const String _askedKey = 'nivaat.batteryExemptionAsked';

/// True while this launch's once-ask dialog may still be on screen. The
/// banner suppresses itself until the first app-resume clears it, so it never
/// flashes behind the very dialog that grants it (device-caught 2026-07-20).
/// Set synchronously at the top of [requestBatteryExemptionOnce] (before its
/// first await, i.e. before the banner can possibly check), cleared on every
/// no-dialog path — and otherwise by the resume that answers the dialog.
bool batteryAskInFlight = false;

/// Asks — once — for exemption from Android battery optimisation, so the
/// cascade's exact-alarm wind checks aren't Doze-throttled when the phone is
/// off charger (Doze rate-limits `allowWhileIdle` alarms to ~1 per 9 min and
/// suspends their network). No-op on iOS, if already exempt, or if already
/// asked. Denial is NOT the end of it: [BackgroundChecksBanner] stays on the
/// home screen while un-exempt, re-offering this dialog (which, unlike
/// runtime permissions, may be shown any number of times).
Future<void> requestBatteryExemptionOnce() async {
  if (!Platform.isAndroid) return;
  batteryAskInFlight = true;
  try {
    final exempt = await _channel.invokeMethod<bool>('isExempt') ?? false;
    if (exempt) {
      batteryAskInFlight = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) ?? false) {
      batteryAskInFlight = false;
      return;
    }
    await prefs.setBool(_askedKey, true);
    await _channel.invokeMethod<bool>('requestExempt');
    // Leave batteryAskInFlight set: the dialog is (about to be) up, and the
    // app-resume that its answer triggers is what clears it.
  } on PlatformException {
    // A missing channel / denied request must never break startup.
    batteryAskInFlight = false;
  }
}

/// True when the OS is set to throttle Nivaat's background wind checks in a
/// way the user can fix: Android — not exempt from battery optimisation;
/// iOS — Background App Refresh turned off (the periodic refresh is then
/// never granted; background checking effectively stops). false on channel
/// errors: never nag off a guess.
Future<bool> backgroundWorkDenied() async {
  try {
    return !(await _channel.invokeMethod<bool>('isExempt') ?? true);
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// The fix path for [backgroundWorkDenied]: Android re-shows the system
/// "ignore battery optimisations?" dialog; iOS can only open the app's
/// Settings page (Background App Refresh lives there).
Future<void> requestBackgroundWork() async {
  if (Platform.isAndroid) {
    try {
      await _channel.invokeMethod<bool>('requestExempt');
    } on PlatformException {
      // Nothing else to try.
    }
  } else {
    await openIosAppSettings();
  }
}

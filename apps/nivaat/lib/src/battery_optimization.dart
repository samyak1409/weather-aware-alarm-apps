import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _channel = MethodChannel('nivaat/battery');
const String _askedKey = 'nivaat.batteryExemptionAsked';

/// Asks — once — for exemption from Android battery optimisation, so the
/// cascade's exact-alarm wind checks aren't Doze-throttled when the phone is
/// off charger (Doze rate-limits `allowWhileIdle` alarms to ~1 per 9 min and
/// suspends their network). No-op on iOS, if already exempt, or if already
/// asked (we don't nag — the user can enable it later in battery settings).
Future<void> requestBatteryExemptionOnce() async {
  if (!Platform.isAndroid) return;
  try {
    final exempt = await _channel.invokeMethod<bool>('isExempt') ?? false;
    if (exempt) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) ?? false) return;
    await prefs.setBool(_askedKey, true);
    await _channel.invokeMethod<bool>('requestExempt');
  } on PlatformException {
    // A missing channel / denied request must never break startup.
  }
}

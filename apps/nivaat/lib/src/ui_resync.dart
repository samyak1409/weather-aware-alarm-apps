import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'controller.dart';

/// Cross-isolate poke so a background wind check can refresh the open UI
/// the moment it writes history / posts a skip card (2026-07-22).
///
/// SharedPreferences is per-isolate-cached: without this, home + History stay
/// stale until resume/nav even though the notification already fired.
const String kNivaatUiResyncPort = 'nivaat.ui_resync';

ReceivePort? _uiPort;

/// Call once from the UI isolate (`main`) after [controller] exists.
void registerNivaatUiResync(NivaatController controller) {
  _uiPort?.close();
  IsolateNameServer.removePortNameMapping(kNivaatUiResyncPort);
  final port = ReceivePort();
  _uiPort = port;
  IsolateNameServer.registerPortWithName(port.sendPort, kNivaatUiResyncPort);
  port.listen((_) {
    unawaited(controller.resync());
  });
}

/// No-op when the UI isn't running. Safe to call from background isolates
/// after [NivaatEngine.evaluateAll] (and thus after any skip/heads-up notify).
void pingNivaatUiResync() {
  final send = IsolateNameServer.lookupPortByName(kNivaatUiResyncPort);
  if (send == null) return;
  try {
    send.send(null);
  } on Exception catch (e) {
    debugPrint('nivaat ui resync ping failed (non-fatal): $e');
  }
}

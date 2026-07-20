import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller.dart';
import 'settings_sheet.dart';

/// Opens `screenshot.target` after home settles (harness builds only).
Future<void> runScreenshotHarness(
  BuildContext context,
  ArunodayController c,
) async {
  if (!kScreenshotHarness || !context.mounted) return;
  final prefs = await SharedPreferences.getInstance();
  final target = prefs.getString('screenshot.target');
  if (target == null || target.isEmpty || !context.mounted) return;

  // Wait until store-backed state is ready (locations/settings).
  for (var i = 0; i < 50 && !c.loaded; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  if (!context.mounted) return;
  await Future<void>.delayed(const Duration(milliseconds: 400));
  if (!context.mounted) return;

  // Only `settings` is in the 3-shot set (see screenshots/README.md).
  if (target == 'settings') {
    showSettingsSheet(context, c);
  }
}

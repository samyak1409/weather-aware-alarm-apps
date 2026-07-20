import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user-facing appearance switches, shared by both apps (2026-07-20).
///
/// Heavy hero type started as an app-wide experiment; Samyak wasn't sure it
/// reads better, so it became a settings toggle instead — ships OFF (the
/// original thin look), ON restores the heavy w700/w600 clocks. The value is
/// a [ValueNotifier] so each app's `MaterialApp` can rebuild its theme live
/// (`ValueListenableBuilder` in main.dart) the moment the switch flips.
class Appearance {
  Appearance._();

  static const _heavyKey = 'appearance.heavyType';

  /// Whether `buildOledTheme(heavyType:)` uses the heavy hero styles.
  static final ValueNotifier<bool> heavyType = ValueNotifier(false);

  /// Call once from `main()` before `runApp` (cheap: SharedPreferences is
  /// already warmed by the stores).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    heavyType.value = prefs.getBool(_heavyKey) ?? false;
  }

  static Future<void> setHeavyType(bool value) async {
    heavyType.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_heavyKey, value);
  }
}

/// The settings row for [Appearance.heavyType] — same in both apps.
class HeavyTypeSwitch extends StatelessWidget {
  const HeavyTypeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<bool>(
      valueListenable: Appearance.heavyType,
      builder: (context, heavy, child) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Bold clocks & titles'),
        subtitle: Text('Heavier type on the home screen',
            style: text.bodyMedium),
        value: heavy,
        onChanged: (v) => unawaited(Appearance.setHeavyType(v)),
      ),
    );
  }
}

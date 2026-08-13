import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The user-facing appearance switches, shared by both apps (2026-07-20).
///
/// Heavy hero type started as an app-wide experiment; Samyak wasn't sure it
/// reads better, so it became a settings toggle — and it shipped OFF, with the
/// original thin look as the default. **It ships ON since 2026-08-13**: the
/// same day the heroes grew (home clock 72, intro sentence 64, ring clock 130),
/// and at that size the w200 thin face reads washed out where w700 reads
/// deliberate. Off is still one tap away and still exactly the old look.
///
/// The value is a [ValueNotifier] so each app's `MaterialApp` can rebuild its
/// theme live (`ValueListenableBuilder` in main.dart) the moment the switch
/// flips.
class Appearance {
  Appearance._();

  static const _heavyKey = 'appearance.heavyType';

  /// Whether `buildOledTheme(heavyType:)` uses the heavy hero styles.
  /// Defaults must agree in both places — the notifier's seed is what a
  /// screen built before [load] finishes uses, and the `??` is what a first
  /// run reads off disk.
  static final ValueNotifier<bool> heavyType = ValueNotifier(true);

  /// Call once from `main()` before `runApp` (cheap: SharedPreferences is
  /// already warmed by the stores).
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    heavyType.value = prefs.getBool(_heavyKey) ?? true;
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

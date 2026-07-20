import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Switchable launcher icons (2026-07-20, Samyak) — both apps ship three
/// candidates; the pick lives in each app's Settings. Ids are "1"/"2"/"3":
/// on Android "1" is MainActivity's own manifest icon and "2"/"3" enable the
/// .IconTwo/.IconThree activity-aliases (exactly one launcher component
/// enabled at a time); on iOS they map to the primary AppIcon and the
/// AppIconTwo/AppIconThree alternate sets. Served by the `core/app_icon`
/// MethodChannel implemented in BOTH MainActivities and BOTH AppDelegates.
const MethodChannel appIconChannel = MethodChannel('core/app_icon');

/// The active icon id; "1" when unanswered (fresh install, errors).
Future<String> currentAppIcon() async {
  try {
    return await appIconChannel.invokeMethod<String>('get') ?? '1';
  } on PlatformException {
    return '1';
  } on MissingPluginException {
    return '1';
  }
}

/// Switch the launcher icon; false when the platform refused. On iOS the
/// system confirms with its own alert; on Android some launchers take a
/// moment (and may move a home-screen shortcut) — documented behavior.
Future<bool> setAppIcon(String id) async {
  try {
    return await appIconChannel
            .invokeMethod<bool>('set', <String, String>{'id': id}) ??
        false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// One selectable launcher icon in [AppIconPicker].
class AppIconChoice {
  const AppIconChoice({
    required this.id,
    required this.label,
    required this.asset,
  });

  /// Native id, "1"/"2"/"3".
  final String id;

  /// User-facing name under the thumbnail (e.g. "Horizon").
  final String label;

  /// In-app thumbnail (the 256px `assets/icons/<id>.png`).
  final String asset;
}

/// The settings row for picking the launcher icon — same in both apps.
class AppIconPicker extends StatefulWidget {
  const AppIconPicker({
    super.key,
    required this.choices,
    required this.accent,
  });

  final List<AppIconChoice> choices;
  final Color accent;

  @override
  State<AppIconPicker> createState() => _AppIconPickerState();
}

class _AppIconPickerState extends State<AppIconPicker> {
  String _selected = '1';

  @override
  void initState() {
    super.initState();
    currentAppIcon().then((id) {
      if (mounted) setState(() => _selected = id);
    });
  }

  Future<void> _pick(AppIconChoice choice) async {
    if (choice.id == _selected) return;
    // Select optimistically: iOS runs setAlternateIconName's completion only
    // after the user dismisses its "You have changed the icon" alert, and the
    // ring shouldn't lag behind the tap that whole time (device-caught
    // 2026-07-20). Reverted if the platform refuses.
    final previous = _selected;
    setState(() => _selected = choice.id);
    if (!await setAppIcon(choice.id)) {
      if (mounted) setState(() => _selected = previous);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('App icon'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final choice in widget.choices) ...[
                GestureDetector(
                  onTap: () => _pick(choice),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            width: 2,
                            color: choice.id == _selected
                                ? widget.accent
                                : AppPalette.hairline,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.asset(
                            choice.asset,
                            width: 60,
                            height: 60,
                            // A missing thumbnail must never take the
                            // settings page down with it.
                            errorBuilder: (context, error, stack) => Container(
                              width: 60,
                              height: 60,
                              color: AppPalette.surface,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        choice.label,
                        style: text.bodyMedium!.copyWith(
                          fontSize: 12,
                          color: choice.id == _selected
                              ? AppPalette.textPrimary
                              : AppPalette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

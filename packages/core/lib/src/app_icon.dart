import 'package:flutter/foundation.dart';
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

/// Switch the launcher icon; false when the platform refused.
///
/// The platforms end differently and neither is a failure: iOS keeps running
/// and shows its own "You have changed the icon" alert, Android **closes the
/// app** (see [appIconRestartWarning]) and launchers may take a moment to
/// redraw. On Android, warn first via [AppIconPicker].
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

/// Android-only body of the notice shown before a switch (MESSAGES.md X7).
///
/// **Why Android can't stay open:** a switch disables the launcher component
/// the running task was started from, and Android tears that task down —
/// `DONT_KILL_APP` spares the process, not the activity. Unpreventable while
/// `MainActivity` keeps the launcher intent-filter, which it must (moving it
/// onto an alias breaks `flutter run`). Unannounced the close reads as a
/// crash (2026-08-01, device-caught).
///
/// **One line, and it stays one line** — an acknowledgement, not a question.
/// Naming Android as the actor is the whole job.
String appIconRestartWarning(String appName) =>
    'Android will close $appName to apply the new icon.';

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
    required this.appName,
  });

  final List<AppIconChoice> choices;
  final Color accent;

  /// `Arunoday` / `Nivaat` — named in the Android confirm dialog
  /// ([appIconRestartWarning]).
  final String appName;

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
    // Android dies on the switch, so say so first. iOS must NOT get this —
    // the OS runs its own alert, so ours would be pure friction.
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!await _warnAndroidClose() || !mounted) return;
    }
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

  /// Information plus one button, not a question (2026-08-01, Samyak —
  /// tapping a thumbnail already said what you want). Barrier or back still
  /// returns false, leaving icon and ring untouched.
  Future<bool> _warnAndroidClose() async {
    final text = Theme.of(context).textTheme;
    final ok = await showDialog<bool>(
      context: context,
      // Explicit though it is the default: with Cancel gone this is the ONLY
      // way out, so locking it down would strand the user. A test taps it.
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Text('CHANGE APP ICON', style: text.labelSmall),
        content: Text(appIconRestartWarning(widget.appName)),
        // M3's 24 under the message plus 24 under the button left the single
        // word marooned in an empty box (2026-08-01, device-caught).
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return ok ?? false;
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

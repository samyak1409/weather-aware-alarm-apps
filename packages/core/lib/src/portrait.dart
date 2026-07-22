import 'package:flutter/services.dart';

/// Portrait-only for both apps (2026-07-22, Samyak): home / sheets / dialogs
/// overflow on phone landscape, so v1 locks orientation instead of a layout
/// pass. Call once from `main()` after [WidgetsFlutterBinding.ensureInitialized].
///
/// Native locks must stay in sync: Android `screenOrientation="portrait"` on
/// each MainActivity, and iOS Info.plist `UISupportedInterfaceOrientations`
/// (phone + iPad) listing only `UIInterfaceOrientationPortrait`, plus
/// `UIRequiresFullScreen` so iPad multitasking can't ignore the orientation.
Future<void> lockToPortrait() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}

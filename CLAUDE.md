# weather-aware-alarm-apps monorepo

Two Flutter alarm apps sharing one core package. **Read SPEC.md before changing any behavior — every product decision there is locked with Samyak; don't silently re-decide.**

## Layout

- `packages/core` — pure logic: solar math, sleep plan, wind engine, Open-Meteo client, theme, models, repos. **All business logic lives here, fully unit-tested.** Apps stay thin.
- `apps/arunoday` — dawn alarm app (daily driver, priority app).
- `apps/nivaat` — wind-conditional badminton alarm.

## Conventions

- UI: pure black `#000000` scaffolds, dark-only, minimal. Accents: Arunoday `AppPalette.dawn`, Nivaat `AppPalette.wind`. No third-party UI kits.
- Alarm scheduling goes through `core`'s `AlarmScheduler` interface, chosen by `createAlarmScheduler`: **`AlarmKitScheduler` on iOS (min target 26.0)**, `AlarmPkgScheduler` on Android. **iOS is AlarmKit-only — there is NO `alarm`-package fallback** (2026-07-18): if the user denies AlarmKit, `scheduleRing` silently no-ops (`PlatformException` caught) and `AlarmPermissionBanner` (shown on both home screens, driven by `alarmSchedulingDenied()`) nudges them to Settings via `url_launcher` (`app-settings:`). So `AlarmPkgScheduler` is effectively Android-only (`warningNotificationOnKill: false` — Android's ring genuinely survives kill). **Both wake and bedtime rings use AlarmKit on iOS** (2026-07-16: a real system alarm that survives force-quit/reboot beats the `alarm` package's in-process Timer; cost — Arunoday's bedtime "+1h" ritual is **Android-only**, since AlarmKit alerts are Stop-only). Never call the `alarm` package directly from screens, except ring-screen `Alarm.ringing` listeners. (AlarmKit's auth prompt is simulator-verified; real-device iOS ring behavior is still untested.)
- **Cross-platform parity is mandatory — every feature must work on BOTH Android and iOS.** Never ship a path that works on one and silently no-ops on the other. When touching anything platform-shaped (notifications, permissions, plugins, `dart:io`, `Platform.is*`), explicitly verify the _other_ platform has a working equivalent — don't assume a plugin handles it. **Burned once (2026-07-13):** we assumed "the `alarm` package requests iOS notification permission" — it does NOT (it only _checks_ `authorizationStatus` and silently drops the notification), so both apps requested permission on Android only and Nivaat's skip cards / Arunoday's bedtime banner would never have appeared on iOS. Fix: both notifiers now call `IOSFlutterLocalNotificationsPlugin.requestPermissions` too. iOS permission is a single app-level grant, so requesting from multiple places prompts only once — the "avoid double-prompt" fear was unfounded. Rule: **read the plugin's native source before trusting it to request a permission.**
- Times: all solar math is UTC-internal, converted at the edge. Location = saved lat/lon, never GPS.
- **Whole minutes only in the app layer**: `core` computes dawn/sunrise to the second, but the apps floor them to the minute at the controller boundary (`dawnOn`/`sunriseOn`). Dawn's seconds drift ~±25s/day; letting them into wake times makes every derived display (picker anchors, ring moments, sleep math) flicker by one minute. Never quote a second-precise time to the user.
- Tests: `packages/core/test` validates against real-world reference numbers recorded in SPEC.md (Jaipur/Tonk/BLR dawn times, ring-rate expectations). Keep them passing; they are the spec-as-code.
- Verify with `flutter analyze` + `flutter test` in each package/app you touch.
- **Coverage (2026-07-19): 125 tests (core 76, arunoday 27, nivaat 22).** Business logic ~95% line-covered (core 50.3% overall but format 100%, repos 99%, models/wind 96%, sleep_plan 95%, solar 98%; arunoday controller 100%; nivaat controller 100%, engine 95.3%). The uncovered remainder is deliberately not unit-tested: platform-plugin wrappers (`alarm_pkg_scheduler`, `alarmkit_scheduler`, `check_scheduler`, `skip_notifier`, `notifications`, `battery_optimization`), the `open_meteo` HTTP client, and Flutter widgets (`location_picker`, `ring_gate`, `sound_picker`, `alarm_permission_banner`, screens) — these need the device/simulator smoke tests and an integration-test screenshot pass, not unit tests. (`scheduler_test` covers the pure non-iOS guards of `createAlarmScheduler`/`alarmSchedulingDenied`.) `flutter test --coverage` → `coverage/lcov.info`.

## Build notes (hard-won, don't rediscover)

- JDK: brew formula openjdk@21, wired via `flutter config --jdk-dir`. Android SDK: `~/Library/Android/sdk` (headless, no Android Studio); use the SDK's own `cmdline-tools/latest/bin/avdmanager` (the brew one points at the wrong root).
- Both apps force `compileSdk = 36` AND carry a root-gradle reflection override forcing plugin modules to 36 (the `alarm` plugin pins 34 but its `flutter_fgbg` dep needs 35+).
- Nivaat Android needs core-library desugaring (flutter_local_notifications).
- **AGP is 9.0.1 — plugins that self-apply KGP only under AGP < 9 silently fail to compile their Kotlin (class-not-found in `GeneratedPluginRegistrant`).** Burned by `app_settings` 8.0.0 (2026-07-18): it skips `kotlin-android` on AGP≥9, so `AppSettingsPlugin` never built → both apps' Android builds broke. Fix: dropped it for `url_launcher` (Flutter-team, KGP-clean) for the iOS "Open Settings" (`app-settings:`). **Lesson: after any plugin/native change, `flutter build apk` — `flutter test` does NOT build the Android/iOS native side, so plugin-compile breaks stay invisible.**
- Nivaat Android battery-optimization exemption: `MainActivity` exposes a `nivaat/battery` MethodChannel (`isExempt`/`requestExempt` → `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`); `requestBatteryExemptionOnce()` (in `main`) asks once so off-charger Doze doesn't throttle the cascade's network checks. Needs `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` in the manifest.
- Min OS: **Android minSdk 33** (Android 13; set in each `app/build.gradle.kts`) · **iOS deployment target 26.0** (AlarmKit-only ring path; set in each `Runner.xcodeproj/project.pbxproj` and Nivaat's `Podfile`). Nivaat also uses workmanager: the Swift import is `workmanager_apple` (federated module name), plugin class `WorkmanagerPlugin`. **Two iOS BGTask ids** in Info.plist `BGTaskSchedulerPermittedIdentifiers` + registered in `AppDelegate`: `…refresh` (periodic BGAppRefresh, `registerPeriodicTask`) and `…processing` (BGProcessing, `registerBGProcessingTask`). workmanager's `registerProcessingTask(initialDelay:)` **does** set the iOS `earliestBeginDate` (= now+delay); `Constraints.requiresCharging`→`requiresExternalPower`, `networkType:.connected`→`requiresNetworkConnectivity`. BGProcessing is one-shot (no native re-submit) so `scheduleCheck` re-registers it each `evaluateAll`. (`registerOneOffTask`'s `initialDelay` is genuinely ignored on iOS — don't use it for scheduling.)
- AlarmKit: `flutter_alarmkit` takes Flutter asset paths for sounds (WAV < 30s); timestamps are Unix **milliseconds** as double; it assigns its own UUIDs → `AlarmKitScheduler` persists an int-id→UUID map. `NSAlarmKitUsageDescription` required in Info.plist.
- Emulator smoke loop: boot `emulator -avd pixel -no-window`, `adb exec-out screencap -p`. iOS: `xcrun simctl` install/launch/screenshot; seed SharedPreferences by writing the app container's plist while the sim is shut down (simctl spawn defaults writes outside the sandbox — doesn't work).

- `flutter run` prints a KGP deprecation warning ("plugins that apply Kotlin Gradle Plugin (KGP): alarm") — benign, lives in the `alarm` plugin's own build script, nothing on our side to change; goes away when the plugin migrates to Flutter's built-in Kotlin. Track upstream releases.

## Assets & screenshots

- `screenshots/<app>/` is **git-tracked** with stable filenames — history lives in git, never in versioned folder names. Refresh them **only when Samyak explicitly asks** ("update screenshots"), never automatically after UI changes (the capture loop costs him time and tokens).
- Alarm sounds are generated, not sourced: `tools/make_sounds.py` (numpy) synthesizes both WAVs; Nivaat's loudness variants (75-100%, 5% steps) are amplitude-scaled copies of the base. Keep every sound < 30s (AlarmKit hard limit).

## Workflow

- Samyak prefers: TLDR-first answers, simple language with examples, data-verified claims, small focused iterations during implementation.
- Commit checkpoints; he reviews diffs. Don't push anywhere without being asked.

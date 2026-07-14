# weather-aware-alarm-apps monorepo

Two Flutter alarm apps sharing one core package. **Read SPEC.md before changing any behavior — every product decision there is locked with Samyak; don't silently re-decide.**

## Layout

- `packages/core` — pure logic: solar math, sleep plan, wind engine, Open-Meteo client, theme, models, repos. **All business logic lives here, fully unit-tested.** Apps stay thin.
- `apps/arunoday` — dawn alarm app (daily driver, priority app).
- `apps/nivaat` — wind-conditional badminton alarm.

## Conventions

- UI: pure black `#000000` scaffolds, dark-only, minimal. Accents: Arunoday `AppPalette.dawn`, Nivaat `AppPalette.wind`. No third-party UI kits.
- Alarm scheduling goes through `core`'s `AlarmScheduler` interface (`AlarmPkgScheduler` is the v1 impl, in core) — never call the `alarm` package directly from screens, except ring-screen `Alarm.ringing` listeners. AlarmKit swap planned for iOS in v1.1 behind the same interface.
- **Cross-platform parity is mandatory — every feature must work on BOTH Android and iOS.** Never ship a path that works on one and silently no-ops on the other. When touching anything platform-shaped (notifications, permissions, plugins, `dart:io`, `Platform.is*`), explicitly verify the *other* platform has a working equivalent — don't assume a plugin handles it. **Burned once (2026-07-13):** we assumed "the `alarm` package requests iOS notification permission" — it does NOT (it only *checks* `authorizationStatus` and silently drops the notification), so both apps requested permission on Android only and Nivaat's skip cards / Arunoday's bedtime banner would never have appeared on iOS. Fix: both notifiers now call `IOSFlutterLocalNotificationsPlugin.requestPermissions` too. iOS permission is a single app-level grant, so requesting from multiple places prompts only once — the "avoid double-prompt" fear was unfounded. Rule: **read the plugin's native source before trusting it to request a permission.**
- Times: all solar math is UTC-internal, converted at the edge. Location = saved lat/lon, never GPS.
- **Whole minutes only in the app layer**: `core` computes dawn/sunrise to the second, but the apps floor them to the minute at the controller boundary (`dawnOn`/`sunriseOn`). Dawn's seconds drift ~±25s/day; letting them into wake times makes every derived display (picker anchors, ring moments, sleep math) flicker by one minute. Never quote a second-precise time to the user.
- Tests: `packages/core/test` validates against real-world reference numbers recorded in SPEC.md (Jaipur/Tonk/BLR dawn times, ring-rate expectations). Keep them passing; they are the spec-as-code.
- Verify with `flutter analyze` + `flutter test` in each package/app you touch.
- **Coverage (2026-07-13): 109 tests (core 68, arunoday 25, nivaat 16).** Business logic ~90% line-covered (core 46.6% overall but format/repos 100%, models/wind 96%, sleep_plan 95%, solar 98%; arunoday controller 99.4%; nivaat controller 100%, engine 78.6%). The uncovered remainder is deliberately not unit-tested: platform-plugin wrappers (`alarm_pkg_scheduler`, `alarmkit_scheduler`, `check_scheduler`, `skip_notifier`, `notifications`), the `open_meteo` HTTP client, and Flutter widgets (`location_picker`, `ring_gate`, `sound_picker`, screens) — these need the device/simulator smoke tests and the planned integration-test screenshot harness, not unit tests. `flutter test --coverage` → `coverage/lcov.info`.

## Build notes (hard-won, don't rediscover)

- JDK: brew formula openjdk@21, wired via `flutter config --jdk-dir`. Android SDK: `~/Library/Android/sdk` (headless, no Android Studio); use the SDK's own `cmdline-tools/latest/bin/avdmanager` (the brew one points at the wrong root).
- Both apps force `compileSdk = 36` AND carry a root-gradle reflection override forcing plugin modules to 36 (the `alarm` plugin pins 34 but its `flutter_fgbg` dep needs 35+).
- Nivaat Android needs core-library desugaring (flutter_local_notifications).
- Nivaat iOS: deployment target 15.0 (workmanager); the Swift import is `workmanager_apple` (federated module name), plugin class `WorkmanagerPlugin`.
- AlarmKit: `flutter_alarmkit` takes Flutter asset paths for sounds (WAV < 30s); timestamps are Unix **milliseconds** as double; it assigns its own UUIDs → `AlarmKitScheduler` persists an int-id→UUID map. `NSAlarmKitUsageDescription` required in Info.plist.
- Emulator smoke loop: boot `emulator -avd pixel -no-window`, `adb exec-out screencap -p`. iOS: `xcrun simctl` install/launch/screenshot; seed SharedPreferences by writing the app container's plist while the sim is shut down (simctl spawn defaults writes outside the sandbox — doesn't work).

- `flutter run` prints a KGP deprecation warning ("plugins that apply Kotlin Gradle Plugin (KGP): alarm") — benign, lives in the `alarm` plugin's own build script, nothing on our side to change; goes away when the plugin migrates to Flutter's built-in Kotlin. Track upstream releases.

## Assets & screenshots

- `screenshots/<app>/` is **git-tracked** with stable filenames — history lives in git, never in versioned folder names. Refresh them **only when Samyak explicitly asks** ("update screenshots"), never automatically after UI changes (the capture loop costs him time and tokens).
- Alarm sounds are generated, not sourced: `tools/make_sounds.py` (numpy) synthesizes both WAVs; Nivaat's loudness variants (50-100%) are amplitude-scaled copies of the base. Keep every sound < 30s (AlarmKit hard limit).

## Workflow

- Samyak prefers: TLDR-first answers, simple language with examples, data-verified claims, small focused iterations during implementation.
- Commit checkpoints; he reviews diffs. Don't push anywhere without being asked.

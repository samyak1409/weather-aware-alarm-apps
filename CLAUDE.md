# alarm-apps monorepo

Two Flutter alarm apps sharing one core package. **Read SPEC.md before changing any behavior — every product decision there is locked with Samyak; don't silently re-decide.**

## Layout

- `packages/core` — pure logic: solar math, sleep plan, wind engine, Open-Meteo client, theme, models, repos. **All business logic lives here, fully unit-tested.** Apps stay thin.
- `apps/arunoday` — dawn alarm app (daily driver, priority app).
- `apps/nivaat` — wind-conditional badminton alarm.

## Conventions

- UI: pure black `#000000` scaffolds, dark-only, minimal. Accents: Arunoday `AppPalette.dawn`, Nivaat `AppPalette.wind`. No third-party UI kits.
- Alarm scheduling goes through `core`'s `AlarmScheduler` interface (`AlarmPkgScheduler` is the v1 impl, in core) — never call the `alarm` package directly from screens, except ring-screen `Alarm.ringing` listeners. AlarmKit swap planned for iOS in v1.1 behind the same interface.
- Times: all solar math is UTC-internal, converted at the edge. Location = saved lat/lon, never GPS.
- Tests: `packages/core/test` validates against real-world reference numbers recorded in SPEC.md (Jaipur/Tonk/BLR dawn times, ring-rate expectations). Keep them passing; they are the spec-as-code.
- Verify with `flutter analyze` + `flutter test` in each package/app you touch.

## Build notes (hard-won, don't rediscover)

- JDK: brew formula openjdk@21, wired via `flutter config --jdk-dir`. Android SDK: `~/Library/Android/sdk` (headless, no Android Studio); use the SDK's own `cmdline-tools/latest/bin/avdmanager` (the brew one points at the wrong root).
- Both apps force `compileSdk = 36` AND carry a root-gradle reflection override forcing plugin modules to 36 (the `alarm` plugin pins 34 but its `flutter_fgbg` dep needs 35+).
- Nivaat Android needs core-library desugaring (flutter_local_notifications).
- Nivaat iOS: deployment target 15.0 (workmanager); the Swift import is `workmanager_apple` (federated module name), plugin class `WorkmanagerPlugin`.
- AlarmKit: `flutter_alarmkit` takes Flutter asset paths for sounds (WAV < 30s); timestamps are Unix **milliseconds** as double; it assigns its own UUIDs → `AlarmKitScheduler` persists an int-id→UUID map. `NSAlarmKitUsageDescription` required in Info.plist.
- Emulator smoke loop: boot `emulator -avd pixel -no-window`, `adb exec-out screencap -p`. iOS: `xcrun simctl` install/launch/screenshot; seed SharedPreferences by writing the app container's plist while the sim is shut down (simctl spawn defaults writes outside the sandbox — doesn't work).

## Workflow

- Samyak prefers: TLDR-first answers, simple language with examples, data-verified claims, small focused iterations during implementation.
- Commit checkpoints; he reviews diffs. Don't push anywhere without being asked.

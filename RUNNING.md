# Running the apps locally (emulator / simulator)

How to run **Arunoday** and **Nivaat** on the Android emulator and the iOS simulator on this Mac — no real device needed for the first testing pass.

## Verified setup (checked 2026-07-19)

`flutter doctor -v` reports **no issues**. Everything below is already installed:

| Tool                   | Version on this Mac              | Requirement                       | Status     |
| ---------------------- | -------------------------------- | --------------------------------- | ---------- |
| Flutter (stable)       | 3.44.6                           | Latest stable line (3.44.x)       | ✅ current |
| Xcode                  | 26.6                             | iOS 26 SDK (apps target iOS 26.0) | ✅         |
| iOS Simulator runtime  | iOS 26.5 (iPhone 17 family)      | ≥ 26.0                            | ✅         |
| Android SDK / platform | 36 (Android 16)                  | ≥ 33 (apps' minSdk)               | ✅         |
| Android emulator (AVD) | `pixel` — Pixel 9, API 36, arm64 | any ≥ 33                          | ✅         |
| CocoaPods              | 1.17.0                           | —                                 | ✅         |
| JDK                    | OpenJDK 21 (Homebrew)            | 17+                               | ✅         |

Note: Android Studio is **not** installed — the SDK lives standalone with command-line tools. That's fully supported (doctor is green) and nothing is missing for running the apps; Studio would only add a GUI for managing AVDs and native-Android debugging.

## Run on Android (emulator)

```sh
# 1. Boot the emulator, wait until the Android home screen shows
flutter emulators --launch pixel

# 2. Run an app (one terminal per app)
cd apps/arunoday   # or apps/nivaat
flutter run -d emulator
```

## Run on iOS (simulator)

```sh
# 1. Boot a simulator and bring the Simulator app forward
xcrun simctl boot "iPhone 17" && open -a Simulator

# 2. Run an app (one terminal per app)
cd apps/arunoday   # or apps/nivaat
flutter run -d iPhone
```

First iOS build is slow (CocoaPods + native compile) — a few minutes is normal.

## First-run prompts & nudge banners (what asks what, and why)

| Prompt / banner | Who shows it | Why it exists |
| --- | --- | --- |
| **Notification permission** (system dialog) | Both apps on Android; **Nivaat only on iOS** | Android: the ring's card + full-screen UI ride on it — denied means bare sound with no visible way to stop the alarm outside the app. Nivaat additionally needs it for its skip notifications ("why didn't it ring"), Arunoday for bedtime reminders. On iOS rings are AlarmKit's own full-screen alerts, so only Nivaat asks (skip notifications); Arunoday posts no iOS notifications and asks nothing there (2026-07-20). |
| **"Allow Nivaat to always run in background?"** (battery-optimisation exemption, asked once at first launch) | **Nivaat, Android only** | The pre-alarm wind-check ladder runs as background wakeups with network; off-charger Doze throttles both (~1 wakeup per 9 min, network suspended), so checks would land late or not at all. **Arunoday deliberately never asks**: it does no background network work — its alarms are exact AlarmManager alarms that fire through Doze anyway. |
| **AlarmKit permission** (system prompt at first schedule) | Both apps, iOS only | iOS 26's real system alarms; there is no fallback, so denied = nothing rings. |
| Persistent **nudge banners** on the home screens | Both apps | Denying any of the above is never silently absorbed (2026-07-19): "Notifications are off" (both apps; Arunoday Android-only), "battery optimisation / Background App Refresh" (Nivaat; the Android one re-opens the system dialog — that one, unlike runtime permissions, may be re-asked forever), and "Alarms are turned off" (AlarmKit denied, iOS). Each re-checks on app resume, so fixing it in Settings hides the banner on return. **Armed-home only (2026-07-22):** banners stay hidden on the empty intro (Nivaat until ≥1 alarm; Arunoday until a location is set). |

Deny-testing tip: Android lets an app re-show the notification dialog only once more after the first "Don't allow"; after the second deny only the Settings path works — which is exactly what the banner deep-links to.

## While it's running

- `r` hot reload · `R` hot restart · `q` quit
- Logs (including the `debugPrint` nets like `nivaat CheckScheduler...`) stream in the same terminal; or attach from anywhere with `flutter logs`.
- Both apps can run side by side on the same device — just use two terminals.
- **Portrait-only (2026-07-22):** both apps lock to portrait on Android and iOS (native + Flutter). Rotating the emulator/sim won't landscape the UI — that's intentional, not a bug.

## What simulators can and can't test

**Android emulator — near-full parity.** Exact alarms ring, notifications show, the battery-optimization prompt appears, background WorkManager wind checks run, and the wind fetch uses your Mac's real network. Test everything here.

**iOS simulator — UI and flows only; two hard limits:**

1. **Background tasks never fire.** Apple doesn't support `BGTaskScheduler` on the simulator ([docs](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/error/code/unavailable), [workmanager #397](https://github.com/fluttercommunity/flutter_workmanager/issues/397)). So Nivaat's closed-app wind-check cascade won't run; checks still evaluate whenever the app is open or foregrounded. Example: schedule a 6:00 alarm, close the app → no T-1h…T-0 checks happen; reopen the app at 5:58 → it catches up immediately.
2. **AlarmKit is flaky on the simulator** — alarms schedule and present, but sound playback and the Dynamic Island are unreliable ([known issue](https://medium.com/@wenzeljeremy/alertsounds-with-ios-simulators-88ee41871c44)). A silent alarm on the simulator is _not_ evidence of a bug.

Bottom line: the simulator pass validates UI, permissions, scheduling logic, and foreground behavior. **Actual ring delivery (especially iOS background + sound) still needs one real-device pass before trusting it.**

## Troubleshooting

```sh
flutter devices                                  # emulator/simulator must be fully booted to appear
flutter clean && flutter pub get                 # per app, on weird build errors
cd ios && pod install --repo-update && cd ..     # per app, on CocoaPods errors
xcrun simctl erase "iPhone 17"                   # factory-reset a simulator (it must be shut down)
```

Release-mode note: `flutter run --release` works on the Android emulator; the iOS **simulator supports debug only** — release/profile need a real iPhone (profile mode is device-only on Android too).

### Android release signing (GitHub sideload)

Both apps share one permanent keystore under `android-signing/` (gitignored). Passwords live in each app’s `android/key.properties` and in `android-signing/BACKUP_THIS.txt`. **Back that folder up off this Mac** — lose it and users cannot update; they must uninstall. Without those files, release builds fall back to the debug key (fine for local runs; never ship that). Rebuild:

```sh
cd apps/arunoday   # or apps/nivaat
flutter build apk --release --split-per-abi --target-platform android-arm64
# → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Install that release APK on a phone or emulator (this is **not** `flutter run` — it's the real minified build):

```sh
adb devices
# first column = serial; use -s when more than one device is connected

adb -s <serial> install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Add `-r` to replace an existing install (same signing key). Copied APKs for GitHub uploads live in `./dist/` (gitignored).

**Nivaat release R8:** Flutter turns on minify/shrink for release APKs. Nivaat’s `android_alarm_manager_plus` path needs `apps/nivaat/android/app/proguard-rules.pro` (keeps that plugin + `JobIntentService` + workmanager + **`androidx.work`/Room** for WorkManager’s DB). Without it, release APKs die on install/launch while `flutter run` (debug, no minify) looks fine — either R8 merging `FlutterBackgroundExecutor`, or stripping `WorkDatabase_Impl` at AndroidX Startup before Flutter runs. **`AndroidAlarmManager.initialize()` must run after the first frame** (see `main.dart` `_finishStartup`); that same helper also runs `checks.initialize()` on **iOS** (seeds periodic BGAppRefresh — don’t skip it when changing Android deferral). After changing those rules, always `flutter build apk --release` and confirm the mapping still lists `FlutterBackgroundExecutor -> FlutterBackgroundExecutor` and `WorkDatabase_Impl`.

**After switching the app icon in Settings (Android):** `flutter run` can fail with `Error: Activity class …MainActivity does not exist` — picking icon 2/3 disables MainActivity as the launcher entry (that's how alternate icons work), and the tool always cold-starts that exact component. Fix either way:

```sh
adb shell pm enable com.samyak.arunoday/com.samyak.arunoday.MainActivity   # or …nivaat…
```

or switch back to the first icon in the app's Settings. Expected cosmetics, not bugs: iOS shows a system alert on every icon change; Android launchers may blink or move the home-screen shortcut.

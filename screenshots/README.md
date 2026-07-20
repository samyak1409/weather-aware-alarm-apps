# Screenshots

Exactly three shots per app × platform. Refreshed **only when Samyak
explicitly asks** ("update screenshots") — never automatically after a UI
change (rule in CLAUDE.md).

## Set (2026-07-20)

| # | File | Screen |
|---|------|--------|
| 01 | `01_empty_state.png` | First-run empty home |
| 02 | `02_home.png` | Populated home (Arunoday: Bengaluru · Nivaat: Society Court) |
| 03 | `03_settings.png` | Settings |

Paths: `screenshots/<arunoday\|nivaat>/<android\|ios>/`.

Android = Pixel emulator (`pixel` AVD, 1080×2424) · iOS = iPhone 17 simulator (iOS 26.5)

Capture **one OS at a time** — never leave the emulator and Simulator both open.
If a system dialog blocks a shot, ask Samyak to tap instead of fighting automation.

## Refresh harness (optional)

Both apps accept `--dart-define=SCREENSHOT_HARNESS=true` (`kScreenshotHarness`
in core), which:

1. Uses `NoOpAlarmScheduler` (no AlarmKit / alarm-package prompts).
2. Skips startup notification / battery dialogs **and** hides permission
   nudge banners on the home screens.
3. Reads `screenshot.target` from SharedPreferences after load — only
   `settings` opens a sheet (the other two shots are home surfaces).

Seed prefs, then launch. **Both platforms store Flutter prefs under the
`flutter.` key prefix.** iOS: write the container plist while the simulator
is shut down.

For Nivaat screenshots: leave `nivaat.notifPermissionAsked` **false** (harness
skips the prompt — marking it asked without a grant would make the home
nudge appear in a *non*-harness build). On Android, `adb shell pm grant …
POST_NOTIFICATIONS` and/or `dumpsys deviceidle whitelist +<pkg>` keep a
non-harness capture clean if you ever shoot without the define.

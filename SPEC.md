# Alarm Apps — Locked v1 Specification

Two minimal, pitch-black (OLED #000000) alarm apps, one Flutter monorepo, shared core package.
All decisions below were locked with Samyak on 2026-07-11 after research and real-data validation.

**Priority: Arunoday is the daily-driver lifetime app. Nivaat is the occasional-use niche tool. Build/polish order follows that.**

---

## Common (both apps)

| Decision | Value |
|---|---|
| Framework | Flutter, monorepo, shared `core` package |
| Targets | Android 13+ (minSdk 33), iOS — latest; AlarmKit (iOS 26) planned for v1.1 |
| UI | Pure black `#000000`, minimal, dark-only. Arunoday accent: dawn orange. Nivaat accent: wind teal |
| Alarm engine v1 | `alarm` pub package behind a `core` interface; swap to `flutter_alarmkit` on iOS in v1.1 |
| Locations | Saved named locations in settings (Open-Meteo geocoding search, free, no key). No GPS/background location |
| Distribution | GitHub releases. Android: APK. iOS: sideload (free Apple ID = 7-day signing during dev; SideStore later) |
| Units | Metric, km/h. English UI. Weekday selector on alarms. Snooze 5 min |

## Arunoday — dawn alarm (सूर्योदय के पहले की रोशनी)

- **Wake anchor: civil dawn** (sun 6° below horizon), computed **on-device** with NOAA solar math. No API, works offline forever.
- **Offset**: user-configurable ± hours+minutes on top of dawn (e.g. dawn +2h for lazy phases). Applied to wake alarm.
- **Locations**: multiple saved, exactly **one active**; switching recalculates everything (dawn differs across India: Tonk vs BLR ≈ 21 min today; Guwahati vs Dwarka ≈ 1h40m).
- **Fixed bedtime (auto, editable)**: `bedtime = midpoint(earliest yearly wake, latest yearly wake) − 8h`, then clamped so nightly sleep stays within **[7h, 9h]** all year. Wake = dawn + offset. Yearly extremes are **scanned across all 365 days** (earliest ≈ early Jun, latest ≈ mid-Jan — equation of time; never assume solstices).
- **Bedtime is a full ringing alarm** (user decision), auto-computed, editable.
- Scheduling: rolling window — next 7 days of wake + bedtime alarms scheduled on every app open/change. (v1 limitation: open the app ~weekly; background top-up in v1.1.)
- Reference numbers (validation): Jaipur 2026 sunrise 05:32 (10 Jun) → 07:17 (12 Jan), swing 105 min. Tonk civil dawn 05:08→06:51. BLR civil dawn 05:29→06:24 (swing only 55 min). Midpoint−8h for Tonk wake≈dawn: bedtime ≈ 22:25, sleep 7.1–8.9h, avg ≈ 8.0h.

## Nivaat — wind-conditional badminton alarm (निवात: Gita 6.19, the lamp in a windless place)

- Alarms at **any time of day** (morning or evening play). Each alarm picks a **court** from saved courts.
- **Wind data**: Open-Meteo (free, no key). Hourly forecast for alarm hour when far out; current wind when ≤15 min away.
- **Threshold**: dropdown **1–6 km/h, default 4** — semantic = **court-level wind**. The API reports 10 m wind; app converts: `court_wind = api_wind × 0.6` (log wind profile). Validated against real data: raw thresholds would never ring in BLR (July 6am median 16.4 km/h raw).
- **Gust rule (auto, uneditable)**: `raw_gust_limit = max(2.2 × raw_speed_limit, 12 km/h)`. Derived from 81 real calm-morning samples (gusts cluster 11–14 km/h when speed passes). Ring only if BOTH speed and gust pass.
- **Check cascade**: at T−12h, −6h, −3h, −2h, −1h, −30m, −15m, −8m, −4m, −2m, −1m, T−0. Far checks use forecast for alarm hour; T−0 uses current wind. Latest successful check wins. If none succeeded by T: retry every 1 min, **cap 30 min after alarm**, then give up.
- **Fail-safe (user decision)**: windy → no ring; API/network fail → no ring. Always leave a **silent skip card** (notification + in-app history): "Skipped: wind 9 km/h at 6:00" — trust through honesty, never silent failure.
- **Wind-proportional volume**: linear ramp, **100% at 0 wind → 50% floor at threshold**; above threshold → skip. Android: volume computed at ring time. iOS: pre-rendered loudness variants chosen at scheduling (AlarmKit can't set volume) — v1 uses `alarm` package volume param.
- iOS reliability: evening decision + BG-refresh ladder (grants are opportunistic); **Bedside mode** (foreground OLED clock, true ring-time check) is the reliable option — v1.1.
- Expected ring rates (validated simulation, threshold 4→6): Tonk Jan 71→90%, Tonk Jul 25→56%, BLR Jan 23→47%, BLR Jul ~0–6% (monsoon: correctly windy).

## v1.1 roadmap (not v1)

flutter_alarmkit on iOS 26 · Nivaat bedside mode · per-court shelter calibration · background schedule top-up · "how often will this ring?" seasonal preview (Open-Meteo archive) · Hindi UI

## Explicitly rejected

Server/push architecture (needs paid Apple account + infra) · GPS auto-location · editable gust threshold · fail-loud on API error (user chose fail-silent + card) · light theme

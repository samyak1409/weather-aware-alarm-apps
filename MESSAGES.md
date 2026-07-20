# Messages & notifications — Arunoday & Nivaat

**Purpose:** every user-facing string across both apps in one place — ring alarms, notifications, in-app history, screen text, dialogs, errors. So any message can be reviewed and changed by pointing at its ID (e.g. _"change N3 no-data body to …"_).

**How to read:** each entry gives the **template** (with `{braces}` for dynamic parts) then a concrete **example** after `→`. Static strings are shown literally (they are their own example). Notifications list **Title** / **Body** / **Button**; history lists the **line** (primary) and **sub** (secondary).

Worked examples below use: Nivaat court **"Society Court"**, limit **4** (gust cap **≤15**), alarm **06:00**; Arunoday location **"Jaipur"**, dawn **06:51**, wake offset **+0:20** (⇒ wake **07:11**), bedtime **21:56**.

## Shared formatting helpers

- `HH:MM` (`fmtClock`) → 24h, zero-padded: `06:00`, `21:56`.
- `date` (`fmtShortDate`) → `18 Jul`.
- `checktime` (`fmtCheckTime`) → time only same-day (`05:59`); dated across midnight (`17 Jul 22:00`).
- `windgust` (`fmtWindGust`) → `wind 3 (≤4) · gusts 12 (≤15) km/h`.
- `±offset` (`fmtOffset`) → `+0:20`, `−0:30`.

---

# ARUNODAY

## Notifications

### A1 — Wake ring (system alarm)

- **Title:** `Arunoday · dawn`
- **Body:** offset 0 → `First light at {loc}. Good morning.` → `First light at Jaipur. Good morning.`
  else → `Dawn {±offset} at {loc}. Good morning.` → `Dawn +0:20 at Jaipur. Good morning.`
- **Button:** `Stop`

### A2 — Bedtime ring

- **Title:** `Arunoday · bedtime`
- **Body:** `Wind down — dawn comes early.`

### A3 — Bedtime "AGAIN" re-ring (after +1h)

- **Title:** `Arunoday · bedtime`
- **Body:** `Second call — dawn does not snooze.`

## Ring screen (in-app overlay while an alarm sounds)

- **A4 — Stop button:** `STOP`
- **A5 — Bedtime ritual (bedtime alarms only):**
  - Wake line: `WAKE {TODAY|TOMORROW} {HH:MM}` → `WAKE TOMORROW 07:11`
  - `NOT SLEEPY` + button `+1h`

## Home screen

- **A6 — App label:** `ARUNODAY`
- **A7 — Wake line:** `WAKE · DAWN{±offset}{ · IN {Xh Ym} | · OFF}`
  → `WAKE · DAWN+0:20 · IN 7H 22M` · disabled → `WAKE · DAWN+0:20 · OFF`
- **A8 — Bedtime line:** `BEDTIME · {AUTO | AUTO{±offset}}{ · AGAIN {HH:MM}}{ · {Xh Ym} TONIGHT}{ · IN {Xh Ym} | · OFF}`
  → `BEDTIME · AUTO+0:30 · 8H 45M TONIGHT · IN 3H 05M` · with re-ring → `BEDTIME · AUTO · AGAIN 22:56 · 8H 15M TONIGHT · IN 0H 45M`
- **A9 — Footer:** `Dawn {today|tomorrow} {HH:MM}{ · Sunrise {HH:MM}}` + second line `{loc name}`
  → `Dawn today 06:51 · Sunrise 07:18` / `Jaipur`
- **A10 — Empty state:** title `Wake with the dawn.` · body `Add your location — the alarm follows its real dawn, every day of the year.` · button `Add location`
- **A11 — No-dawn (polar) screen:** `No daily dawn at {loc}.` → `No daily dawn at Tromsø.` · body `This is a polar location where the sun does not cross the dawn threshold every day. Pick another location in settings.`

## Settings sheet

- **A12 — Title:** `SETTINGS`
- **A13 — Rows** (grouped by ritual, 2026-07-20): `Wake alarm` · `Wake offset from dawn` · `Bedtime alarm` · `Bedtime` · `Bedtime again` (subtitle `Not sleepy — tonight only`) · `Alarm sound` · section `APPEARANCE` (X6) · section `LOCATIONS`
- **A14 — Hints:** `Long-press wake offset to reset to dawn.` · `Long-press bedtime to return to auto.`
- **A15 — Yearly sleep readout:** `Year here: sleep {Xh Ym} (summer) to {Xh Ym} (winter) — the natural swing of dawn at this latitude.`
  → `Year here: sleep 7h 33m (summer) to 8h 27m (winter) — the natural swing of dawn at this latitude.`
- **A16 — Bedtime picker:** helpText `BEDTIME` · title `BEDTIME` · hint `{auto is {HH:MM} | manual} · tap the time to pick exactly` → `auto is 21:56 · tap the time to pick exactly` · buttons `Cancel`, `Save`
- **A17 — Wake-offset picker:** helpText `WAKE TIME` · title `WAKE OFFSET` · hint `{relative to civil dawn | dawn {HH:MM} · wake {HH:MM}}` + `tap the offset to pick the wake time` → `dawn 06:51 · wake 07:11` + `tap the offset to pick the wake time` · buttons `Cancel`, `Save`
- **A18 — Validation snacks:** `Bedtime can't be the same as the wake alarm.` · `Wake time can't be the same as the bedtime.` · `No daily dawn at {l} (polar region) — Arunoday needs a real dawn.` → `No daily dawn at Tromsø (polar region) — Arunoday needs a real dawn.`
  _(Bedtime **is** now allowed to land on a pending re-ring's minute — the re-ring wins that slot so only one alarm sounds, and if the re-ring is cancelled the daily bedtime takes it back.)_

---

# NIVAAT

## Notifications

_In every Nivaat title below, `{HH:MM}` is the **alarm time you set** (e.g. `06:00`) — never the ring time or the wind-check time. (Verified in code: all three titles use the occurrence's scheduled time.)_

### N1 — Ring (the alarm itself; AlarmKit on iOS, `alarm` package on Android)

- **Title:** `Nivaat {HH:MM} · {court}` → `Nivaat 06:00 · Society Court`
- **Body:** `{windgust} — play! 🏸` → `wind 3 (≤4) · gusts 12 (≤15) km/h — play! 🏸`
- **Button:** `Stop`

### N2 — Heads-up ("still checking"), posted at T while the retry window runs

- **Title:** `Nivaat {HH:MM} · still checking` → `Nivaat 06:00 · still checking`
- **Body — windy:** `{court} too windy · {windgust} · checked {checktime} · keeping watch until {HH:MM}, will ring if it calms 🏸`
  → `Society Court too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:00 · keeping watch until 06:30, will ring if it calms 🏸`
- **Body — gusty:** `{court} too gusty · {windgust} · checked {checktime} · keeping watch until {HH:MM}, will ring if it calms 🏸`
  → `Society Court too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:00 · keeping watch until 06:30, will ring if it calms 🏸`
- **Body — no-data:** `Couldn't reach the wind at {court} · last tried {checktime} · keeping watch until {HH:MM}, will ring once it's reachable 🏸`
  → `Couldn't reach the wind at Society Court · last tried 06:00 · keeping watch until 06:30, will ring once it's reachable 🏸`

### N3 — Skip card (final), at the +30m cap or on a late first-open

- **Title:** `Nivaat {HH:MM} · skipped` → `Nivaat 06:00 · skipped`
- **Body — windy:** `{court} too windy · {windgust} · checked {checktime} — next time 🏸`
  → `Society Court too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:29 — next time 🏸`
- **Body — gusty:** `{court} too gusty · {windgust} · checked {checktime} — next time 🏸`
  → `Society Court too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:29 — next time 🏸`
- **Body — no-data:** `Couldn't reach the wind at {court} · last tried {checktime}` _(no sign-off)_
  → `Couldn't reach the wind at Society Court · last tried 06:29`

### N4 — Skip notification channel (Android)

- **Name:** `Skipped alarms` · **Description:** `Why an alarm did not ring`

## History

Shown in two places: the **history sheet** (a scrollable list of past outcomes; opened from settings, or by tapping the home "last outcome" line) and the home screen's single **"last outcome"** line. Each entry has a **line** — the primary text (outcome + numbers) — and a **sub** — the smaller secondary line beneath it (court + when + freshness). Both lead with the **court name**.

History is an **append-only log mirroring the notifications** (2026-07-20): an occurrence that misses its T leaves the heads-up **snapshot row** right then (what N2 said, marked with N17's watch note), and its **final outcome** — the cap's skip, or a late ring — is a **separate second row**. Both stay forever; nothing is overwritten.

| Outcome        | Line (template → example)                                                              | Sheet sub (example)                                 |
| -------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **N5** rang    | `Rang (at {vol}%) · {windgust}` → `Rang (at 88%) · wind 3 (≤4) · gusts 12 (≤15) km/h`  | `Society Court · 18 Jul · 06:00 · checked 06:00`    |
| **N6** windy   | `Skipped (windy) · {windgust}` → `Skipped (windy) · wind 6 (≤4) · gusts 18 (≤15) km/h` | `Society Court · 18 Jul · 06:00 · checked 06:29`    |
| **N7** gusty   | `Skipped (gusty) · {windgust}` → `Skipped (gusty) · wind 3 (≤4) · gusts 16 (≤15) km/h` | `Society Court · 18 Jul · 06:00 · checked 06:29`    |
| **N8** no-data | `Skipped (no data)`                                                                    | `Society Court · 18 Jul · 06:00 · last tried 06:29` |

- Sheet **sub** = `{court} · {date} · {HH:MM} · {checked|last tried} {checktime}{ · watch note}`.
- Home **last outcome** = `{court} · {date} {HH:MM} · {checked|last tried} {checktime} — {line}{ · watch note}` → `Society Court · 18 Jul 06:00 · checked 06:00 — Rang (at 88%) · wind 3 (≤4) · gusts 12 (≤15) km/h`.
- `HH:MM` is the **alarm time**; "checked" = last successful reading, "last tried" = last attempt for a no-data skip.

### N17 — Watch note (heads-up snapshot rows only)

- While the +30m retry window runs: ` · watching until {HH:MM}` → ` · watching until 06:30`
- Forever after: ` · watched until {HH:MM}` → ` · watched until 06:30`
- Appended to the sheet sub and the home last-outcome line; marks the row as the at-T snapshot whose final outcome is its own later row (N5–N8). Final rows never carry it.

## Home screen

- **N9 — App label:** `NIVAAT`
- **N10 — Background note (footer):** `Keep the phone charged and online before your alarm — the background wind check needs both.`
- **N11 — Empty state:** title `The windless alarm.` · body `Rings only when the wind at your court is low enough to play. The calmer the morning, the louder it rings.`
- **N12 — Alarm list row (sub):** `{weekdays} · {court} · ≤{limit} km/h` → `Every day · Society Court · ≤4 km/h` — court deleted → `court removed`
- **N18 — Background-checks banner** (shown while the OS throttles background wind checks; hidden while the first-run exemption dialog is up):
  - **Android:** `Battery optimisation can delay or skip Nivaat's background wind checks — it could miss a wind change and ring on a windy morning, or stay silent on a calm one.` · button `Allow background use` (re-opens the system exemption dialog)
  - **iOS:** `Background App Refresh is off — Nivaat can only check the wind while the app is open.` · button `Open Settings`

## Sheets & dialogs

- **N13 — Alarm editor:** title `NEW ALARM` / `EDIT ALARM` · row `Court` · row `Max wind at court` · hint `Gust guard auto: ≤{n} km/h` → `Gust guard auto: ≤15 km/h` · buttons `Delete`, `Save`
- **N14 — Courts sheet:** header `COURTS` · hint `Save your courts — each alarm checks the wind at its own court.`
- **N15 — Delete-court dialog:** title `DELETE COURT` · body (variants):
  - `{n} alarm(s) use {court} and will be deleted too. Continue?` → `2 alarms use Society Court and will be deleted too. Continue?`
  - `… and will be deleted too, along with {m} history entry/entries. Continue?` → `2 alarms use Society Court and will be deleted too, along with 5 history entries. Continue?`
  - `{m} history entry/entries for {court} will be deleted too. Continue?` → `5 history entries for Society Court will be deleted too. Continue?`
  - buttons `Cancel`, `Delete`
- **N16 — Duplicate-court error:** `Same spot as {name} — already added.` → `Same spot as Society Court — already added.`
- **N19 — Settings page** (header `SETTINGS`; the home top bar keeps only its tune icon, 2026-07-20): tiles `Courts` (trailing: count) · `Alarm sound` (trailing: tone name, e.g. `Court Call`) · `History` (trailing: count) · then the shared `APPEARANCE` section (X6)

---

# SHARED (both apps)

### X1 — Permission banner (home screen; iOS, AlarmKit denied)

- **Text:** `Alarms are turned off — {AppName} can't ring until you allow alarms for it in Settings.` → `Alarms are turned off — Arunoday can't ring until you allow alarms for it in Settings.`
- **Button:** `Open Settings`

### X2 — Location picker (add a place)

- GPS button: `Use my current location` (loading: `Getting your location…`) · caption `Works offline`
- Search hint: `Or search a place…`
- Name dialog: title `NAME THIS PLACE` · default `My location` · buttons `Cancel`, `Save`
- Errors: `Search failed — check network` · `Turn on location services first` · `Location permission denied` · `Couldn't get your location — try search instead`

### X3 — Sound picker

- Header: `ALARM SOUND` · section (Android) `DEVICE ALARM SOUNDS`
- Default tone names: Nivaat `Court Call` · Arunoday `Dawn Bells`

### X4 — Notifications-off banner (home screen; only after the user has ANSWERED the permission prompt with a deny)

- **Nivaat, Android:** `Notifications are off — a ringing alarm shows nothing on screen (sound only, no Stop), and Nivaat can't tell you when it skips an alarm for wind, or why.`
- **Nivaat, iOS:** `Notifications are off — Nivaat can't tell you when it skips an alarm for wind, or why.`
- **Arunoday, Android only** (no iOS banner or permission request — it posts no iOS notifications): `Notifications are off — a ringing alarm shows nothing on screen (sound only, no Stop), and bedtime reminders can't appear.`
- **Button (all):** `Turn on notifications` (Android → the app's notification settings page; iOS → the app's Settings page)

### X5 — Maker's mark (home screen footer, both apps, always visible)

- **Text:** `CRAFTED WITH ♥ BY SAMYAK` — the `♥` is the Material `favorite` icon in the app's accent colour (a text glyph became the red emoji on Android); tapping `SAMYAK` opens samyak1409.github.io in the browser

### X6 — Appearance settings (Arunoday settings page · Nivaat settings page, header `SETTINGS`)

- **Section label:** `APPEARANCE`
- **Bold-type toggle:** title `Bold clocks & titles` · subtitle `Heavier type on the home screen` (ships OFF)
- **Icon picker:** title `App icon` · three thumbnails with labels — Arunoday `Horizon` (default) / `Rays` / `Dawn`; Nivaat `Shuttle` (default) / `Calm` / `Crest`. iOS confirms a switch with the system's own alert; Android launchers may take a moment to show the new icon

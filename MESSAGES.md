# Messages & notifications — Arunoday & Nivaat

**Purpose:** every user-facing string across both apps in one place — ring alarms, notifications, in-app history, screen text, dialogs, errors. So any message can be reviewed and changed by pointing at its ID (e.g. _"change N3 no-data body to …"_).

**How to read:** each entry gives the **template** (with `{braces}` for dynamic parts) then a concrete **example** after `→`. Static strings are shown literally (they are their own example). Notifications list **Title** / **Body** / **Button**; history lists the **line** (primary) and **sub** (secondary).

Worked examples below use: Nivaat court **"Society Court"**, limit **4** (gust cap **≤15**), alarm **06:00**; Arunoday location **"Jaipur"**, dawn **06:51**, wake offset **+0:20** (⇒ wake **07:11**), bedtime **21:56**.

## Shared formatting helpers

- `HH:MM` (`fmtClock`) → 24h, zero-padded: `06:00`, `21:56`.
- `date` (`fmtShortDate`) → `18 Jul`. **No year, accepted 2026-07-22** — Nivaat's history is append-only, so rows a year apart look identical; reviewed and left as-is.
- `checktime` (`fmtCheckTime`) → time only same-day (`05:59`); dated across midnight (`17 Jul 22:00`).
- `windgust` (`fmtWindGust`) → `wind 3 (≤4) · gusts 12 (≤15) km/h`.
- `±offset` (`fmtOffset`) → `+0:20`, `−0:30`. **Never spaced off the word it modifies** — `Dawn+0:20`, `DAWN+0:20`, `Auto+0:30` are each one value, not two (2026-07-22).

---

# ARUNODAY

## Notifications

### A1 — Wake ring (system alarm)

- **Title:** `Arunoday · Dawn`
- **Body:** offset 0 → `First light at {loc}. Good morning.` → `First light at Jaipur. Good morning.`
  else → `Dawn{±offset} at {loc}. Good morning.` → `Dawn+0:20 at Jaipur. Good morning.`
- **Button:** `Stop`

### A2 — Bedtime ring

- **Title:** `Arunoday · Bedtime`
- **Body:** `Wind down — dawn comes early.`

### A3 — Bedtime "AGAIN" re-ring (after +1h)

- **Title:** `Arunoday · Bedtime`
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

## Settings sheet

- **A12 — Title:** `SETTINGS`
- **A13 — Rows** (grouped by ritual, 2026-07-20): `Wake alarm` · `Wake offset from dawn` · `Bedtime alarm` · `Bedtime` · `Bedtime again` (subtitle `Not sleepy — tonight only`) · `Alarm sound` · section `APPEARANCE` (X6) · section `LOCATIONS`
- **A14 — Hints:** `Long-press wake offset to reset to dawn.` · `Long-press bedtime to return to auto.`
- **A15 — Yearly sleep readout:** `Year here: sleep {Xh Ym} (summer) to {Xh Ym} (winter) — the natural swing of dawn at this latitude.`
  → `Year here: sleep 7h 33m (summer) to 8h 27m (winter) — the natural swing of dawn at this latitude.`
- **A16 — Bedtime picker:** helpText `BEDTIME` · title `BEDTIME` · hint `{auto is {HH:MM} | manual} · tap the time to pick exactly` → `auto is 21:56 · tap the time to pick exactly` · buttons `Cancel`, `Save`
- **A17 — Wake-offset picker:** helpText `WAKE TIME` · title `WAKE OFFSET` · hint `{relative to civil dawn | dawn {HH:MM} · wake {HH:MM}}` + `tap the offset to pick the wake time` → `dawn 06:51 · wake 07:11` + `tap the offset to pick the wake time` · buttons `Cancel`, `Save`
- **A18 — Validation:** wake↔bedtime collisions show live inside the wake-offset / bedtime dialogs (`Bedtime can't be the same as the wake alarm.` / `Wake time can't be the same as the bedtime.`) with Save disabled. Polar refuse is picker-only at add: `No daily dawn here (polar) — Arunoday needs a real dawn.` → same wording for Tromsø etc.
  _(Bedtime **is** allowed to land on a pending re-ring's minute — the re-ring wins that slot so only one alarm sounds, and if the re-ring is cancelled the daily bedtime takes it back.)_

---

# NIVAAT

## Notifications

_All three titles share one shape — `{court} · {HH:MM} · {status}` (`nivaatNotificationTitle`), status being `Play! 🏸` / `Still checking` / `Skipped`. **The app name is deliberately absent** (2026-07-22): both OS notification headers already print "Nivaat" above the title, so repeating it there spent the scannable head of the line on a duplicate. The court leads instead — it's what tells two alarms apart — and for the same reason the bodies below no longer name it. Statuses are **sentence-capitalised**: they head a title, not a mid-sentence clause. `{HH:MM}` is the **alarm time you set** (e.g. `06:00`) — never the ring time or the wind-check time._

_Every body is now **just the evidence** (2026-07-22): the verdict lives in the title, so the trailing promises (`will ring if it calms`, `will ring once it's reachable`) and the sign-off (`— next time`) are gone, and with them the 🏸 — which survives only as part of the ring's status, the one moment that earns it._

### N1 — Ring (the alarm itself; AlarmKit on iOS, `alarm` package on Android)

- **Title:** `{court} · {HH:MM} · Play! 🏸` → `Society Court · 06:00 · Play! 🏸`
- **Body:** `{windgust} · checked {checktime}` → `wind 3 (≤4) · gusts 12 (≤15) km/h · checked 06:00`
- **Button:** `Stop`
- The ring carries its freshness too (2026-07-22) — a ring booked from last night's forecast says `· checked 17 Jul 22:00`, so a 6am reading is never confused with a 12-hour-old one. Same instant its N5 history row shows.

### N2 — Heads-up ("still checking"), posted at T while the retry window runs

- **Title:** `{court} · {HH:MM} · Still checking` → `Society Court · 06:00 · Still checking`
- **Body — windy:** `Too windy · {windgust} · checked {checktime} · watching until {checktime}`
  → `Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:00 · watching until 06:30`
- **Body — gusty:** `Too gusty · {windgust} · checked {checktime} · watching until {checktime}`
  → `Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:00 · watching until 06:30`
- **Body — no-data:** `Couldn't reach the wind · last tried {checktime} · watching until {checktime}`
  → `Couldn't reach the wind · last tried 06:00 · watching until 06:30`
- The body is N3's plus ` · watching until {checktime}` — and that deadline phrase is word-for-word N17's history watch note (same `fmtCheckTime` vs the alarm, so a late-night cap crossing midnight dates itself).
- **Left standing after the outcome — locked 2026-07-22, don't "fix" it.** Nothing cancels or rewrites this card, so after a late ring at 06:07 it still reads `Still checking … watching until 06:30`. Accepted: its counterpart arrives as its own card (N3) or as the ring itself (N1), and history keeps both moments as separate rows. Note the asymmetry is real — N17 ages `watching` → `watched` once the deadline passes; the notification cannot.

### N3 — Skip card (final), at the +30m cap or on a late first-open

- **Title:** `{court} · {HH:MM} · Skipped` → `Society Court · 06:00 · Skipped`
- **Body — windy:** `Too windy · {windgust} · checked {checktime}`
  → `Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · checked 06:29`
- **Body — gusty:** `Too gusty · {windgust} · checked {checktime}`
  → `Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · checked 06:29`
- **Body — no-data:** `Couldn't reach the wind · last tried {checktime}` _(no numbers — there were none)_
  → `Couldn't reach the wind · last tried 06:29`

### N4 — Notification channel (Android)

- **Name:** `Alarm updates` · **Description:** `Still checking, and why an alarm didn't ring` · **id:** `nivaat_alarm_updates`
- Carries **both** N2 and N3, so it can't be named for only one: the old `Skipped alarms` meant muting the skip explanations also killed the still-checking heads-up — the card that's still worth acting on (renamed 2026-07-22).

## History

Shown in the **history sheet** (a scrollable list of past outcomes; opened from settings, or by tapping the home "still checking" cue while a retry window is open). Each entry has a **line** — the primary text (outcome + numbers) — and a **sub** — the smaller secondary line beneath it (court + when + freshness). Both lead with the **court name**.

History is an **append-only log mirroring the notifications** (2026-07-20): an occurrence that misses its T leaves the heads-up **snapshot row** right then (what N2 said, marked with N17's watch note), and its **final outcome** — the cap's skip, or a late ring — is a **separate second row**. Both stay forever; nothing is overwritten.

| Outcome        | Line (template → example)                                                              | Sheet sub (example)                                 |
| -------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------- |
| **N5** rang    | `Rang (vol. {vol}%) · {windgust}` → `Rang (vol. 88%) · wind 3 (≤4) · gusts 12 (≤15) km/h`  | `Society Court · 18 Jul · 06:00 · checked 06:00`    |
| **N6** windy   | `Skipped · {windgust}` → `Skipped · wind 6 (≤4) · gusts 18 (≤15) km/h` | `Society Court · 18 Jul · 06:00 · checked 06:29`    |
| **N7** gusty   | `Skipped (gusty) · {windgust}` → `Skipped (gusty) · wind 3 (≤4) · gusts 16 (≤15) km/h` | `Society Court · 18 Jul · 06:00 · checked 06:29`    |
| **N8** no-data | `Skipped (no data)`                                                                    | `Society Court · 18 Jul · 06:00 · last tried 06:29` |

- Sheet **sub** = `{court} · {date} · {HH:MM} · {checked|last tried} {checktime}{ · watch note}`.
- `{vol}` is the ring's **volume** (the wind ramp — calmer morning, louder ring, per N11), not a score. Written `vol. 88%` so it can't be read as one (2026-07-22).
- **N6's bare `Skipped` means windy — locked 2026-07-22, don't add `(windy)`.** Windy is the default skip, so only the exceptions carry a label (`(gusty)`, `(no data)`). Accepted consequence: the sheet's wording differs from the card's, which says `Too windy` for the same event.
- A row whose court is gone is **pruned on load**, so `{court}` always resolves. The `court removed` fallback (same wording as N12) is defence only — deleting a court already sweeps its log; the gap was a background check landing a row just after that sweep.
- `HH:MM` is the **alarm time**; "checked" = last successful reading, "last tried" = last attempt for a no-data skip. One helper (`nivaatCheckedNote`) writes this phrase for **all** of N1/N2/N3, so a card and its history row can't drift.

### N17 — Watch note (heads-up snapshot rows only)

- While the +30m retry window runs: ` · watching until {checktime}` → ` · watching until 06:30` (same-day) / ` · watching until 23 Jul 00:19` (cap crosses midnight vs the alarm)
- Forever after: ` · watched until {checktime}` → ` · watched until 06:30`
- Appended to the sheet sub; marks the row as the at-T snapshot whose final outcome is its own later row (N5–N8). Final rows never carry it.

### N21 — Home watching cue (only while a +30m window is open)

- Text: `Still checking wind · until {checktime}` → `Still checking wind · until 06:30`
- Leading wind-accent filled bullet in the text (`● Still checking wind · until 06:30`) — "live + tappable", not a word prefix.
- With several open windows, quotes the **soonest** cap (same pick the home dismiss timer uses).
- **Clears when checking actually stops (2026-07-23)** — unlike N2 (a posted notification can't rewrite itself): a final row for the same `alarmId + at` (late ring / cap skip), the alarm gone/disabled, **or** live `CheckState` no longer targeting that occurrence (toggle-off discards it; toggle-on re-arms tomorrow — cue must not reappear for today's dead retries). Hidden the rest of the time (no permanent "last outcome" dump on home — 2026-07-22). Tap opens the history sheet.

## Home screen

- **N9 — App label:** `NIVAAT`
- **N21 — Watching cue** (only while a +30m retry window is open): see History § N21 above.
- **N10 — Background note (footer, only when ≥1 alarm):** `Keep the phone charged and online before your alarm — the background wind check needs both.` Soft-wraps (no hard newlines — large accessibility text must reflow cleanly). Hidden on the empty intro. Rendered at 50% of secondary text opacity (2026-07-22) so it stays a quiet caveat.
- **N11 — Empty state:** title `The windless alarm.` · body `Rings only when the wind at your court is low enough to play. The calmer the morning, the louder it rings.`
- **N12 — Alarm list row (sub):** `{weekdays} · {court} · ≤{limit} km/h` → `Every day · Society Court · ≤4 km/h` — court deleted → `court removed`
- **N18 — Background-checks banner** (shown while the OS throttles background wind checks; hidden while the first-run exemption dialog is up):
  - **Android:** `Battery optimisation can delay or skip Nivaat's background wind checks — it could miss a wind change and ring on a windy morning, or stay silent on a calm one.` · button `Allow background use` (re-opens the system exemption dialog)
  - **iOS:** `Background App Refresh is off — Nivaat can only check the wind while the app is open.` · button `Open Settings`

## Sheets & dialogs

- **N13 — Alarm editor:** title `NEW ALARM` / `EDIT ALARM` · row `Court` · row `Max wind at court` · hint `Gust guard auto: ≤{n} km/h` → `Gust guard auto: ≤15 km/h` · buttons `Delete`, `Save`
- **N20 — Duplicate-time error (alarm editor, inline above Save):** `Another alarm is already at {HH:MM}.` → `Another alarm is already at 06:00.` — any other alarm with the same HH:MM (court / weekdays ignored). Shown live on open and after picking a time; Save stays disabled while it shows (not a SnackBar — those land on the hidden home Scaffold).
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

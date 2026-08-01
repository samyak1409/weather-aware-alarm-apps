# Messages & notifications — Arunoday & Nivaat

**Purpose:** every user-facing string across both apps in one place — ring alarms, notifications, in-app history, screen text, dialogs, errors. So any message can be reviewed and changed by pointing at its ID (e.g. _"change N2's no-data body to …"_).

**How to read:** each entry gives the **template** (with `{braces}` for dynamic parts) then a concrete **example** after `→`. Static strings are shown literally (they are their own example). Notifications list **Title** / **Body** / **Button** (an entry with no button simply omits the line); history lists the **line** (primary) and **sub** (secondary).

**Three conventions, all learned the hard way:**

- **IDs follow document order, and are renumbered wholesale when the document is restructured** (last done 2026-07-26). The alternative — permanent numbers with retired gaps — was tried and dropped: it left `A11` and `N3` as holes, the ring screen stranded on Arunoday numbers after Nivaat inherited it, and Nivaat's home section running `N9, N21, N10, N11, N12, N18`. _(Those five are **old-scheme** numbers, quoted as history — resolving them against the table below gives the wrong entries, which is exactly the hazard being described.)_ Order beats history for a file whose whole job is lookup. The cost is that a renumber invalidates every citation at once, so **it must be done with a repo-wide grep in the same change** — every `MESSAGES.md N…` in the Dart sources plus every ID in SPEC and CLAUDE was updated on 2026-07-26 (REVIEW cites none), and anything older than that date is on the previous scheme.
- **Entries are defined in three shapes**, and a checker has to know all of them: a `- **ID —** …` bullet, a `### ID — …` heading, and — for the six history rows N4–N9 — a **table row** `| **N4** rang | …`. N11 additionally appears a second time, formatted like a bullet entry, as the Home-screen pointer back to its History definition; that one is a cross-reference, not a second entry.
- **Counted phrases spell out every form they can render** — `1 alarm uses …` **and** `2 alarms use …`, never an `{n} alarm(s) use …` shorthand. The form a template elides is the form nobody proofreads: N20 was written that way on 2026-07-19 (`398f5c0`) and shipped saying "**1 alarm use** Society Court" until a review rendered the singular the better part of a fortnight later.
- **Every string here is asserted by a test**, so this file cannot quietly drift from the app. `message_test` (arunoday) · `notification_message_test` + `screen_message_test` + `morning_story_test` (nivaat) · `shared_message_test` (core). Anything with a branch is a pure builder asserted directly, every branch; flat labels are asserted by rendering the real widget, which also proves they are reachable. The handful that genuinely can't be reached from a host test are named as such where they appear, rather than faked with an assertion that proves nothing.

**Index** — which section to jump to:

| App           | Notifications | Screens                                     | Sheets & dialogs |
| ------------- | ------------- | ------------------------------------------- | ---------------- |
| **Arunoday**  | A1–A3         | ring add-on A4 · home A5–A9                 | settings A10–A16 |
| **Nivaat**    | N1–N3         | home N12–N16 · history N4–N9, N10, N11      | N17–N22          |
| **Both apps** | —             | ring screen X1 · banners X2, X3 · footer X4 | X5, X6, X7       |

Worked examples below use: Nivaat court **"Society Court"**, limit **4** (gust cap **≤15**), alarm **06:00**; Arunoday location **"Jaipur"**, dawn **06:51**, wake offset **+0:20** (⇒ wake **07:11**), bedtime **21:56**.

## Shared formatting helpers

- `HH:MM` (`fmtClock`) → 24h, zero-padded: `06:00`, `21:56`.
- `date` (`fmtShortDate`) → `18 Jul`. **No year** — accepted 2026-07-22, when the log was capped at 60 rows and so could not reach a second July. **The cap is gone (2026-07-31): history is permanent, and the premise went with it.** Two `18 Jul` rows can now coexist, a year and several hundred rows apart. Left as-is pending a decision — scrolling that far is itself the year marker — and the smallest honest fix, if one is wanted, is the rule `fmtCheckTime` already uses for dates: print the year only when it differs from today's.
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
- "First light" is only honest when the wake **is** the dawn; any offset names itself instead.

### A2 — Bedtime ring

- **Title:** `Arunoday · Bedtime`
- **Body:** `Wind down — dawn comes early.`

### A3 — Bedtime "AGAIN" re-ring (after +1h)

- **Title:** `Arunoday · Bedtime`
- **Body:** `Second call — dawn does not snooze.`

## Ring screen

The screen itself is shared — see **X1**. Arunoday is the only app that adds anything to it.

- **A4 — Bedtime ritual** (bedtime alarms only; Android only, since AlarmKit's alert is Stop-only):
  - Wake line: `WAKE {TODAY|TOMORROW} {HH:MM}` → `WAKE TOMORROW 07:11` — `TODAY` when the bedtime itself ran past midnight, which wakes you the same calendar day
  - `NOT SLEEPY` + button `+1h`

## Home screen

- **A5 — App label:** `ARUNODAY`
- **A6 — Wake:** hero clock `{HH:MM}` → `07:11`, with the label line beneath it: `WAKE · DAWN{±offset}{ · IN {Xh Ym} | · OFF}`
  → `WAKE · DAWN+0:20 · IN 7H 22M` · disabled → `WAKE · DAWN+0:20 · OFF`
- **A7 — Bedtime:** second clock `{HH:MM}` → `21:56`, with the label line: `BEDTIME · {AUTO | AUTO{±offset}}{ · AGAIN {HH:MM}}{ · {Xh Ym} TONIGHT}{ · IN {Xh Ym} | · OFF}`
  → `BEDTIME · AUTO+0:30 · 8H 45M TONIGHT · IN 3H 05M` · with re-ring → `BEDTIME · AUTO · AGAIN 22:56 · 8H 15M TONIGHT · IN 0H 45M`
- `IN {Xh Ym}` and `OFF` are opposites sharing the final slot on both lines — a switched-off alarm must never advertise a ring. The countdown is minute-truncated so it agrees with the clock above it, and empty when there is nothing ahead.
- **Both clocks fall back to `—` in code, and neither fallback is reachable** (corrected 2026-07-31). It was listed here as the clock "when no wake can be computed (no location)", which was wrong twice over: **no location shows A9**, not this screen — and this screen exists only when there is one, whose daily dawn was checked before you could add it (A16), so dawn and everything derived from it resolve. The `—` stays as defence rather than a force-unwrap; see N4 for what force-unwrapping an "impossible" null costs when it arrives anyway. Same `—` on A11's `Bedtime` row, same reasoning.
- **A8 — Footer:** `Dawn {today|tomorrow} {HH:MM}{ · Sunrise {HH:MM}}` + second line `{loc name}`
  → `Dawn today 06:51 · Sunrise 07:18` / `Jaipur`
- **A9 — Empty state:** title `Wake with the dawn.` · body `Add your location — the alarm follows its real dawn, every day of the year.` · button `Add location`

## Settings sheet

- **A10 — Title:** `SETTINGS`
- **A11 — Rows** (grouped by ritual, 2026-07-20): `Wake alarm` (switch) · `Wake offset from dawn` (trailing `{±offset}` → `+0:20`) · `Bedtime alarm` (switch) · `Bedtime` (subtitle `Auto` / `Auto{±offset}` — sentence-case here, unlike A7's `AUTO`; trailing `{HH:MM}` → `21:56`) · `Bedtime again` (subtitle `Not sleepy — tonight only`, trailing `{HH:MM}` and a ✕ that cancels it; **only while a re-ring is pending**) · `Alarm sound` (trailing: tone name, e.g. `Dawn Bells`) · section `APPEARANCE` (X7) · section `LOCATIONS` (a `+` opens X5; each saved place is a row — tap to make it active, bin to delete)
- **A12 — Hints**, each shown **only when there is something to undo**: `Long-press wake offset to reset to dawn.` (offset ≠ 0) · `Long-press bedtime to return to auto.` (bedtime manually set)
- **A13 — Yearly sleep readout:** `Year here: sleep {Xh Ym} (summer) to {Xh Ym} (winter) — the natural swing of dawn at this latitude.`
  → `Year here: sleep 7h 33m (summer) to 8h 27m (winter) — the natural swing of dawn at this latitude.`
- **A14 — Bedtime picker:** title `BEDTIME` · the big time (tap it → system time picker, helpText `BEDTIME`) · hint `auto is {HH:MM} · tap the time to pick exactly` → `auto is 21:56 · tap the time to pick exactly` — `{HH:MM}` is the **sleep plan's** bedtime, the anchor the offset is measured from, so it is quoted whether or not you have nudged bedtime off it · nudge buttons `−1h` / `+1h` (each disabled at its end of the ±12h range) · buttons `Cancel`, `Save`
  _(Corrected 2026-07-31. The hint was written `{auto is {HH:MM} | manual}`, and there is no `manual` form: the null it branched on meant **no sleep plan** — i.e. no location — not a manually-set bedtime, which leaves the auto value perfectly quotable. No location also means no settings page to open this from, so the branch could never render. The dialog behind it failed the same way, anchoring to a fabricated 22:00 and then silently discarding whatever you saved; it now declines to open at all.)_
- **A15 — Wake-offset picker:** title `WAKE OFFSET` · the big offset (tap it → system time picker, helpText `WAKE TIME`) · hint `dawn {HH:MM} · wake {HH:MM}` → `dawn 06:51 · wake 07:11` (anchor first, then the result) · second line `tap the offset to pick the wake time` · nudge buttons `−1h` / `+1h` (also disabled at their ends) · buttons `Cancel`, `Save`
  _(Corrected 2026-07-31, same shape as A14. The hint had a second form `relative to civil dawn`, and the second line was documented as appearing "only when a location is set" — both describing a dialog opened with no dawn, which cannot happen. Worse, that state also short-circuited the wake↔bedtime collision check (A16): the one case that produced the alternative wording was the one case where Save stopped being validated. Dawn is required now, both lines are unconditional, and the check always runs.)_
- **A16 — Validation:** wake↔bedtime collisions show live inside the wake-offset / bedtime dialogs (`Bedtime can't be the same as the wake alarm.` / `Wake time can't be the same as the bedtime.`) with Save disabled. Two refusals live in the **place picker**, checked before the place is named or saved: polar → `No daily dawn here (polar) — Arunoday needs a real dawn.` (same wording for Tromsø etc.), and duplicate → `Same dawn as {name} — already added.` → `Same dawn as Jaipur — already added.` (Arunoday dedupes by **dawn time**, since two towns that share a dawn are one alarm; Nivaat dedupes by distance instead — N21.) Both come from `ArunodayController.placeRefusal`: home and settings can each add a location, and until 2026-07-31 each carried its own **inline copy** of this pair — two strings to keep in step, neither reachable by a test.
  _(Bedtime **is** allowed to land on a pending re-ring's minute — the re-ring wins that slot so only one alarm sounds, and if the re-ring is cancelled the daily bedtime takes it back.)_
  _(The polar refusal replaced a whole no-dawn **screen** you could strand yourself on; refusing at add means it can never be reached.)_

---

# NIVAAT

## Notifications

_Every title shares one shape — `{court} · {HH:MM} · {status}` (`nivaatNotificationTitle`), status being `Play! 🏸` for the ring and `Still checking` / `Skipped` / `Cancelled` for the three states of the morning's one card. **The app name is deliberately absent** (2026-07-22): both OS notification headers already print "Nivaat" above the title, so repeating it there spent the scannable head of the line on a duplicate. The court leads instead — it's what tells two alarms apart — and for the same reason the bodies below no longer name it. Statuses are **sentence-capitalised**: they head a title, not a mid-sentence clause. `{HH:MM}` is the **alarm time you set** (e.g. `06:00`) — never the ring time or the wind-check time._

_Every body is now **just the evidence** (2026-07-22): the verdict lives in the title, so the trailing promises (`will ring if it calms`, `will ring once it's reachable`) and the sign-off (`— next time`) are gone, and with them the 🏸 — which survives only as part of the ring's status, the one moment that earns it._

### N1 — Ring (the alarm itself; AlarmKit on iOS, `alarm` package on Android)

- **Title:** `{court} · {HH:MM} · Play! 🏸` → `Society Court · 06:00 · Play! 🏸`
- **Body:** `{windgust} · checked {checktime}` → `wind 3 (≤4) · gusts 12 (≤15) km/h · checked 06:00`
- **Button:** `Stop`
- The ring carries its freshness too (2026-07-22) — a ring booked from last night's forecast says `· checked 17 Jul 22:00`, so a 6am reading is never confused with a 12-hour-old one. Its N4 history row quotes the **same instant** but words it `last checked 06:00` — plain `checked` is the ring's alone, because a single check approved it.
- **On screen:** if Nivaat is open on Android when this fires, the shared ring screen (X1) appears and shows this body verbatim. Nivaat adds no actions of its own to it, and on iOS there is no such screen at all.

### N2 — The morning's card (one notification, rewritten as the morning resolves)

Posted at T when the alarm doesn't ring, and **rewritten in place** — same id, three states — until the morning is settled. There is no second card: the heads-up and the skip card used to be separate notifications, which left the shade holding a promise ("watching until 06:30") that the morning had already broken (2026-07-26).

- **Title:** `{court} · {HH:MM} · {status}` — `Still checking` / `Skipped` / `Cancelled`
- **Body — still checking:** `{reason} · {windgust} · last checked {checktime} · watching until {checktime}`
  → `Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:00 · watching until 06:30`
- **Body — skipped:** the same, minus the deadline
  → `Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:30`
- **Body — skipped, when checking outlasted the reading:** ` · watched until {checktime}` is appended
  → `Too windy · … · last checked 06:29 · watched until 06:30` — the only thing separating "we gave up at 06:29" from "we tried at 06:30 and got nothing". Omitted whenever the two show the same minute, which is almost always.
- **Body — cancelled:** `{reason} · {windgust} · last checked {checktime} · stopped {checktime}`
  → `Too windy · wind 6 (≤4) · gusts 18 (≤15) km/h · last checked 06:00 · stopped 06:05`
  **Only ever written while the retry window is open** — between T and the cap. It is gated on the card having been posted (`CheckState.cardShown`, set at T and cleared when the morning finalises), so cancelling **before** T writes nothing at all: a window that never opened has nothing to explain, and a card nobody saw needs no correction.
- **gusty / no-data** swap only the reason: `Too gusty · wind 3 (≤4) · gusts 16 (≤15) km/h · …`, and `Couldn't reach the wind · last tried 06:00 · watching until 06:30` — no-data carries no numbers, because none were read, and says `last tried` for the same reason.
- **`Cancelled`, never `Stopped`.** The ring's own button is literally `Stop`, so a card titled "Stopped" reads as "you silenced the alarm" — a different event that really exists in this app.
- **Every push alerts.** Rewriting is new information every time, including a Keep-checking deadline you just moved, so there is no quiet variant and no per-platform presentation flags. Posting to an id you dismissed re-creates it, which is right: the outcome is news you haven't seen.
- **Cancelled by:** a late ring (the ring becomes that morning's card), **delete**, or **court-gone**. Nothing else takes it down — a toggle-off or an abandoning edit _rewrites_ it to `Cancelled`, because the alarm still exists and deserves the explanation.
- **Keep checking mid-window** re-posts it with the new deadline and appends a matching row — **unless the new deadline is already behind you**, in which case the morning ends there and then and the card goes straight to `Skipped` (2026-07-31). Shrinking 30→1 at 06:02 used to push `watching until 06:01`, alerting, and leave that broken promise in the log for good. The wind numbers stay whatever the first push captured — never rebuilt from the edited alarm, which put the new limit beside the old reading: "Too windy · wind 5 (≤20)".
- **Raising the limit mid-window does take effect**, and the two rules don't conflict. The re-post above republishes an **old reading**, so it must keep that reading's old limit. The remaining **retries** are a different thing: they re-decide against the alarm as it is now, which is what makes "raise the limit at 06:05 and it still rings this morning" work — and the final `Skipped` card and its row then quote the new limit beside the reading from a check that actually ran under it. Every card is one moment: one reading, one pair of limits, never a mix.

### N3 — Notification channel (Android)

- **Name:** `Alarm updates` · **Description:** `Still checking, and why an alarm didn't ring` · **id:** `nivaat_alarm_updates`
- Carries **every state** of N2, so it can't be named for one of them: the old `Skipped alarms` meant muting the skip explanations also killed the still-checking card — the one that's still worth acting on (renamed 2026-07-22).

## History

Shown in the **history sheet** (a scrollable list of past outcomes; opened from settings, or by tapping the home "still checking" cue while a retry window is open) — header `HISTORY`, and when there are no rows yet, `Every ring and skip lands here, with the wind that caused it.` Each entry has a **line** — the primary text (outcome + numbers) — and a **sub** — the smaller secondary line beneath it (court + when + freshness) — plus a leading icon: **air** for windy/gusty, **cloud-off** for no-data, **bell** for a ring, **cancel** for a cancellation. The icon shows the _reason_, so a `Still checking` row and the `Skipped` row under it share one — it's the line that tells them apart. Both text lines lead with the **court name**.

History is an **append-only log of card pushes** (2026-07-20, tightened 2026-07-26): every push of N2 appends exactly one row, and **nothing is ever rewritten** — a row always says what was true when it was written. A missed T leaves a `Still checking` row; the outcome is a separate second row; a cancellation is a third kind. Adjacent rows carry the meaning that annotations used to: `Still checking … watching until 06:30` above `Skipped … last checked 06:10` **is** the shortfall, with no vocabulary for it. Rows are identified by `alarmId + at + pushSeq`, so two isolates racing on one push converge while two real pushes both survive — content can't be the key, since Keep checking 30→60→30 leaves two byte-identical rows that must both stay.

A morning writes **one row per card push**, newest at the top of the sheet — usually two (the promise, then the outcome), just one when the app never ran inside the retry window, and more whenever you move the deadline mid-window. First the outcome family, how a morning ended:

| Outcome        | Line (template → example)                                                                 | Sheet sub (example)                                   |
| -------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------- |
| **N4** rang    | `Rang (vol. {vol}%) · {windgust}` → `Rang (vol. 85%) · wind 3 (≤4) · gusts 12 (≤15) km/h` | `Society Court · 18 Jul · 06:00 · last checked 06:00` |
| **N5** windy   | `Skipped · {windgust}` → `Skipped · wind 6 (≤4) · gusts 18 (≤15) km/h`                    | `Society Court · 18 Jul · 06:00 · last checked 06:30` |
| **N6** gusty   | `Skipped (gusty) · {windgust}` → `Skipped (gusty) · wind 3 (≤4) · gusts 16 (≤15) km/h`    | `Society Court · 18 Jul · 06:00 · last checked 06:30` |
| **N7** no-data | `Skipped (no data)` — no numbers, because none were read                                  | `Society Court · 18 Jul · 06:00 · last tried 06:30`   |

Then the two rows that are **not** an ending — the promise a morning made, and you calling it off:

| Kind                  | Line (all forms)                                                                                                                                   | Sheet sub (example)                                                          |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| **N8** still checking | `Still checking · wind 6 (≤4) · gusts 18 (≤15) km/h`<br>`Still checking (gusty) · wind 3 (≤4) · gusts 16 (≤15) km/h`<br>`Still checking (no data)` | `Society Court · 18 Jul · 06:00 · last checked 06:00 · watching until 06:30` |
| **N9** cancelled      | `Cancelled` — bare, whatever the wind was doing                                                                                                    | `Society Court · 18 Jul · 06:00 · stopped 06:05`                             |

N8 mirrors the skip lines exactly — the status word swaps for `Skipped`, the reason stays in the parenthetical — so a morning's rows read as one sentence continued rather than two unrelated entries. (N8's sub says `last tried` in the no-data form, like N7.)

**The outcome subs read `06:30`, the cap itself** (corrected 2026-07-31 — they showed `06:29`, which was quoting a bug as if it were the format). The cap check is the window's last check and it really does run **at** the cap: the cascade clamps its final booking to that instant, and an occurrence stays live to the end of the cap's minute (`nivaatOccurrenceEndsAfter`). A `06:29` reading behind a 30-minute window means one specific thing — the 06:30 attempt failed to reach the network — and it is exactly then that `· watched until 06:30` appears to say so (N10). Before 2026-07-26 a five-second slack made every late wake look like a new morning, so `06:29` was the *normal* result; the doc's examples were still the pre-fix ones.

- Sheet **sub** = `{court} · {date} · {HH:MM} · {last checked|last tried} {checktime}{ · watch note}`, where `{HH:MM}` is the **alarm time** and the freshness clause is `last checked` for a real reading or `last tried` for a no-data row (the last attempt — nothing was read). **The ring card is the only place that says plain `checked`**: one check approved it, so "last" would imply others that never happened. Line and sub are both built by `nivaatHistoryLine` / `nivaatHistorySub` — outside the widget, so they can be asserted as whole strings — and the freshness and watch-note phrases come from the same helpers the notification bodies use, so a row and its card can't word one fact two ways.
- **The N9 row is the one exception: it carries no freshness clause at all** (`… · 06:00 · stopped 06:05`), while the N2 cancelled _card_ keeps the reason, the numbers **and** `last checked`. Deliberate (Samyak, 2026-07-26): a cancelled row only ever exists directly beside the N8 row that already holds all of it, and the card has no neighbour to lean on. Accepted cost — the row alone doesn't say how far checking got before you stopped it (retries to 06:04, stopped 06:05, and the row shows only 06:05); the card does, and so does the pair of rows read together.
- `{vol}` is the ring's **volume** (the wind ramp — calmer morning, louder ring, per N14), not a score. Written `vol. 85%` so it can't be read as one (2026-07-22). Only ever **100, 85 or 70** since 2026-07-26 — the ramp has three steps, so these are the only three numbers this line can print. A row that carries no volume degrades to a bare `Rang · {windgust}`, and one with no readings either to just `Rang` — never a dangling `· ` (2026-07-26). The engine stores both on every rang row it writes, but the fields are optional and history is **persisted**, so force-unwrapping the volume turned a single odd row into a permanently un-openable log — the one screen that explains a morning the alarm didn't ring. Every line is built by `nivaatHistoryLine`, unit-tested alongside the other message builders.
- **N5's bare `Skipped` means windy — locked 2026-07-22, don't add `(windy)`.** Windy is the default skip, so only the exceptions carry a label (`(gusty)`, `(no data)`). Accepted consequence: the sheet's wording differs from the card's, which says `Too windy` for the same event.
- A row whose court is gone is **pruned on load**, so `{court}` always resolves. The `court removed` fallback (same wording as N15) is defence only — deleting a court already sweeps its log; the gap was a background check landing a row just after that sweep.

### N10 — Watch note (the trailing clause on a row's sub)

Rows never age, so this is pure formatting of what that push recorded — no clock, no neighbours, nothing that changes later.

- **Still checking:** ` · watching until {checktime}` → ` · watching until 06:30` (` · watching until 06:01` on a 1-min window; ` · watching until 23 Jul 00:19` when the cap crosses midnight). Present tense **forever** — that is what the card said at that moment. How far the morning actually got is the next row's business.
- **Outcome:** ` · watched until {checktime}` → ` · watched until 06:30`, and **only** when checking outlasted the last reading. Compared as displayed, so 06:30:40 against a 06:30 reading adds nothing.
- **Cancelled:** ` · stopped {checktime}` → ` · stopped 06:05`.
- No note on any other row. `· failed` is **gone** (2026-07-26): it was a verdict, and every verdict needs a pass mark nobody can defend — running to 06:29 isn't a failure, running to 06:01 is, and there is no honest line between them. Reporting the reach instead means the reader draws it.

### N11 — Home watching cue (only while a retry window is open)

- Text: `Still checking wind · until {checktime}` → `Still checking wind · until 06:30`
- Leading wind-accent filled bullet in the text (`● Still checking wind · until 06:30`) — "live + tappable", not a word prefix.
- With several open windows, quotes the **soonest** cap (same pick the home dismiss timer uses). Cap times come from each still-checking row's `watchedUntil`, so they are per-alarm.
- **Clears when checking actually stops (2026-07-23)**: the occurrence's **newest** row is no longer a `Still checking` one (an outcome or cancellation means the morning is done), the alarm is gone/disabled, **or** live `CheckState` no longer targets that occurrence (toggle-off discards it; toggle-on re-arms tomorrow — cue must not reappear for today's dead retries). Hidden the rest of the time (no permanent "last outcome" dump on home — 2026-07-22). Tap opens the history sheet.

## Home screen

- **N12 — App label:** `NIVAAT`
- **N13 — Background note (footer, only when ≥1 alarm):** `Keep the phone charged and connected to the internet before your alarm — the background wind check needs both.` **`connected to the internet`, not `online`** (2026-07-31, Samyak): to a general reader "online" first suggests *signed in*, and this app has no account to sign into. The longer phrase costs nothing here — it is a quiet footer with room to wrap. Soft-wraps (no hard newlines — large accessibility text must reflow cleanly). Hidden on the empty intro. Rendered at 50% of secondary text opacity (2026-07-22) so it stays a quiet caveat.
- **N14 — Empty state:** title `The windless alarm.` · body `Rings only when the wind at your court is low enough to play. The calmer the morning, the louder it rings.` Sits **a third down**, the same 1:2 spacer rhythm as Arunoday's A9 (2026-07-31 — it was centred, which put the headline at 46% of the screen against A9's 28%, and centring reads lower still because the block hangs below its own midpoint with no button under it to balance the way A9's `Add location` does). Both sides assert the bound, since neither app's tests can see the other.
- **N15 — Alarm list row:** clock `HH:MM` with trailing `in {Xh Ym}` on the same line (enabled only) → `06:40` … `in 1h 00m`; **past 24h it switches to `in {Nd HHh}`** → `in 5d 04h` (a weekend-only alarm is five days out every Monday — hours alone would read `in 120h 00m`; the day form truncates to the hour, so 24h30m reads `in 1d 00h` — each form drops what's below its smallest unit, and the seam is exact: 23h59m still reads `in 23h 59m`); sub `{weekdays} · {court} · ≤{limit} km/h` → `Every day · Society Court · ≤4 km/h` — court missing → `court removed` (**defence only**, and no supported state reaches it: deleting a court deletes its alarms in the same synchronous step, which is what N20 warns you about, so an alarm can't outlive its court. Same word and same reasoning as the history fallback below — it exists so a lookup miss degrades to one word instead of blanking the row). Non-default retry appends ` · +{n}m` on the sub. Countdown is sentence-case (Nivaat body text — not Arunoday's ALL-CAPS `IN 7H 22M` label strip); sits **immediately after the clock, on its baseline** — not end-aligned against the toggle, which read as a label for the switch (2026-07-26). Toggle-off hides it; **also hidden while a post-T retry is open** (late ring is anytime — don't flash tomorrow beside the Still checking cue). Ticks on wall-clock :00.
- **N11 — Watching cue** (only while a retry window is open): see History § N11 above.
- **N16 — Background-checks banner** (shown while the OS throttles background wind checks; hidden while the first-run exemption dialog is up):
  - **Android:** `Battery optimisation can delay or skip Nivaat's background wind checks — it could miss a wind change and ring on a windy morning, or stay silent on a calm one.` · button `Allow background use` (re-opens the system exemption dialog)
  - **iOS:** `Background App Refresh is off — Nivaat can only check the wind while the app is open.` · button `Open Settings`

## Sheets & dialogs

- **N17 — Alarm editor:** title `NEW ALARM` / `EDIT ALARM` · big clock · live `in {Xh Ym}` / `in {Nd HHh}` under it (updates with the picker + on wall-clock :00; blank only when no weekday can fire — **a switched-off alarm still counts down here** (2026-07-26, Samyak: you are picking a time, so the time left is the feedback; its home row stays silent, where the switch is the statement); **mid-window the editor still counts down to the draft clock** even while today's retry flies and home is quiet beside Still checking (same reason — picker feedback, not the live cascade); the slot keeps its height either way so nothing jumps) · day chips `M` `T` `W` `T` `F` `S` `S` (Mon-first; selected ones fill with the wind accent) · row `Court` (flex Row, not ListTile — a 0.67-of-SCREEN trailing cap asserted at 2× text on a 390 pt phone; label is explicit `bodyLarge` so leaving ListTile doesn't demote it to grey bodyMedium) · row `Max wind at court` (dropdown items `{n} km/h` → `4 km/h`) · hint `Gust guard auto: ≤{n} km/h` → `Gust guard auto: ≤15 km/h` (derived, not chosen: 2.2 × limit ÷ 0.6, so a new alarm's default limit 6 shows `≤22 km/h` and the worked example's limit 4 shows `≤15`) · **Keep checking** (2026-07-26): label + hint `Rings late if the wind drops in time.` — the hint states the payoff, since nothing else tells you the alarm still rings, i.e. why you'd pick 60m over 1m — on one row with trailing segments `1m` / `30m` / `60m` (default **30**, `retryMinutesAfter`; Row not ListTile — wide trailer overflows ListTile on narrow phones; segments clamp their own text scale so `60m` never crops) · buttons `Delete` (editing only), `Save`
- **N18 — Duplicate-time error (alarm editor, inline above Save):** `Another alarm is already at {HH:MM}.` → `Another alarm is already at 06:00.` — any other alarm with the same HH:MM (court / weekdays ignored). Shown live on open and after picking a time; Save stays disabled while it shows (not a SnackBar — those land on the hidden home Scaffold).
- **N19 — Courts sheet:** header `COURTS` · empty state (no courts saved yet) `Save your courts — each alarm checks the wind at its own court.` · each saved court is a row: title `{name}` → `Society Court`, sub `{lat}, {lon}` to three decimals → `26.170, 75.790`, with a delete (bin) button
  - **Three decimals is not a convention, it's this app's resolution.** 0.001° ≈ **111 m** of latitude (≈ 99 m of longitude at Jaipur's 27° N) — essentially the ~100 m radius N21 refuses duplicates inside. So it is the finest precision at which two saved courts can still legitimately differ: a fourth decimal would print ~11 m of detail the app itself treats as the same place, and two decimals (≈ 1.1 km) would render genuinely different courts as identical text. If the N21 radius ever changes, this should follow it.
- **N20 — Delete-court dialog:** title `DELETE COURT` · body — one of three shapes, built from two counted phrases:
  - `{alarms}` = `1 alarm uses` **or** `{n} alarms use` · `{history}` = `1 history entry` **or** `{m} history entries` _(the singular shipped as "1 alarm **use** …" until 2026-07-26 — see the conventions at the top)_
  - alarms only → `{alarms} {court} and will be deleted too. Continue?` → `2 alarms use Society Court and will be deleted too. Continue?`
  - alarms **and** history → `{alarms} {court} and will be deleted too, along with {history}. Continue?` → `2 alarms use Society Court and will be deleted too, along with 5 history entries. Continue?`
  - history only → `{history} for {court} will be deleted too. Continue?` → `5 history entries for Society Court will be deleted too. Continue?`
  - buttons `Cancel`, `Delete`. No dialog at all when the court has neither alarms nor history — nothing to warn about, so it deletes straight away.
- **N21 — Duplicate-court error:** `Same area as {name} — already added.` → `Same area as Society Court — already added.` Nivaat dedupes by **distance** (within ~100 m), because two courts can genuinely sit close together; Arunoday dedupes by dawn time instead (A16). `NivaatController.courtRefusal`, extracted off the sheet 2026-07-31 — it was built inline in a `validate:` closure, so nothing could name it.
  - **"Area" is the right vagueness.** The refusal has to be true at both ends of the rule: `Same spot` (until 2026-07-31) undersold it — 90 m away is not the same *spot*, and someone standing at the other end of the same park would read it as a bug. Naming the number instead (`Within 100 m of {name}`) trades a friendly sentence for a precision the user can't act on. If a sharper phrasing is ever wanted, the honest one is **`Too close to {name} — already added.`**: it names the rule (proximity) rather than a place, and it survives any change to the radius. `Same area` is fine as it stands — it just describes where you are rather than why it's refusing.
- **N22 — Settings page** (header `SETTINGS`; the home top bar keeps only its tune icon, 2026-07-20): tiles `Courts` (trailing: count) · `Alarm sound` (trailing: tone name, e.g. `Court Call`) · `History` (trailing: count) · then the shared `APPEARANCE` section (X7). Order is configure → observe → decorate.

---

# SHARED (both apps)

### X1 — Ring screen (in-app overlay while an alarm sounds; **Android only**)

Core's `RingGate` overlays whichever app is open when one of its alarms rings. Top to bottom: the app label (`ARUNODAY` / `NIVAAT`), the alarm's **scheduled** `HH:MM` (not the wall clock — a ring can start a second early and this screen doesn't rebuild), **the ring notification's own body** (A1 / A2 / A3 / N1 — never a second wording), any app-specific actions (Arunoday's A4; Nivaat adds none), then the Stop button.

- **Stop button:** `STOP` (letter-spaced)
- **On iOS there is no such screen.** Rings there are AlarmKit's, so the OS draws its own Stop-only alert and `Alarm.ringing` never fires — which is also why Arunoday's `+1h` ritual is Android-only.

### X2 — Alarms-off banner (home screen; iOS, only after the user has ANSWERED the AlarmKit prompt with a deny)

- **Text:** `Alarms are turned off — {AppName} can't ring until you allow alarms for it in Settings.` → `Alarms are turned off — Arunoday can't ring until you allow alarms for it in Settings.`
- **Button:** `Open Settings`
- Same rule as X3, by a different route: `alarmSchedulingDenied` is true **only** for AlarmKit's `denied` state — `notDetermined` (never asked) reads false, so the banner can't flash behind its own first-run prompt.

### X3 — Notifications-off banner (home screen; only after the user has ANSWERED the permission prompt with a deny)

- **Nivaat, Android:** `Notifications are off — a ringing alarm shows nothing on screen (sound only, no Stop), and Nivaat can't tell you when it skips an alarm for wind, or why.`
- **Nivaat, iOS:** `Notifications are off — Nivaat can't tell you when it skips an alarm for wind, or why.` — no "no Stop" clause, because the iOS ring is the OS's own alert (X1).
- **Arunoday, Android only** (no iOS banner or permission request — it posts no iOS notifications): `Notifications are off — a ringing alarm shows nothing on screen (sound only, no Stop).`
  _(It used to add "and bedtime reminders can't appear" — dropped 2026-07-31, because it wasn't true. The bedtime is an **alarm** (A2/A3), not a reminder: with notifications off it still rings, it just rings with nothing on screen, which the first clause already says. Arunoday posts no other notification of any kind, so there was nothing else to name.)_
- **Button (all):** `Turn on notifications` (Android → the app's notification settings page; iOS → the app's Settings page)
- **N16 is the odd one out and should be.** X2 and X3 gate on "the prompt was answered no", because a permission is a question with an answer. Battery optimisation and Background App Refresh are not — they are live OS settings you can change any time and Android will re-ask forever, so N16 reads the setting directly and instead suppresses itself while its own once-ask dialog is on screen (`batteryAskInFlight`). Three banners, one rule — **never appear behind the dialog you are about to show** — enforced three ways because the underlying states differ.

### X4 — Maker's mark (home screen footer, both apps, always visible)

- **Text:** `CRAFTED WITH ♥ BY SAMYAK` — the `♥` is the Material `favorite` icon in the app's accent colour (a text glyph became the red emoji on Android); tapping `SAMYAK` opens samyak1409.github.io in the browser

### X5 — Location picker (add a place)

- GPS button: `Use my current location` (loading: `Getting your location…`) · caption `Works offline`
- Search hint: `Or search a place…` · each result is a row: title `{place name}`, sub `{region}` → `Jaipur` / `Rajasthan, India`
- Name dialog: title `NAME THIS PLACE` · default `My location` — a suggestion you can accept or type over; **clear the field and `Save` goes dim** until you type something (2026-07-31: it used to silently write `My location` back, which read as the app ignoring a deletion you meant. Whitespace counts as empty, since the trimmed value is what would have been saved). Keyboard submit obeys the same rule, so it isn't a way round the dim button. · buttons `Cancel`, `Save`
- Errors: `Search failed — check network` · `Turn on location services first` · `Location permission denied` · `Couldn't get your location — try search instead`
- Each app adds its own refusals here, checked before the place is named: Arunoday's polar + same-dawn (A16), Nivaat's same-area (N21).
- _The **three GPS errors** are the only strings in this file with no automated assertion — each needs a real device geolocation result, which no host test can produce. Device smoke test only, said plainly rather than faked. (The name dialog is not among them: it opens on a host through `showNamePlaceDialogForTest`, and `Search failed — check network` is asserted from a faked geocode failure.)_

### X6 — Sound picker

- Header: `ALARM SOUND` · section (Android) `DEVICE ALARM SOUNDS`
- Default tone names: Nivaat `Court Call` · Arunoday `Dawn Bells`

### X7 — Appearance settings (Arunoday settings page · Nivaat settings page, header `SETTINGS`)

- **Section label:** `APPEARANCE`
- **Bold-type toggle:** title `Bold clocks & titles` · subtitle `Heavier type on the home screen` (ships OFF)
- **Icon picker:** title `App icon` · three thumbnails with labels — Arunoday `Horizon` (default) / `Rays` / `Dawn`; Nivaat `Shuttle` (default) / `Calm` / `Crest`. Android launchers may take a moment to show the new icon
- **Android close notice** (dialog, **Android only**, before the switch — 2026-08-01): title `CHANGE APP ICON` · body `Android will close {AppName} to apply the new icon.` → `Android will close Nivaat to apply the new icon.` · button `OK` (one). `appIconRestartWarning`
  - **It informs, it does not ask.** No Cancel: tapping a thumbnail already said what you want, so a second choice would be invented. `OK` applies the switch and the app goes immediately (`finishAndRemoveTask`, since the wait read as a freeze). Tapping the barrier backs out and changes nothing — **the only way out now**, so the dialog must stay `barrierDismissible`; a test taps it.
  - **One sentence, locked by a test.** Naming **Android** as the actor is the whole job — it says the close is the platform's price, not a fault, which is what stops it reading as a crash (device-caught: _"it feels like the app crashed"_). Two earlier drafts were cut: one spent a second sentence on the mechanism, the other on reassuring you the alarms survive — _"I don't even want this thing"_ (Samyak), and he's right that an alarm was never in danger. **Don't re-add either**; the mechanism lives in `appIconRestartWarning`'s dartdoc. **iOS gets no dialog from us** — `setAlternateIconName` leaves the app running and the OS shows its own alert, so ours would be pure friction.

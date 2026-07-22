# Behaviour review — Arunoday & Nivaat (v1)

**Purpose:** a plain-language inventory of every meaningful algorithm / flow / decision in both apps, so I can double-check each is as intended. Grouped so shared behaviour isn't repeated; **OS differences are flagged inline** (most logic is identical on Android and iOS — the real splits are alarm delivery and background scheduling).

**How to use:** every item is numbered. **Default = approved.** Reply only with the ones to change, e.g. _"change 3.9: …"_ or _"3.4 wrong, should be …"_. Cosmetic-only behaviour (scrollbars, snackbars, double-tap guards) is intentionally omitted.

---

## 1. Common to both apps (and both OSes)

**1.1 — One alarm interface, platform-swapped underneath.** Both apps schedule/cancel rings through a single core interface (`scheduleRing(id, time, title, body, volume)` / `cancel`). _Which_ engine actually rings is chosen per platform (1.2).

**1.2 — How the alarm rings (OS split):**

- **Android:** the `alarm` package — full-screen, loud, loops, vibrates, enforced volume, and it **rings even after the app is swiped from recents** (it's a system AlarmManager alarm).
- **iOS (min 26.0):** Apple **AlarmKit** — a _system_ alarm that breaks through Silent mode & Focus, shows full-screen (**Apple's own UI — Stop-only; app-custom buttons like Arunoday's "+1h" can't live on it**), and survives app termination/reboot. Needs a one-time iOS authorization prompt. _(Implemented and selected in code; the auth prompt is verified on the iOS 26 simulator, but ring behaviour on a real iOS device is still untested.)_
- **AlarmKit denied:** **nothing rings** — there is no `alarm`-package fallback on iOS (by choice: its Timer-based ring is too unreliable to ship). Scheduling silently no-ops and a home-screen banner (`AlarmPermissionBanner`) tells the user and opens Settings so they can allow alarms.
- We set _"don't warn on kill"_ — swiping the app away does **not** post a scary "alarm may not ring" notice (the alarm still fires; that warning only applies to aggressive OEM task-killers).

**1.3 — In-app ring screen.** When an `alarm`-package alarm rings _and the app is open_, a full-screen black STOP screen overlays everything, showing the alarm's **scheduled** time (not wall-clock, so a ring that starts a second early still shows the right minute) and its message. _OS note:_ on iOS every ring is an AlarmKit **system** ring (Apple's Stop-only UI), so this in-app screen — and app-custom actions like Arunoday's "+1h" — appear only on **Android** now.

**1.4 — Notification permission requested at first launch — Nivaat on both platforms, Arunoday on Android only (2026-07-20).** Android 13+ needs the runtime grant (the ring's card/full-screen UI rides on it); Nivaat asks on iOS too because the `alarm` package only _checks_ iOS permission and never asks, and its skip notifications are real iOS notifications. Arunoday no longer asks on iOS at all — under AlarmKit-only iOS it posts zero notifications there, so the old prompt asked users for nothing. A deny is never silently absorbed — see 1.9. _Example:_ first open → OS permission prompt (except Arunoday-iOS: no prompt).

**1.5 — Locations are saved lat/lon, never live GPS at alarm time.** You add a place once; all dawn/wind math uses those saved coords, fully offline. No background location, ever.

**1.6 — Adding a place:** "Use my current location" (one-shot GPS — works offline, low-accuracy is fine at dawn/wind scale) **or** type-to-search (Open-Meteo geocoding, free, no key). A pick is validated (duplicate / polar) **before** you're asked to name it, so a doomed pick never wastes effort. _Example:_ tap GPS on a spot you already saved → told immediately, no name prompt.

**1.7 — On resume, both apps re-sync** (reload from storage + recompute + reschedule), since a background check or notification action may have changed state. Two additions (2026-07-19): a resync also fires **the moment a ring starts or is stopped** (RingGate reports it — so e.g. Nivaat's history updates while the alarm still sounds), and Nivaat's resync first **reloads SharedPreferences from disk** — each isolate caches it, so without the reload the foreground app can't see what a background wind check wrote until a cold start. **Nivaat UI freshness (2026-07-22):** after a background `evaluateAll`, the check isolate also **pings the UI isolate** (`pingNivaatUiResync`) so home/History update the moment a skip card lands — not only on resume.

**1.8 — Theme:** pure-black OLED scaffolds / app bars, dark-only, minimal. Arunoday = dawn orange, Nivaat = sky blue. **Elevated overlays (2026-07-23):** sheets / dialogs / snackbars / `DropdownButton` menus / `showTimePicker` share `AppPalette.surface` (`#0E0E0E`) — menus via theme `canvasColor`; time picker via `timePickerTheme` + `ColorScheme.surfaceContainer*` (SDK ignores `dialogTheme`, so without the pin it punches a true-black hole); `surfaceTint` transparent. **Portrait-only (2026-07-22):** both apps lock orientation (Android `screenOrientation="portrait"`, iOS Info.plist phone + iPad portrait-only + `UIRequiresFullScreen`, plus `lockToPortrait()` in both mains) — phone landscape overflows home/sheets/dialogs; no landscape layout pass in v1.

**1.9 — A denied capability always leaves a persistent home-screen nudge banner with a one-tap fix (2026-07-19/20), re-checked on every resume:** (a) **notifications denied** → "Notifications are off …" banner, deep-linking to the app's notification settings (after the second Android deny the OS never re-shows the dialog, so Settings is the only way back); shown by both apps on Android, by Nivaat on iOS. (b) **Nivaat background work throttled** → battery-optimisation banner (Android; tapping re-shows the system exemption dialog, which — unlike runtime permissions — may be re-asked forever) / Background App Refresh banner (iOS; opens Settings). (c) **AlarmKit denied** (iOS) → the existing "Alarms are turned off" banner. None of them ever flashes behind its own first-run dialog: the notification banners wait until the prompt has been _answered_, the battery banner suppresses itself while the once-ask dialog is up and re-checks on the resume that answers it. **Armed-home only (2026-07-22):** banners hide on the empty intro (Nivaat: no alarms yet; Arunoday: no location yet) so the hero stays clean — they appear once there's something to protect. _Example:_ deny the battery dialog → the banner appears right as the dialog closes (once an alarm exists).

---

## 2. Arunoday — dawn wake alarm

_Concept: wake with the real civil dawn at your location, every day, auto-tracking through the year._

**2.1 — Civil dawn is the anchor.** Wake = civil dawn (sun 6° below horizon) at the active location, from NOAA (National Oceanic and Atmospheric Administration, a US scientific and regulatory agency) solar math; it drifts ~1 min/day across the year. _Example:_ Tonk civil dawn ≈ 05:08 in June → ≈ 06:51 in January, and the alarm follows automatically. Internally second-precise, but **floored to the whole minute** so displays never flicker.

**2.2 — Wake offset from dawn.** Shift wake to _dawn ± offset_ (±12h, via ±1h taps or an exact time picker); default 0 = exactly dawn. _Example:_ +2:00 → wake 2h after dawn; home shows "DAWN+2:00".

**2.3 — Bedtime is auto-derived from dawn, and is INDEPENDENT of the wake offset.** Fixed bedtime = midpoint(earliest, latest yearly dawn) − 8h — one fixed clock time all year. It keeps every night's sleep inside **[7h, 9h]** as long as the location's yearly dawn swing is ≤ ~2h; a wider swing can't be held in that window by a single fixed bedtime (see 2.5). Changing the wake offset does **not** move bedtime (that's what 2.4 is for). _Example:_ Bengaluru → bedtime auto 21:56, whatever your wake offset is.

**2.4 — Manual bedtime adjustment (offset from auto).** Nudge bedtime earlier/later (±12h), stored as a signed offset from the auto plan so it travels across cities ("1h later than ideal" stays 1h later than the _new_ ideal). Long-press to reset to Auto. _Example:_ set auto+30m; move to a city where auto is 22:10 → you get 22:40.

**2.5 — Yearly sleep-range readout; feasibility is computed but NOT shown.** The settings screen shows the year's sleep span — e.g. _"Year here: sleep 7h 33m (summer) to 8h 27m (winter) — the natural swing of daylight at this latitude."_ Internally a `feasible` flag is computed (true when the yearly dawn swing ≤ ~2h, i.e. [7–9h] is holdable), but it is **not surfaced anywhere in the UI** — so there is currently **no explicit "no fixed bedtime fits 7–9h" message**; at an extreme latitude the shown range simply widens past 7–9h (e.g. "5h 45m (summer) to 10h 15m (winter)"). _(Physics, not a bug — a truly fixed bedtime ⇒ the summer↔winter gap equals the dawn swing.)_

**2.6 — Rolling 7-day schedule.** The OS rings alarms only if they're registered ahead of time, so Arunoday pre-registers today + the next 7 days of wake/bedtime alarms (ids 1000–1007 / 2000–2007) and re-registers the batch on every open / resume / change — a safety net that keeps you covered for ~a week without opening the app (beyond that it drains; v2 adds a background top-up). Each refresh cancels obsolete alarms but never a currently-ringing one.  
Note: Ordinary alarm apps use the OS's native fixed-time repeat (iOS repeating notification/AlarmKit; Android repeating/self-rearming AlarmManager) — but Arunoday's wake time changes daily (dawn drift), so no fixed repeat fits; hence the rolling batch. It self-sustains in practice (opening the app, and on Android the daily full-screen ring foregrounding the app, both re-fill the window); the true gaps are iOS (system ring doesn't resume the app → relies on app-opens + BGAppRefresh) and OEM task-killers, both closed by the v2 background self-rearm.

**2.7 — Bedtime ring ritual.** Bedtime rings with one action: **"Not sleepy → +1h"** — stops the ring instantly and re-rings an hour later (the "AGAIN" reminder). The ring screen also shows tomorrow's wake, labelled TODAY/TOMORROW correctly for a post-midnight bedtime. _Example:_ rings 21:56; tapping +1h stops it and schedules a re-ring **1h from the tap** (≈22:56 if tapped promptly); home shows "AGAIN 22:56". _(There is **no snooze** — locked decision; the ritual/+1h covers it.)_

**2.8 — Sunrise shown for context only.** The home footer shows today's dawn + sunrise; once sunrise passes it rolls to tomorrow's. Every alarm anchors to civil _dawn_; sunrise is display-only.

**2.9 — Multiple locations + dawn-dedup.** Save several places, pick the active one. A new place whose civil dawn matches an existing one _to the minute_ (sampled at both solstices — ~Jun 21 & Dec 21, the year's longest & shortest days — and both equinoxes — ~Mar 21 & Sep 21, when day ≈ night) is rejected as a duplicate — distance is the wrong test (dawn barely changes over long east–west distance). _Example:_ two neighbourhoods in one city that share the dawn → duplicate.

**2.10 — Polar refusal (add-only).** A location with no daily civil dawn (high latitude / white-night summers) is refused **in the place picker at add** — "No daily dawn here (polar) — Arunoday needs a real dawn." There is no activate-time refuse and no dedicated "no dawn" home screen (2026-07-23): polar coords never enter the saved list, so post-add handling was dead code. _Example:_ Tromsø / Anchorage → rejected at pick.

**2.11 — Delete location.** Deleting the active one moves active to the next remaining; deleting the last one drops you back to the empty "add a location" home screen.

**2.12 — Alarm sound.** A bundled tone, or **(Android only)** a device system alarm sound, with tap-to-preview. iOS shows only bundled tones (Apple exposes no API to list system alarm sounds).

**Arunoday platform split (iOS vs Android):**

- **iOS (min 26.0)** → **both** wake and bedtime use **AlarmKit** — Silent/Focus-proof system alarms that survive force-quit and reboot. Apple's UI is **Stop-only**, so the bedtime **"+1h" ritual is not available on iOS** (open the app to adjust). This is the 2026-07-16 reliability-over-ritual decision: losing a ritual button beats losing the ring (the `alarm` package's iOS ring is an in-process Timer that a force-quit kills).
- **Android** → both wake and bedtime use the **`alarm` package** — genuinely kill-proof (foreground service + AlarmManager), and its ring screen still **hosts the "+1h" ritual**. So the ritual is Android-only.
- Denied AlarmKit → **no ring at all** (no `alarm`-package fallback on iOS), and a home-screen banner nudges the user to Settings. The old `RoutingScheduler` (the wake-vs-bedtime split) is **deleted** — one scheduler now serves both types.

---

## 3. Nivaat — wind-conditional badminton alarm

_Concept: an alarm for a specific court that only rings if the wind there is low enough to play — and the calmer it is, the louder it rings._

**3.1 — Each alarm = time + weekdays + a court + a max wind.** Court picked from your saved courts; max court-wind is **4–6 km/h, default 6**; any time of day. _Example:_ 06:00 Mon–Sat at "Society Court", max 6.

**3.2 — 10 m → court-level conversion, ×0.6** (log wind profile — you play at ~2 m where wind is ~40% weaker). _Example:_ API 10 km/h at 10 m → ~6 km/h felt on court.

**3.3 — Decision in whole km/h.** Ring only if BOTH: rounded court speed ≤ your limit **AND** rounded gust ≤ the gust cap. Rounding both the reading and the cap means the shown numbers can never contradict the decision. _Example:_ court 3, gust 12, limit 4 → rings; gust 16 → skips (gusty).

**3.4 — Gust guard (auto, uneditable): 2.2 × the raw speed limit, no floor.** Sits above normal gustiness (typical gust factors ~1.4–1.7), so only an _abnormally_ gusty morning blocks a ring. _Example:_ limit 4 → gust cap ≈ 15 km/h.

**3.5 — Wind-proportional volume.** 100% in dead calm, ramping linearly down to a 75% floor at your limit; above the limit → skip. The loudness tells you how good the badminton weather is before you open your eyes. _Example:_ half your limit → 87.5%; at your limit → 75%.

**3.6 — The check cascade.** Wind is checked before the alarm — **T−1h, −30m, −15m, −10m, −5m, −2m, −1m, T−0**. Far checks use the hourly _forecast_; within 15 min it uses _current_ wind; latest successful check wins. Then **it keeps retrying every minute to +30 min after _any_ skip** (windy, gusty, or no-data), and **rings late if the wind drops** in that window. The skip is held **provisional** meanwhile: at T it posts a **"still checking until 6:30" heads-up** (the reason so far + the deadline); if the wind drops it **rings late** and the heads-up simply stays put, else at the cap a **separate** final skip card is posted alongside it (its own notification id, so it alerts afresh rather than quietly overwriting the heads-up) — using the **last _known_ reason**, so a blip at the cap still says "windy", not "couldn't check". **A ring is final (never retried).** If the app first runs only _after_ the +30m cap (e.g. iOS woke it late), the missed occurrence is still finalised from the last-known state — a committed ring logs "rang", otherwise **one** skip card + history row (never silently dropped, never a heads-up). _Example:_ windy at 06:00 → heads-up "too windy · checking until 06:30"; calm at 06:07 → rings; still windy at 06:30 → "skipped — windy" card. Forecast lookups are keyed in **UTC**, so a court in another timezone reads the right hour. _(The scheduled ladder runs on Android exact wakeups; on iOS it's opportunistic via BGAppRefresh — see the platform split below.)_

**3.6a — After an occurrence is finalised, the cascade rolls straight into the next one (2026-07-19).** Logging a ring or a capped skip doesn't end the pass: the same evaluation immediately evaluates the NEXT occurrence — pre-arming its ring while the forecast is calm (vital on iOS, which may get no background slot before T) and booking its first ladder check (vital on Android, where checks only ever reschedule themselves — previously the cascade slept until the next manual app open). Mid-ring, only the next check is booked (touching the ring's scheduler id would silence it).

**3.7 — Fail-safe = don't ring, but always explain (trust mechanism).** Windy → no ring; gusty → no ring; API/network dead → no ring. **Every** skip leaves an audible notification + a history entry, and **every outcome shows all four numbers** — "wind 3 (≤4) · gusts 16 (≤15) km/h". A skipped alarm is never confusable with a broken one. _(Fail-silent-with-a-card is a locked decision, chosen over fail-loud.)_

**3.8 — History is an immediate, append-only event log (2026-07-19, revised 2026-07-20).** Every ring and skip is logged with the wind that caused it and the **limits in force at that time** (so an old row still reads correctly after you change a limit). A row is anchored to the alarm's time and **always** shows the **wind-check time** behind it — "· checked HH:MM" (last successful reading; e.g. a 06:00 ring on a 22:00 check), or "· last tried HH:MM" for a no-data skip (its last attempt, since nothing was read) — as reinforcement the result came from a real check. History mirrors the notifications, row for row: the moment T is missed, the heads-up's **snapshot row** is written (marked "watching until 06:30", later "watched until 06:30" — retries never touch it), and the **final outcome** — the cap's skip, or a late ring — is a **separate second row**. Both stay forever; dismissing a notification can never erase the story, and nothing is overwritten. Home no longer dumps the newest row permanently (2026-07-22): while a snapshot window is still open **and** that occurrence is still being checked (no final row yet; alarm still enabled; live `CheckState` still targets that `alarmAt`) it shows a live `● Still checking wind · until HH:MM` cue (tap → history) — clears on late ring / delete / disable / toggle that discards the occurrence; otherwise home stays clean. _Example:_ windy at 06:00, calm at 06:07 → two rows: "Skipped · … · watched until 06:30" below "Rang (vol. …) · checked 06:07".

**3.8a — Orphan history is pruned on load (2026-07-22).** Deleting a court already sweeps its log, but a background isolate mid-check can land a row just after that sweep. Every load drops rows whose court is gone (including when the court list is empty). No court-less entry can linger on screen.

**3.9 — A ring is never silenced by opening the app, and never lost from history.** If a ring is sounding and you open the app, it keeps ringing (never cancelled or relabelled) — and it's logged "rang" **at that very moment**, while still audible, not when you stop it (2026-07-19). A ring that already fired is recorded as "rang" even if you open the app much later, or the wind has since risen. And a fired-but-not-yet-logged ring survives everything: editing the alarm, toggling it off, or deleting it finalises the "rang" row **before** the cascade state is discarded (this was the device-caught "reput" bug — an edited alarm's ring used to vanish from history forever). _Example:_ rings 06:00 on a calm forecast; you open the app at 06:50 in a fresh gust → history says **rang**, not skipped.

**3.10 — Courts: add / dedup / delete.** Add via GPS/search; a court within **~100 m** of an existing one is rejected (same spot). Deleting a court also **deletes its alarms _and_ its history log**, behind a confirmation that names both counts (e.g. "2 alarms use Home Court and will be deleted too, along with 5 history entries. Continue?"). **Every history row carries its `courtId`** (not just the alarm id), so deleting a court removes its _entire_ log — including rows from alarms that were deleted individually earlier. No orphaned history can linger.

**3.11 — Default max-wind is 6** (most lenient — rings most readily; tighten to 5 or 4 if you're picky). Alarms saved under the retired 1–3 settings migrate up to **4**. _Why only 4–6:_ below 4 the gust cap would fall under the ~12–15 km/h near-surface gust baseline, so those settings would almost never ring — dropped rather than propped up with a magic constant.

**3.12 — Sound.** Bundled tone, or (Android) a device system alarm sound; on iOS AlarmKit (no volume knob) the wind-ramp maps to pre-rendered loudness variants.

**Nivaat platform split — this is the important one:**

- **Ring delivery** → same as Arunoday (iOS min 26: AlarmKit; Android: `alarm` package).
- **Background wind checks:**
  - **Android:** _exact_ wakeups (AlarmManager) — the cascade ladder runs at (near) its exact times. Reliable, full cascade **while charging** (no Doze). Off charger, Doze rate-limits `allowWhileIdle` alarms to ~1 per 9 min, so Nivaat asks **once** at first launch for a battery-optimization exemption ("Unrestricted") to keep the network checks flowing.
  - **iOS:** **no exact background wakeups.** The cascade leans on two opportunistic triggers — a periodic **BGAppRefresh** (~30 min, usage-driven/daytime) **and** a **BGProcessingTask** whose `earliestBeginDate` is nudged to the next cascade rung (idle window, charging-or-not, network required) so a granted wakeup lands near T instead of being burned early — plus app-open/resume evaluations. iOS still decides _if/when_ either runs (the date is a **floor, not a schedule**), so the exact T−0 live re-check may not run. **Known v1 limitation** — the reliable-iOS answer is "Bedside mode" (a foreground OLED clock that does a true ring-time check) in v2.
  - _Consequence example:_ on iOS, if the evening forecast was calm the ring fires; if the wind rose overnight and no background check ran to catch it, it may **ring anyway** (the app errs toward ringing, and history records it truthfully). On Android the T−0 check catches that change and skips.
- **Skip notification** → audible on both; needs the notification permission (1.4).

---

## 4. Cross-cutting locked decisions (confirm these too)

**4.1 — No snooze** in either app (Arunoday's +1h ritual / just getting up covers it).

**4.2 — Units: metric km/h; English UI.**

**4.3 — Nivaat fail-silent + card**, not fail-loud on API error.

**4.4 — No server/push backend in v1** (needs a paid Apple account + infra) — everything runs on-device; the rolling window + app-opens are the reliability net, with a background top-up planned for v2.

**4.5 — GPS is one-shot at add-time only**; never background, never at alarm time.

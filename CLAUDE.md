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

## Workflow

- Samyak prefers: TLDR-first answers, simple language with examples, data-verified claims, small focused iterations during implementation.
- Commit checkpoints; he reviews diffs. Don't push anywhere without being asked.

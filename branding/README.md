# Branding

App-icon candidates, generated in-repo by `tools/make_icons.py` (numpy SDF
renderer — same idea as `tools/make_sounds.py`: exact `AppPalette` colours,
no licence baggage, regenerable forever).

**All three candidates per app SHIP (2026-07-20)**: the launcher icon is
switchable from each app's Settings (`core/app_icon` MethodChannel — Android
activity-aliases, iOS alternate icons). Candidate 1 is the default.

## The candidates

Open `icons/arunoday-preview.png` / `icons/nivaat-preview.png` — squircle-
masked on a launcher-dark background, in file order (1→3 left to right).
The `icons/<app>/*.png` files are the full-bleed 1024×1024 sources.

**Arunoday** (dawn amber `#FFB067`) — Settings labels in quotes:

- `a1-horizon` — "Horizon" (default): half sun on the horizon, the literal
  *arunoday*.
- `a2-first-rays` — "Rays": classic sunrise glyph; most instantly legible.
- `a3-dawn-dot` — "Dawn": sun clear of the ground line; most abstract.

**Nivaat** (wind blue `#6FB7EC`):

- `n1-shuttle` — "Shuttle" (default): line-drawn shuttlecock; says badminton
  in one glance.
- `n2-calm` — "Calm": wind gusts fading out, the *nivaat* itself.
- `n3-shuttle-badge` — "Crest": filled shuttlecock in a thin ring.

## Regenerating

`python3 tools/make_icons.py` refreshes this folder (candidates + previews);
add `--apply` to also rewrite the real launcher assets in both apps: Android
adaptive mipmaps (`ic_launcher*`, foreground = the icon at 0.80 on its own
gradient so the adaptive crop never clips a motif), iOS single-size
`AppIcon`/`AppIconTwo`/`AppIconThree` appiconsets, and the 256px Settings
thumbnails (`apps/<app>/assets/icons/`). Uses macOS `sips` for resizes.

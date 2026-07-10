# alarm-apps

Two minimal, pitch-black alarm apps. One Flutter monorepo.

## 🌄 Arunoday (अरुणोदय)
Wakes you at **civil dawn** — every day, at your location's real dawn, like humans woke for millions of years. Dynamic wake, fixed bedtime, computed so you naturally sleep ~7h in summer and ~9h in winter.

## 🌬️ Nivaat (निवात)
The badminton alarm. Rings **only if the wind at your court is low enough to play** — and the calmer the morning, the louder it rings. *"yathā dīpo nivāta-stho neṅgate"* — like a lamp in a windless place that doesn't flicker (Gita 6.19).

## Structure

```
packages/core     shared logic: solar math, sleep planner, wind engine, Open-Meteo, theme
apps/arunoday     dawn alarm app
apps/nivaat       wind alarm app
```

## Development

```sh
cd packages/core && flutter test        # all business logic is tested here
cd apps/arunoday && flutter run
cd apps/nivaat   && flutter run
```

See `SPEC.md` for the full locked v1 specification and the research behind every number.

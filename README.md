# Moon Phase Astro

An analog watch face for the **Garmin Venue 3 / Venue 3S** that shows the real
current moon phase, the day of the month, and your heart rate — on a pure-black,
AMOLED-friendly dial with a rainbow second hand.

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform: Connect IQ](https://img.shields.io/badge/platform-Garmin%20Connect%20IQ-007cc3.svg)
![Devices: Venu 3 / Venu 3S](https://img.shields.io/badge/devices-Venu%203%20%2F%20Venu%203S-333.svg)

<p align="center">
  <img src="screenshots/1.png" alt="Moon Phase Astro watch face" width="360">
</p>

## Features

- **Real moon phase** — a warm off-white moon subdial at 6 o'clock, shaded as a
  sphere: a crisp terminator with a smooth limb-darkening gradient toward the
  edge, and lunar maria clipped by the terminator so they appear and vanish
  correctly through the month. The math is on-device (`source/MoonPhase.mc`).
- **Eclipses** — the moon turns copper during a lunar eclipse and shows a corona
  during a solar one. Every eclipse from 2025 to 2045 is built in from the NASA
  catalogue; past that the face computes them on the watch. Optionally gated on
  whether the eclipse is actually above your horizon.
- **Full numerals** — bright white hour numerals, plus grey five-second numerals
  set radially on the outermost ring, sharing that ring with the tick dots.
- **Seven hand styles** — Dauphine, Baton, Syringe, Skeleton, Breguet, Alpha and
  Sword, switchable from the phone without a rebuild.
- **Spectrum second hand** — its hue sweeps the full spectrum once per minute,
  trailing a comet tail in one of three styles.
- **Backgrounds** — a fixed starfield of layered star sprites, or the star
  pattern of a zodiac constellation (stars only, or joined by lines).
- **Daily rainbow wave** — once a day a band of spectrum washes outward across
  the whole face.
- **Complications** — a classic `FRI 27` date at 3 o'clock, heart rate with a
  heart glyph at 9 o'clock.
- **Always-on aware** — in low-power mode the colour and ornamentation drop to a
  dim wireframe, and the whole face drifts a few pixels on a slow cycle to protect
  against burn-in.
- **Configurable** — everything above is a setting in Garmin Connect; see
  [Settings](#settings). Colours live in `source/Theme.mc`.

## Settings

Set these in **Garmin Connect > the watch face > Settings**, or in the simulator
under **Settings > Watchface Settings**.

| Setting | Default | Notes |
|---|---|---|
| Hand style | Dauphine | Seven silhouettes |
| Comet trail | Classic | Classic single hue, spectrum trail, or spectrum ring |
| Comet crosses the numerals | off | On, the trail runs unbroken through the five-second marks |
| Show orbit ring | off | The faint dotted circle inside the hour numerals |
| Background | Starfield | Or a zodiac constellation, with or without lines |
| Zodiac sign | Auto | Auto follows the current sun sign |
| Star density | Normal | Off / sparse / normal / dense |
| Show hour numerals | on | |
| Show second numerals | on | |
| Daily rainbow wave | on | Fires on the first wrist raise after the set hour |
| Rainbow wave hour | 0 | |
| Eclipse effects | on | |
| Show eclipses | Always | Or only when above your horizon (uses last known GPS, never requests a fix) |
| Eclipse data | Built in through 2045 | Or always calculate on the watch |

There are also diagnostic read-outs (last position used, eclipse data status) and
test switches (force an eclipse, shift the astronomy clock, override the position,
fire the rainbow wave every minute). See [`docs/eclipse-test-dates.md`](docs/eclipse-test-dates.md).

## Tuning the look in code

The proportions are deliberately gathered into two blocks of constants:

| What | Where |
|---|---|
| Ring radii, second-numeral font and size, hour-numeral font, tick dot sizes | `TUNING` block at the top of `source/Dial.mc` |
| Date and heart-rate fonts, heart icon size, complication positions | `TUNING` block at the top of `source/MoonPhaseAnalogView.mc` |
| Moon gradient smoothness and limb darkening | `LEVELS`, `STEP_PX`, `LIMB_FLOOR` in `source/MoonDial.mc` |
| All colours | `source/Theme.mc` |

The five-second numerals use `FONT_XTINY`, the smallest built-in font. To go
smaller than that, lower `Dial.SEC_LABEL_SCALE` — the labels are pre-rendered
once and blitted through an affine transform, so the scale is free at runtime.

## Requirements

- A **Garmin Venu 3 (45 mm)** or **Venu 3S (41 mm)** watch.
- To build from source: the [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/)
  (min API level 5.2.0) and a working Java runtime (Temurin/Adoptium JDK 17 or 21
  recommended).

## Build

The included PowerShell script locates the Connect IQ SDK and a working Java
runtime, then produces signed `.prg` files for both watch sizes in `bin\`:

```powershell
.\build.ps1              # release builds for venu3 and venu3s
.\build.ps1 -Debug       # debug builds (for the simulator)
```

> Note: this project ships build scripts that work around a broken Oracle
> "javapath" Java stub by calling the compiler with a known-good JRE directly. If
> your `java` on PATH already works, the scripts use it automatically.

## Preview in the simulator

```powershell
.\run-simulator.ps1            # or:  .\run-simulator.ps1 venu3s
```

This builds the face and opens it in the Connect IQ simulator, where you can use
**Settings > Time** and the power-mode toggles to watch the moon phase, the
spectrum second hand, and the always-on look.

## Install on your watch

Build the `.prg` that matches your watch, then copy it into the watch's
`GARMIN\APPS\` folder over USB (MTP). Full step-by-step instructions — including
the Garmin Express gotcha and on-watch debugging — are in [`INSTALL.md`](INSTALL.md).

## Project layout

| File | Purpose |
|------|---------|
| `manifest.xml` | App metadata; targets venu3 + venu3s, min API 5.2.0 |
| `monkey.jungle` | Build configuration |
| `source/MoonPhaseAnalogApp.mc` | App entry point |
| `source/MoonPhaseAnalogView.mc` | Layout, frame orchestration, complications |
| `source/Dial.mc` | Second track, numerals, comet, starfield, zodiac |
| `source/Hands.mc` | The seven hand silhouettes |
| `source/MoonDial.mc` | Moon shading and the eclipse looks |
| `source/MoonPhase.mc` | Lunar phase and eclipse detection (no UI) |
| `source/EclipseData.mc` | Generated: 93 eclipses, 2025-2045 |
| `source/SkyPosition.mc` | Solar position and the GPS visibility gate |
| `source/Zodiac.mc` | Star patterns for the 12 constellations |
| `source/RainbowWave.mc` | The daily wave |
| `source/Settings.mc` | Cached, guarded property access |
| `source/Complications.mc` | Date + heart rate lookups |
| `source/Theme.mc` | Colour palette + colour helpers |
| `source/EclipseTest.mc` | On-watch unit tests (`:test` build only) |
| `resources/` | App name, launcher icon, settings + properties |
| `build.ps1` | One-command build for both sizes |
| `run-simulator.ps1` | Build + open in the simulator |
| `tools/` | Data generators, math validator, test runner |
| `docs/` | Eclipse catalogue and test script |
| `INSTALL.md` | Detailed sideloading guide |

## Tests

```powershell
.\tools\run-tests.ps1              # on-watch unit tests in the simulator
.\tools\check-eclipse-math.ps1     # validate the computed eclipse fallback
```

`source/EclipseData.mc` is generated — edit `docs/eclipse-events.tsv` and re-run
`tools\gen-eclipse-data.ps1` (and `tools\gen-eclipse-doc.ps1`) rather than
editing it by hand.

## License

Released under the [MIT License](LICENSE). Copyright (c) 2026 Anton Velmozhnyi.

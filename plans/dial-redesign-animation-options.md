# Moon Phase Astro — dial redesign, animation & options

## Context

`MoonPhaseAnalogView.mc` currently renders a sparse dial: one hardcoded `"12"` numeral,
a 60-dot tick ring, 12 fixed 1px stars, a flat scanline moon, and a single hollow-blade
hand shape used for both hands. Everything is procedural Monkey C on a Garmin Venu 3 /
3S (CIQ `minApiLevel 5.2.0`), so every element is freely re-drawable — there are no
bitmap assets except the launcher icon.

The user wants the dial to carry far more information and personality:

- Full **hour numerals** (bright white) and **5-second numerals** (grey, radially
  oriented, outermost) instead of the lone `"12"`.
- A classic **`FRI 27`** date instead of the bare number.
- **Bigger heart rate** — larger glyph and larger font.
- A **hand-style selector** so the final silhouette can be chosen by eye in the
  simulator/on-watch rather than decided up front.
- **Two animated/state effects**: a red **eclipse moon** (astronomical, both lunar and
  solar) and a once-per-day **rainbow wave** washing outward across the face.
- Richer **star sprites** and **spherical shading** on the moon.
- A second **comet-trail mode** (reveal-newest / hide-oldest, dots coloured from around
  the wheel), with the current trail kept as an option.

Intended outcome: a denser, more alive face that stays AMOLED-black and always-on-safe,
with the subjective choices (hands, comet, effects) exposed as Connect IQ settings so
they can be flipped without a rebuild.

### Two constraints worth stating up front

1. **Animation ceiling is 1 frame per second.** Garmin calls `onUpdate` on a watch face
   once per second while awake. The rainbow wave is therefore a ~12-frame sequence, not
   a smooth 60fps sweep. This is a platform limit, not an implementation choice.
2. **Eclipse timing is approximate.** Mean-element node math gives eclipse dates
   reliably and maxima to within a few hours — plenty for a day-long visual state.
   Location-gating the effect is an *option* (§9a): with a last-known GPS position the
   face can check whether the eclipsed body is actually above your horizon, and it falls
   back to showing the eclipse globally when no position is available.

---

## Architecture

`MoonPhaseAnalogView.mc` (380 lines) would roughly triple. Split the drawing into
modules, keeping the view as the orchestrator:

| File | Role |
|---|---|
| `source/MoonPhaseAnalogView.mc` | Layout metrics, `onUpdate` orchestration, low-power state (existing `scaled()`, `rot()`, `_ox/_oy` burn-in shift stay here) |
| `source/Settings.mc` | **new** — cached reads of `Application.Properties`, safe defaults |
| `source/Hands.mc` | **new** — 7 hand silhouettes + `drawHand` (replaces `handPoints`/`drawHand`, view lines 339–367) |
| `source/Dial.mc` | **new** — tick ring, hour numerals, radial second numerals, starfield, orbit ring, comet trail (replaces `drawTicks`/`drawTwelve`/`drawStarfield`/`drawOrbitRing`) |
| `source/MoonDial.mc` | **new** — moon disc with limb darkening + eclipse look (replaces `drawMoon`/`drawCraterSpans`; `CRATERS` const moves here) |
| `source/RainbowWave.mc` | **new** — wave scheduling, progress, and a `tint(color, x, y)` helper every draw call routes through |
| `source/MoonPhase.mc` | extend — draconic-node math, `eclipseAt()` |
| `source/Complications.mc` | extend — `dayOfWeekShort()` |
| `source/Theme.mc` | extend — new palette entries |
| `source/MoonPhaseAnalogApp.mc` | add `onSettingsChanged` to invalidate the settings cache + `requestUpdate` |

Reuse `Theme.hsvToColor` (`Theme.mc:34`) for every hue computation — the rainbow wave,
the spectrum comet, and the second hand all share it. Reuse the existing
`MoonPhase.fmod` (`MoonPhase.mc:44`) for the node math.

---

## 1. Radial layout (the crowding problem)

Adding two numeral rings to a dial that already has ticks, a comet, two complications
and a moon subdial needs one agreed radial stack. All values are fractions of `_radius`:

```
0.900   second track      one shared ring — see below
0.760   hour numerals     1–12         upright, FONT_SMALL, white     (Theme.NUMERAL)
0.600   orbit ring        unchanged
0.46    date  (x +0.46)  /  heart rate (x −0.46)  /  moon (y +0.46)
```

**The second track is a single ring at `0.90R`.** The tick dots and the 5-second
numerals share it: the 12 positions that are multiples of 5 draw a radial numeral
(`60, 05, 10, … 55`, grey, `FONT_XTINY`) *instead of* a dot, and the other 48 positions
draw the small dim dot as today. Nothing is drawn twice and nothing overlaps.

Consequences for the existing code in `drawTicks` (`MoonPhaseAnalogView.mc:137–172`):

- The `i % 15 == 0` major-dot branch (line 143) goes away — 0/15/30/45 are now numerals.
  The quarter emphasis moves onto those four numerals, which render a step brighter than
  the other eight.
- The comet trail also rides this same ring. When the trail passes a numeral position it
  **tints the numeral** in the trail colour and alpha rather than drawing a dot over it,
  so the comet reads as continuous — glowing dots between glowing numbers.

Hand lengths change to suit: hour `0.48`, minute `0.84` (sweeps across the hour numerals
and stops just inside the second track), second `0.86`.

## 2. Second numerals — radial text

`dc.drawText` cannot rotate. API 5.2 has `Graphics.AffineTransform` + `dc.drawBitmap2`,
so:

- In `onLayout`, render each of the 12 labels (`"05"…"55"`, `"60"` at top) once into a
  small `Graphics.createBufferedBitmap` using `FONT_XTINY` on a transparent palette;
  cache the 12 handles. Generated and cached once — never re-rendered per frame.
- Because the comet can tint a numeral, cache **three** tone variants per label (normal,
  quarter-bright, and a white master the comet colour multiplies against) rather than
  re-rasterising when the trail arrives. Palette entries make this cheap.
- Each frame, blit with `drawBitmap2(..., {:transform => AffineTransform})` composed as
  translate-to-position × rotate-by-angle × translate-to-glyph-centre, so the label's
  baseline points outward along its radius.
- Guard with `dc has :drawBitmap2`; fall back to upright `drawText` if absent (it will
  not be on venu3/3s, but the guard costs nothing and mirrors the existing
  `dc has :setAntiAlias` pattern at `MoonPhaseAnalogView.mc:80`).

Memory: 12 buffers of roughly 30×20px at 8bpp ≈ 7 KB. Fine.

Hidden in low power (burn-in + they mean nothing without a second hand).

## 3. Hour numerals

Loop 1–12 at `0.78R`, upright, `FONT_SMALL`, `Theme.NUMERAL` = pure white so they read
brighter than the grey seconds. Dimmed to `Theme.READOUT_DIM` in low power. Skip the
numeral at 6 o'clock if it fouls the moon subdial (moon top edge sits at `0.31R`, so it
clears — verify visually in the simulator).

Setting-gated: `ShowHourNumerals`, `ShowSecondNumerals` (both default on).

## 4. Date — `FRI 27`

`Complications.dayOfWeekShort()` from `Gregorian.info(Time.now(), Time.FORMAT_MEDIUM)`
`.day_of_week`, uppercased and truncated to 3. `drawDay` renders it as two runs on one
baseline: small grey `FRI` + `FONT_NUMBER_MEDIUM` white `27`, measured with
`dc.getTextWidthInPixels` so the pair is centred on `x = _cx + 0.46R`.

## 5. Heart rate — bigger

In `drawHeartRate` (`MoonPhaseAnalogView.mc:192`): `hs` goes `scaled(5)` → `scaled(9)`,
the glyph gains a proper cusp notch between the two lobes, and the number goes
`FONT_TINY` → `FONT_NUMBER_MEDIUM` so it matches the date's weight. Re-centre the
icon/number stack around `_cy` after the size change.

## 6. Hand styles (7, selectable)

Replace `handPoints` with `Hands.silhouette(style, kind, ca, sa, len, hw, tail)` — a
switch returning the point list, and a matching `Hands.draw` that knows whether each
style is filled, hollow, or filled-with-facet. Styles:

| # | Style | Treatment |
|---|---|---|
| 0 | **Dauphine** | Solid tapered diamond, centre facet line in a second tone |
| 1 | **Baton / Bauhaus** | Flat rectangle, squared ends, bright lume block near the tip |
| 2 | **Syringe / Pencil** | Narrow shaft flaring to a spear point |
| 3 | **Skeleton** | Current hollow blade, thinner outline and cleaner taper |
| 4 | **Breguet** | Slim shaft with a pierced circle (pomme) near the tip |
| 5 | **Alpha** | Broad triangular arrow, wide shoulders — high legibility |
| 6 | **Sword** | Long straight-edged blade tapering to a fine point |

Selected by the `HandStyle` property. All 7 share the existing `rot()` helper
(`MoonPhaseAnalogView.mc:371`) so the burn-in offset keeps working, and all shrink to
outline-only in low power (the existing `spineColor == null` convention).

## 7. Star sprites

`_buildStars` (`MoonPhaseAnalogView.mc:100`) replaces its 12 hardcoded seeds with a
small deterministic LCG generating ~28 stars, each with a tier and a brightness — same
field every boot, but denser and varied. `Dial.drawStarfield` draws by tier:

- **tier 0** — 1px dot (the majority)
- **tier 1** — centre dot plus four 2px orthogonal spikes (a small sparkle)
- **tier 2** — brighter centre plus four 3px spikes and four dimmer 1px diagonals

Two or three tier-2 stars twinkle: brightness modulated by `clock.sec` so they pulse on
the free 1 Hz redraw. Density controlled by a `StarDensity` property (off / sparse /
normal / dense). Starfield stays awake-only, as today.

## 7a. Zodiac constellation background (alternative to the starfield)

A `Background` property replaces the random starfield with an actual zodiac
constellation:

| Value | Background |
|---|---|
| 0 | **Starfield** *(default)* — §7 |
| 1 | **Zodiac — stars only** |
| 2 | **Zodiac — stars + connecting lines** |

**Astronomy only — no figurative artwork.** The background is the constellation's main
stars and nothing else: no ram, crab, lion, scales or any other sign glyph or character
illustration, and no zodiac symbol. Mode 2 adds only the plain connecting lines between
those stars.

New `source/Zodiac.mc` holds the data: for each of the 12 signs, an array of stars as
`[x, y, magnitude]` in normalised `-1..1` dial coords (positions traced from the real
constellation's principal stars, then fitted to a circle), plus an array of `[i, j]`
index pairs for the conventional connecting lines. Only the main pattern stars are
included — roughly 5–12 per sign, not the full catalogue — so the shape stays legible at
390px.

Rendering, in `Dial.drawZodiac`:

- Fit the pattern to `0.80R` and centre it, then nudge it up slightly so the busiest part
  clears the moon subdial at the bottom (`y +0.46R`).
- Stars draw through the **same tiered sprite renderer as §7** — magnitude maps onto the
  tier, so the brightest few get the full 4-point sparkle and the faint ones stay 1px
  dots. Same twinkle on the brightest two.
- Mode 2 draws the connecting lines first, underneath, as 1px lines in a new
  `Theme.ZODIAC_LINE` (very dark, around `0x24242C` — present but never competing with
  the hands). `setPenWidth(1)`, anti-aliased.

Which sign is chosen comes from a `ZodiacSign` property:

- **Auto** *(default)* — the current sun sign, from a simple date-range table against
  `Gregorian.info`. The background then changes with the season, which fits the
  astronomical theme.
- **Aries … Pisces** — pinned to your own birth sign.

Awake-only and rainbow-wave-tinted, exactly like the starfield it replaces, so no other
code path changes.

## 8. Moon shading

Extend the existing scanline loop in `drawMoon` (`MoonPhaseAnalogView.mc:237–257`) —
the same lit-span geometry, but each span is drawn in three passes instead of one:

1. Full span in `MOON_LIT`.
2. **Limb darkening** — the outer ~15% of the span nearest the limb overdrawn in
   `MOON_LIMB_DARK`, and the outermost ~6% in `MOON_LIMB_DARK2`. This is what makes it
   read as a sphere rather than a disc.
3. **Terminator softening** — a 2–3px band on the terminator side in an intermediate
   tone, so the day/night edge isn't a hard cut.

Maria (`drawCraterSpans`) draw after pass 1 and before the darkening passes, so they
darken with the limb too. The existing bright-limb arc (lines 260–269) stays but is
narrowed to the lit outer edge only.

## 9. Eclipses (red moon)

Detection is a **lookup table first, computed fallback second**. Mean-element math alone
finds eclipse seasons reliably but misclassifies events sitting near the ecliptic limit
and can be hours out on the maximum, which is exactly the kind of error that shows up as
"the moon went red on a normal night". Published eclipse data is exact and tiny, so the
table is the primary source.

### 9.1 `source/EclipseData.mc` — exact events, 2025 → 2045

Every solar and lunar eclipse in that span (~90 events) transcribed from published data,
stored as **three flat parallel arrays** rather than an array of arrays — nested arrays
carry per-object overhead in Monkey C and this needs to stay cheap:

```
DAYS[]     Number   days since 2000-01-01 of the maximum   (ascending, ~9100 … 16800)
MINUTES[]  Number   minute of day, UTC, of the maximum     (0 … 1439)
TYPEMAG[]  Number   type * 1000 + round(magnitude * 100)
```

Type codes: `0` partial solar, `1` annular, `2` total solar, `3` hybrid, `4` penumbral
lunar, `5` partial lunar, `6` total lunar. Total footprint roughly 270 Numbers — about
1–2 KB, negligible against the watch-face budget.

`EclipseData.lookup(epochSeconds)` binary-searches `DAYS` for an entry whose maximum
falls within the effect window (±6 h), and returns type + magnitude + exact maximum, or
`null`. Deterministic and exactly testable.

### 9.2 Computed fallback, outside the table

For any date before 2025 or after 2045 the face falls back to the mean-element math, so
it degrades gracefully instead of simply going dead in 2046. Add to `MoonPhase.mc`:

```
DRACONIC   = 27.212220817        // node-to-node month
INCL       = 5.145               // lunar orbit inclination, degrees
REF_NODE   = <JD of a known ascending-node passage>
```

`eclipseAt(epochSeconds)` computes the argument of latitude
`F = fmod(jd - REF_NODE, DRACONIC) / DRACONIC` alongside the existing synodic phase from
`fractionAt`, derives the Moon's approximate ecliptic latitude
`β ≈ INCL * sin(2πF)`, and applies the classical ecliptic limits:

- **`:solar`** when phase ≈ 0.0 (new moon) and `|β| < 1.6°` — certain below 1.4°.
- **`:lunar`** when phase ≈ 0.5 (full moon) and `|β| < 1.05°` — certain below 0.9°.
- `:magnitude` scales with how far inside the limit the event sits.

Below a magnitude threshold the result is suppressed, so faint penumbral events (which
look like nothing in the sky) don't turn the moon red.

`MoonPhase.eclipseAt` is the single entry point: it consults `EclipseData.lookup` first
and only computes when the timestamp is outside the table's range.

### 9.3 Telling the user which one is in play

A read-only `EclipseDataInfo` property, written by the face in the same way as
`LastFixInfo` (§9a), reports the data source in the settings screen — e.g.
`exact data through 2045-12-31 · currently: exact` or
`· currently: estimated (beyond table)`. The `EclipseEffects` setting's own description
string in `settings.xml` carries the same note, so the 2045 horizon is visible without
digging.

Rendering in `MoonDial`:

- **Lunar** — the lit surface palette swaps to a copper/blood gradient
  (`ECLIPSE_RED` → `ECLIPSE_RED_DEEP`), the whole disc is lit (a lunar eclipse is a full
  moon), the limb-darkening passes stay, and a faint red glow ring is drawn outside the
  disc.
- **Solar** — the disc goes near-black with a thin white/pearl corona ring and a couple
  of soft radial streamers.

Gated by an `EclipseEffects` property (default on). Effect window ≈ ±6 h around the
computed maximum.

## 9a. Optional GPS visibility gate

New `source/SkyPosition.mc` with a standard low-precision solar-position routine
(~40 lines: days-since-J2000 → mean longitude → ecliptic longitude → declination →
local hour angle → altitude). From it:

- `sunAltitude(epochSeconds, latDeg, lonDeg)` in degrees.
- `moonAltitudeApprox(...)` — at a **lunar** eclipse the moon is by definition opposite
  the sun, so `moonAlt ≈ -sunAlt` is accurate to a degree or two. That is enough to
  answer "is the moon above my horizon".

Position comes from `Toybox.Position.getInfo()`, which returns the **last known** fix
without powering the GPS — no battery cost and legal from a watch face. It requires
`<iq:uses-permission id="Positions"/>` in `manifest.xml` (currently
`<iq:permissions/>` is empty), which means one permission prompt at install.

New `EclipseVisibility` property, list:

| Value | Behaviour |
|---|---|
| 0 | **Always show** *(default)* — pure astronomy, position never read |
| 1 | **Only when visible here** — gate on the GPS check below |

Gate logic for mode 1:

- `Position.getInfo()` is `null`, has no `position`, or its `accuracy` is
  `Position.QUALITY_NOT_AVAILABLE` → **fall back to always-show**. Never hide an
  eclipse just because the watch has no fix.
- **Lunar:** show only if the moon is above the horizon at the eclipse maximum, i.e.
  `sunAltitude < -0.5°`.
- **Solar:** show only if the sun is above the horizon at maximum
  (`sunAltitude > -0.5°`). This is *necessary but not sufficient* — true solar-eclipse
  visibility depends on the narrow path of totality, which mean-element math cannot
  reproduce. So mode 1 for a solar eclipse means "an eclipse is happening and the sun is
  up where you are", and the corona is rendered at reduced intensity to signal that it
  may be partial or not visible at all. Documented in the README and the setting's
  description string.

**Surfacing the cached position (never on the dial).** The face must not print
coordinates on the watch face itself. Instead the last position it actually used is
written back into three read-only properties, so it shows up in the **settings** screen —
in Garmin Connect / Connect IQ on the phone, and in the on-device watch-face settings
menu on the Venu 3:

| Property | Example |
|---|---|
| `LastFixLat` | `59.4370` |
| `LastFixLon` | `24.7536` |
| `LastFixInfo` | `59.4370, 24.7536 · 2026-08-22 14:03 · good` |

`LastFixInfo` is the useful one — a single human-readable line with the coordinates, the
local timestamp of the fix the face read, and the `Position.Info.accuracy` bucket
(`good` / `usable` / `poor` / `none`). When no position is available it reads
`no position — showing all eclipses`, which makes the fallback state (§9a gate logic)
visible rather than mysterious.

Mechanics and caveats:

- Written with `Application.Properties.setValue` from `SkyPosition`, **throttled**: only
  when the position moves more than ~5 km or the previous write is over an hour old.
  Watch faces run every second and properties live in flash, so an unthrottled write
  would be wasteful.
- Declared in `settings.xml` as plain text entries labelled *"Last position used
  (read-only)"*. Connect IQ has no true read-only control, so the fields are technically
  editable; the face ignores whatever is typed and overwrites on the next update. The
  label says so.
- The phone only shows the value it last synced from the watch, so it can lag behind by
  a sync cycle. Not a problem for a diagnostic readout, but worth knowing when checking
  it.
- Gated behind `EclipseVisibility = 1`; in *always show* mode nothing is read and the
  fields report `position not used`.

**Simulator testability** (this is the part that needs deliberate support):

- The CIQ simulator's **Simulation > Set Position…** feeds `Position.getInfo()`, so the
  gate can be exercised by pairing a position with **Settings > Time**.
- Because that path is fiddly, add two debug properties, `DebugLatitude` and
  `DebugLongitude` (floats, default `999` = unset). When both are set,
  `SkyPosition.currentPosition()` returns them instead of calling `Position.getInfo()`.
  That makes the gate testable deterministically — set Reykjavík vs. Auckland at a fixed
  eclipse timestamp and confirm one shows the red moon and the other doesn't, with no
  dependence on simulator position support.
- Add a `DebugEclipse` property (list: off / force lunar / force solar) that short-
  circuits `MoonPhase.eclipseAt` so the rendering can be tuned without hunting for a
  real eclipse date.
- In debug builds, `System.println` the decision each minute:
  `phase, F, eclipse type, magnitude, lat/lon, sunAlt, visible?` — so a failing gate can
  be diagnosed from the simulator console rather than by eye.

## 9b. Testing eclipses in the simulator

This has to be genuinely exercisable, not just theoretically correct, so the design is
built for it:

**Everything is driven by an explicit timestamp.** `MoonPhase.eclipseAt(epochSeconds)`
and `SkyPosition.sunAltitude(epochSeconds, lat, lon)` take the time as a parameter; the
view passes `Time.now().value()`. Nothing reads a hidden real-time clock. The CIQ
simulator's **Settings > Time** drives `Time.now()`, so **changing the simulator date is
all it takes** to move the face to any eclipse — the moon phase, the node math, the
visibility gate and the date complication all follow it consistently.

**Passing GPS alongside it.** Two independent routes, so a failure in one doesn't block
testing:

1. **Simulation > Set Position…** in the simulator feeds `Position.getInfo()` directly.
   This is the realistic path and also proves the `Positions` permission is wired up.
2. **`DebugLatitude` / `DebugLongitude` properties.** When both are set (default `999` =
   unset) `SkyPosition.currentPosition()` returns them and never touches
   `Position.getInfo()`. Deterministic, works even if simulator position support is
   flaky, and lets a date + coordinate pair be reproduced exactly from notes.

**A shifted astronomical clock, so normal time keeps running.** A
`DebugTimeOffsetDays` property (float, default `0`) is added to the epoch before it
reaches the astronomy code only. Set it to `+192.5` and the moon/eclipse state jumps to
an eclipse while the dial still shows the real current time — handy for checking that
the red moon composes correctly with a normal-looking face, and for scrubbing through
an eclipse hour by hour in fractional steps.

**A reference table, checked in.** `docs/eclipse-test-dates.md` is the human-readable
form of `EclipseData.mc` — the 2025–2045 events with UTC maxima and types — and doubles
as the manual test script. It also records the day-by-day sweep used to validate the
**fallback** math against the table: running `MoonPhase.eclipseAt`'s computed path over
all 20 years and diffing it against the exact entries is what catches a wrong `REF_NODE`
or a bad ecliptic limit, and it quantifies how much the fallback can be trusted past
2045. Near-term rows to spot-check by hand: 2026-02-17 (annular solar), 2026-03-03
(total lunar), 2026-08-12 (total solar), 2026-08-28 (partial lunar).

**Unit tests.** Monkey C's `(:test)` annotation runs under
`monkeydo <prg> <device> -t`. Add `source/EclipseTest.mc` asserting:

- `eclipseAt` returns `:lunar` at each known lunar maximum and `:solar` at each solar
  one — driven straight off the `EclipseData` table, so every one of the ~90 events is
  covered rather than a hand-picked few;
- it returns `null` at a set of control dates — ordinary full moons and new moons
  between eclipse seasons;
- `DAYS[]` is strictly ascending (a transcription typo in the table is the most likely
  failure mode, and binary search silently misbehaves without this check);
- the **fallback** path, forced on, agrees with the table on type for the large majority
  of events and never fires on the control dates;
- `sunAltitude` matches known sunrise/sunset for two reference cities to within a couple
  of degrees;
- the gate resolves *visible* at a night-side location and *not visible* at its antipode
  for one fixed lunar-eclipse timestamp.

This is what makes a date change in the simulator trustworthy rather than a guess.

**One gotcha to handle:** jumping the simulator date around would otherwise re-fire the
rainbow wave on every jump, since it triggers on "day differs from `lastWaveDay`". The
wave check ignores backwards day changes, and `WaveTestMode` is the intended way to
trigger it deliberately — so eclipse testing isn't drowned in rainbows.

## 10. Rainbow wave

`RainbowWave.mc` holds the state:

- On each awake `onUpdate`, if `EnableRainbowWave` and the local day differs from
  `lastWaveDay` in `Application.Storage` and the clock has passed `WaveHour`, latch a
  start timestamp and write `lastWaveDay`. Because the check runs on wake, a wave whose
  scheduled moment passed while the wrist was down fires on the next raise — you
  actually see it.
- Progress `p = (now - start) / 12.0` over 12 frames; a hue band of width ~0.22R
  travels from the hub to past the rim.
- `RainbowWave.tint(baseColor, x, y)` returns the base colour unless the point falls in
  the band, in which case it returns `Theme.hsvToColor(hue, s, v)` blended by distance
  from the band centre. Hue derives from the point's radius so the band itself is a
  spectrum. Every dial draw call (ticks, both numeral rings, stars, orbit ring, hands,
  complication text) routes its colour through this, so the wash crosses the whole face.
- Off entirely in low power. A `WaveTestMode` debug property fires it every minute so
  the effect can be tuned in the simulator without waiting a day.

## 11. Comet trail modes

All three modes ride the shared second track at `0.90R`, and in all three a trail
position that lands on a multiple of 5 lights the **numeral** in the trail colour
instead of drawing a dot (§1).

`CometMode` property, three values, current behaviour kept as the default:

0. **Classic** *(current)* — 8 dots behind the head, all in the head's hue, alpha fading
   `210 - k*24` (`MoonPhaseAnalogView.mc:161–171`).
1. **Spectrum reveal** — each of the 60 tick positions owns a fixed hue
   (`position/60 × 360°`). The head dot lights at full brightness in *its own* hue each
   second and the oldest dot in the trail goes out, so the colours are scattered around
   the circle rather than uniform.
2. **Spectrum ring** — all 60 dots always visible in their own hue but very dim, with
   the trail and head bright. The full wheel is faintly present at all times.

## 12. Settings plumbing

New `resources/settings/settings.xml` + `resources/properties.xml`:

| Property | Type | Default |
|---|---|---|
| `HandStyle` | list 0–6 | 0 (Dauphine) |
| `CometMode` | list 0–2 | 0 (Classic) |
| `ShowHourNumerals` | bool | true |
| `ShowSecondNumerals` | bool | true |
| `StarDensity` | list 0–3 | 2 (normal) |
| `Background` | list 0–2 | 0 (starfield) |
| `ZodiacSign` | list 0–12 | 0 (auto / current sun sign) |
| `EnableRainbowWave` | bool | true |
| `WaveHour` | number 0–23 | 0 |
| `EclipseEffects` | bool | true |
| `EclipseVisibility` | list 0–1 | 0 (always show) |
| `DebugEclipse` | list 0–2 | 0 (off) |
| `DebugTimeOffsetDays` | float | 0 (astronomy clock only) |
| `DebugLatitude` | float | 999 (unset) |
| `DebugLongitude` | float | 999 (unset) |
| `WaveTestMode` | bool | false |
| `LastFixLat` | float | written by the face (read-only readout) |
| `LastFixLon` | float | written by the face (read-only readout) |
| `LastFixInfo` | string | written by the face (read-only readout) |
| `EclipseDataInfo` | string | written by the face — data source + 2045 horizon |

`Settings.mc` reads them through `Application.Properties.getValue` inside a guard that
falls back to the default on any exception, and caches into module vars.
`MoonPhaseAnalogApp.onSettingsChanged` clears the cache and calls
`WatchUi.requestUpdate()`.

Label strings go in `resources/strings/strings.xml` alongside the existing `AppName`.

---

## Files to modify / create

**Modify:** `source/MoonPhaseAnalogView.mc` (orchestration + layout radii),
`source/MoonPhase.mc` (node/eclipse math), `source/Complications.mc` (`dayOfWeekShort`),
`source/Theme.mc` (palette), `source/MoonPhaseAnalogApp.mc` (`onSettingsChanged`),
`manifest.xml` (`Positions` permission), `resources/strings/strings.xml`,
`README.md` (features + new settings table + the solar-visibility caveat).

**Create:** `source/Settings.mc`, `source/Hands.mc`, `source/Dial.mc`,
`source/MoonDial.mc`, `source/RainbowWave.mc`, `source/SkyPosition.mc`,
`source/Zodiac.mc`, `source/EclipseData.mc` (2025–2045 event table),
`source/EclipseTest.mc` (`(:test)` unit tests),
`resources/properties.xml`, `resources/settings/settings.xml`,
`docs/eclipse-test-dates.md`.

## Verification

1. `.\build.ps1 -Debug` — must compile clean for both `venu3` and `venu3s`.
2. `.\run-simulator.ps1` then `.\run-simulator.ps1 venu3s` — confirm the layout holds at
   both 454px and 390px: the second track reads as one clean ring (numerals sitting
   exactly where their dots would have been, no doubled marks, even spacing at the small
   390px size), the hour numerals clear it, and `FRI 27` clears the `3` numeral.
3. In the simulator, cycle `HandStyle` 0→6 via **Settings > Watchface Settings** — the
   point of the selector is a side-by-side eyeball comparison; capture a screenshot of
   each for the final pick.
4. Cycle `CometMode` 0→2 and watch a full minute of second-hand sweep for each.
5. **Background:** step `Background` 0→2, and with zodiac selected step `ZodiacSign`
   through all 12 — confirm each pattern is recognisable **as a star pattern only** (no
   glyphs or figures anywhere), fits inside the hour numerals, clears the moon subdial,
   and that the connecting lines stay subordinate to the hands. Check *auto* picks the
   right sign for the simulator date.
6. **Rainbow wave:** enable `WaveTestMode` and watch it fire at the top of a minute;
   confirm 12 distinct frames and that ticks, numerals, stars and hands all tint.
7. **Eclipse rendering:** set `DebugEclipse` to *force lunar*, then *force solar*, and
   tune the red moon / corona look without needing a real date.
8. **Eclipse detection by date:** clear `DebugEclipse`, then walk
   `docs/eclipse-test-dates.md` using **Settings > Time**. For each row confirm the
   effect appears in the window and is absent on the control dates (ordinary full and
   new moons between eclipse seasons), and that the magnitude threshold suppresses faint
   penumbral events. Repeat a couple of rows using `DebugTimeOffsetDays` instead of the
   simulator clock, to confirm both time paths agree.
   Run the unit tests too: `monkeydo bin\MoonPhaseAstro-venu3.prg venu3 -t` — all
   `EclipseTest` cases must pass.
   Finally jump to a date past 2045 and confirm the face falls back to computed events
   rather than showing nothing, and that `EclipseDataInfo` in the settings flips to
   `currently: estimated (beyond table)`.
9. **GPS gate:** set `EclipseVisibility` to *only when visible here*, park the clock at a
   lunar-eclipse maximum, then set `DebugLatitude`/`DebugLongitude` to a location where
   it is night (moon up → red moon) and to its antipode (moon down → normal moon).
   Clear both debug values and confirm the simulator's **Simulation > Set Position…**
   drives the same result. Finally disable position entirely and confirm the fallback
   shows the eclipse rather than hiding it. Watch the debug `println` line for
   `sunAlt` / `visible?` at each step.
   Also confirm the readout: reopen **Settings** and check `LastFixInfo` reflects the
   position just used, that it reads `no position — showing all eclipses` when position
   is unavailable, and that **no coordinates appear anywhere on the dial itself**.
10. **Always-on:** toggle low power in the simulator — second numerals, stars and the
    zodiac gone, hour numerals dim, no wave, hands outline-only, burn-in drift still
    working.
11. Sanity-check the moon across a full synodic month (step the date day by day) to
    confirm the new limb darkening doesn't break the terminator at the quarters.

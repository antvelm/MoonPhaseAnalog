# Milky Way starfield — implementation summary

What shipped, how it differs from the plan in `docs/milky-way-starfield.md`, and
what still needs eyes on it.

Branch `v2`. Both `venu3` and `venu3s` build clean, no warnings.

---

## What changed, in one paragraph

The starfield behind the dial was a uniform scatter of at most 44 stars with no
connection to anything else on the face. It is now two populations — a dense
band arcing across the dial, plus a sparser scatter elsewhere — and **moonlight
washes it out**: each star carries a magnitude, moonlight raises the faintest
magnitude that still draws, and everything below that is skipped. At new moon
the whole field shows; by first quarter the band is gone; a full moon leaves
a dozen bright anchors, dimmed as well as thinned. Star count became a single adjustable number
(default 120) instead of a four-step density enum.

---

## Behaviour

Measured by replaying the exact generator arithmetic outside the watch
(`starcheck.ps1`, see *How this was verified*), at the default `StarCount` 120:

| phase | illumination | stars drawn | faintest survivor's level |
|---|---|---|---|
| new | 0.00 | 120 | 0.57 |
| thin crescent | 0.15 | 88 | 0.51 |
| first quarter | 0.50 | 45 | 0.43 |
| gibbous | 0.85 | 24 | 0.38 |
| **full** | 1.00 | **13** | 0.31 |

Four stars twinkle at every phase, by construction. Reproduce the table with
`tools\starcheck.ps1`; the numbers above are its default output.

Sprite mix at 120: **93** single-pixel dots, **15** small crosses, **8** static
sparkles, **4** twinkling sparkles.

Field extent stays inside 0.206–0.860 R with **zero** stars needing the
boundary clamp, at every count tested (120 / 160 / 200).

---

## The settings change

`StarDensity` (list: off / sparse / normal / dense → 0, 14, 28, 44 stars) is
**gone**, replaced by:

```xml
<property id="StarCount" type="number">120</property>
```

a plain numeric field, range 0–200. `Settings.starDensity` → `Settings.starCount`;
`_lastDensity` → `_lastStarCount`. Five now-unused strings were deleted and two
added.

Each star's identity is fixed by its index, so **raising the count adds stars
without moving the ones already there** — confirmed by the identical radius
extremes across 120 / 160 / 200. Star 0 is the same star at every setting.

---

## How the pieces work

**The band** (`Dial.buildStars`). A star is assigned to the band or the field by
its own variate rather than by splitting the array — that is what buys the
index-stability above. Band stars are placed in a rotated frame: `s` runs along
the band, `d` across it, and the spine is bowed by `MW_BOW * (s² - 0.5)`, which
is what curves it into an arc instead of a stripe. Two summed uniforms give `d`
a triangular spread, so the band is dense on its spine and thins to either side.
Points landing in the hub or past the rim are resampled up to five times, then
radially clamped.

**Magnitude.** Skewed hard toward faint, since the fade is only legible if most
stars are dim: band haze is `0.04 + 0.62·w³`, field stars `0.18 + 0.54·w²`, with
a small bright minority in each (`0.78 + 0.22·w` / `0.72 + 0.28·w`) so a full
moon does not leave an obvious hole where the band was.

**The fade** (`Dial.drawStarfield`). A cutoff and a wash, both per frame:

```
illum    = MoonPhase.illumination(frac)
floorMag = MOON_FLOOR * illum
if (mag <= floorMag) skip
wash     = 1 - MOON_WASH * illum
level    = wash * (STAR_LEVEL_MIN + (1 - STAR_LEVEL_MIN) * (mag - floorMag)/(1 - floorMag))
```

`STAR_LEVEL_MIN` is why stars dissolve rather than pop: a star right at the
cutoff still draws, just dimly. `MoonPhase.illumination` already returned exactly
the 0-at-new / 1-at-full value needed, so no new astronomy was written.

`MOON_WASH` is the second half of the effect, added after the first version
shipped looking wrong. A cutoff on its own only makes the field *sparser*: the
stars it spares are by definition the brightest, most conspicuous sprites, and
they keep drawing at full strength, so a full moon reads as the same sky with
gaps in it rather than as a washed-out one. Dimming the survivors as well is
what makes the phase legible at a glance.

**Phase routing.** `frac` was being computed inside `drawMoon`, after
`drawBackground` had already run. It is now taken once in `onUpdate` and passed
to both — off `astroTime(now)`, so `DebugTimeOffsetDays` scrubs the sky and the
moon together. That is the intended way to test this feature.

**Tiers.** Sprite size now follows magnitude instead of being rolled separately,
so a big sprite always means a bright star. This gave `Theme.STAR_DIM` a purpose
— it was defined but never referenced — and removed a dead ternary in `drawStar`
where tiers 1 and 0 both resolved to `Theme.STAR`.

---

## Deviations from the plan

**1. Zodiac twinkle was kept, not dropped.** The plan proposed letting zodiac
constellations lose their twinkle as a side effect of the tier change. On the
instruction to keep animations as they are, `drawZodiac` now promotes its tier-2
stars to tier 3 at the call site, so **zodiac mode renders exactly as before** —
same palette, same pulse, full brightness at every phase. The moonlight rules
still do not touch it.

**2. The twinkle gate is a counter, not a random draw.** The plan said to reuse
the `w2` variate. That was wrong twice over, and both only showed up under
measurement:

- `w2` had *already* been spent choosing the magnitude branch. Every star with
  `mag >= 0.85` necessarily had `w2 > 0.72`, so `(w2 > 0.72) ? 3 : 2` always
  picked 3 — **tier 2 was unreachable and all 12 bright stars twinkled.** At
  full moon that is 12 of 19 visible stars pulsing: precisely the all-over
  shimmer the gate existed to prevent.
- A *fresh* variate did not fix it either. This LCG (`seed*75+74 mod 65537`)
  sampled at a fixed stride per star is correlated enough that a 1/3 threshold
  came out at 2/3 — still 8 twinklers.

So every third bright star twinkles, by count. That pins the number exactly:
4 at `StarCount` 120, 6 at 160, 8 at 200.

**3. The faint floors were lowered.** As planned, the band's minimum magnitude
was 0.12, so with `MOON_FLOOR` at 0.80 nothing faded until illumination passed
0.15 — the sky stayed completely full for about the first three and a half days
either side of new moon. Since the requirement was that the dimmest stars show
*only* at or very near new moon, the floors dropped to 0.04 (band) and 0.18
(field), so the faintest start going as soon as there is any moon at all. This
is what turned the crescent column in the table above from 120 into 90.

**4. `drawPoint` replaced `fillCircle(r=1)` for tier 0**, and star coordinates
are now rounded to whole pixels in `buildStars` rather than left as floats. Both
were planned as optional; both were taken.

---

## Performance

Two optimizations went in with the feature:

- **Antialiasing is switched off for the starfield pass only** and restored
  after. `setAntiAlias(true)` is global (`MoonPhaseAnalogView.mc`), and an
  antialiased `fillCircle(r=1)` is markedly more expensive than an aliased one —
  at ~120 of them that was the single biggest line item. These sprites are 1–3 px;
  there is nothing for antialiasing to smooth.
- **Tier 0 draws a single pixel** via `drawPoint` rather than a fill.

Working against the cost: the fade skips sub-cutoff stars on a float compare
before any `Dc` call, so **the field gets cheaper as the moon fills** — new moon
is the worst case. `RainbowWave.tint` early-returns when the wave is inactive, so
its per-star `sqrt` is only paid during a wave. Twinkle is pinned to ~4 stars, so
`Math.sin` does not scale with the field. `buildStars` is not on the draw path.

**Not yet measured on hardware.** The estimate is ~2.7× the old starfield's draw
cost at the default — still one to two orders of magnitude under the ~1,900-sample
moon gradient that historically tripped the watchdog — but that is an estimate,
not a profile. See *What still needs checking*.

---

## Files touched

| File | Change |
|---|---|
| `source/MoonDial.mc` | waning terminator mirrored; limb rim faded in with the crescent (`RIM_FADE`) |
| `source/Theme.mc` | `STAR_DIM` raised so the faint tier is actually visible |
| `source/Dial.mc` | band + moonlight constants incl. `MOON_WASH`; `buildStars` rewritten; fade and AA toggle in `drawStarfield`; `base` param, tier-3 twinkle and `drawPoint` in `drawStar`; `frac` through `drawBackground`; `drawZodiac` call site |
| `source/MoonPhaseAnalogView.mc` | `frac` hoisted into `onUpdate` and passed to `drawBackground` / `drawMoon`; `_lastStarCount` |
| `source/Settings.mc` | `starDensity` → `starCount`, default 120, range 0–200 |
| `resources/properties.xml` | `StarDensity` → `StarCount`; `Background` comment |
| `resources/settings/settings.xml` | list → `numeric min=0 max=200` |
| `resources/strings/strings.xml` | 5 density strings removed, 2 added |

Untouched: `MoonPhase.mc`, `Zodiac.mc`, `RainbowWave.mc`, and
`docs/redesign-recap.md` — this change is documented here and in
`docs/milky-way-starfield.md` only, not folded into the earlier recap.

---

## Tuning

All in `source/Dial.mc`:

| Constant | Now | What it does |
|---|---|---|
| `MW_ANGLE` | 0.52 | band axis, radians clockwise from vertical |
| `MW_BOW` | 0.55 | how far the arc bows; 0 is a straight band |
| `MW_WIDTH` | 0.30 | half-width either side of the spine |
| `MW_SHARE` | 0.62 | fraction of stars in the band |
| `MW_SPAN` | 0.86 | how far along the radius the band reaches |
| `MOON_FLOOR` | 0.88 | faintest magnitude still visible at full moon |
| `MOON_WASH` | 0.45 | brightness the whole field loses by full moon |
| `STAR_LEVEL_MIN` | 0.55 | how brightly a star draws right at the cutoff |

Raise `MOON_FLOOR` for a starker full moon, `MOON_WASH` to make what survives
it quieter, and `STAR_LEVEL_MIN` if the faint haze is too dim to see on the
real panel. `Theme.STAR_DIM`, which the faint tier draws in, is the fourth
lever: it went from `0x3A3A44` to `0x4E4E58` for the same reason.

---

## How this was verified

**Done:**

- Both devices compile clean, no warnings.
- The generator arithmetic was replayed outside the watch — same LCG, same seed,
  same constants — to produce the phase and tier tables above. This is what
  caught the unreachable tier 2, the over-eager twinkle threshold, and the
  too-high faint floors; none of the three is visible by reading the code.
- Counts 0 / 1 / 120 / 160 / 200: no empty-array crash path, no clamping, and
  identical radius extremes across counts, confirming index stability.

- **The synodic month was walked in the simulator**, eight steps from new to
  waning crescent, by `tools\gen-phase-walk.ps1`. Each step picks the
  `DebugTimeOffsetDays` that lands the astro clock exactly on the target phase
  fraction, builds, resets simulator state per
  `docs/simulator-property-reset.md`, and screenshots. `tools\montage.ps1`
  stitches the results into `screenshots\phase-walk\moon-strip.png` (the disc,
  magnified) and `star-grid.png` (one dial quadrant at 2x, where the faint tier
  survives the scaling — a downscaled whole-face montage averages single-pixel
  stars into the background and makes the fade look like it is not happening).
- The nine unit tests pass.

### Two bugs the walk caught

Both were invisible in a still of today's sky, and both are why the feature
looked broken rather than subtle:

**The waning half of the month rendered time-reversed** (`MoonDial.draw`). The
lit span was `-w .. w*cos(p)` past full moon, but `cos` is symmetric about frac
0.5, so that replays the waxing crescents backwards: the moon jumped from full
straight to a thin sliver and grew back to full by the next new moon. It is
`-w .. -w*cos(p)`. Because the starfield keys off the same `frac`, the sky was
right while the disc beside it was not, which read as the stars being broken
too.

**A new moon was drawn with a bright rim** round its lit limb, because the
terminator highlight was drawn flat whenever `awake`. There is no lit limb at
new moon; the rim now fades in with the crescent's width (`RIM_FADE`), so a new
moon is a genuinely dark disc.

## What still needs checking

1. **Does the band read as an arc?** `MW_BOW` and `MW_WIDTH` were picked by eye
   from a coarse ASCII render. `MW_WIDTH` 0.30 may be wide enough to look diffuse
   rather than band-like.
2. **Profile** `onUpdate` at `StarCount` 200, parked at new moon, with
   `WaveTestMode` on — that is the worst-case frame.
3. **On-device** side-load at 200 through several wrist-raise cycles, watching
   for a watchdog reset.
4. **Regressions**: zodiac modes unchanged; always-on still skips the background;
   burn-in shift still applies via `_ox/_oy`.

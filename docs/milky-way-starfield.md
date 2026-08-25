# Milky Way starfield with moonlight-driven star visibility

## Context

The starfield behind the dial (`Dial.buildStars` / `Dial.drawStarfield`) is currently a
flat, uniform scatter: 14/28/44 stars on an annulus, brightness `0.55..1.0` correlated
with tier, and no relationship to anything else on the face. On a watch face whose whole
subject is the Moon, that is a missed connection — the sky is decorative rather than
astronomical.

Two changes fix that:

1. **Structure.** Stars concentrate along a fixed, gently arced band across the dial, so
   the field reads as the Milky Way rather than as noise.
2. **Meaning.** Moonlight washes stars out. The faintest stars are visible only at or near
   new moon and gradually disappear as the Moon waxes, until at full moon only a dozen or
   so bright anchor stars remain. The sky then becomes a second, ambient readout of the
   same phase the moon disc shows.

The star count also becomes a directly adjustable number (default 120) instead of the
four-step `StarDensity` enum, which tops out at 44 — far too sparse for a band to read.

Scope note: **the Zodiac backgrounds are deliberately unchanged.** They are an
informational display, and fading stars by magnitude would break the constellation shapes.

---

## Step 0 — save this plan

Copy this file to `docs/milky-way-starfield.md` before starting. (Plan mode restricts
edits to the plan file, so it could not be written there during planning.)

---

## Step 1 — `StarDensity` → `StarCount`

Replace the enum with a numeric setting. Four files:

**`resources/properties.xml`** (replace the `StarDensity` block at lines 89-92):

```xml
<!-- Number of stars in the procedural field (Background 0). 0 turns the
     starfield off. Stars cluster along a fixed arced band across the dial -
     the Milky Way - with a sparser scatter elsewhere. The field is seeded and
     each star's identity is fixed by its index, so raising the count adds
     stars without moving the ones already there, and a given count always
     yields the same sky. How many are actually drawn depends on the moon
     phase: see Dial.MOON_FLOOR. Changing this rebuilds the field on the next
     draw. Above ~150 check the frame cost on-device before shipping. -->
<property id="StarCount" type="number">120</property>
```

Also update the `Background` comment at lines 76-81, which references `StarDensity` twice.

**`resources/settings/settings.xml`** (replace lines 72-79):

```xml
<setting propertyKey="@Properties.StarCount" title="@Strings.SetStarCount"
         prompt="@Strings.SetStarCountPrompt">
    <settingConfig type="numeric" min="0" max="200" />
</setting>
```

**`resources/strings/strings.xml`** — delete `SetStarDensity`, `DensityOff`,
`DensitySparse`, `DensityNormal`, `DensityDense` (lines 54-58); add:

```xml
<string id="SetStarCount">Stars</string>
<string id="SetStarCountPrompt">How many stars in the sky, 0-200. Faint stars are only visible near new moon and fade out as the moon fills.</string>
```

**`source/Settings.mc`** — rename the field (line 58) and its read (line 90):

```monkeyc
var starCount;
...
starCount = numberOr("StarCount", 120, 0, 200);
```

**`source/MoonPhaseAnalogView.mc`** — in `refreshCaches` (lines 84-89), rename
`_lastDensity` → `_lastStarCount` and compare against `Settings.starCount`. Rename the
field declaration too.

---

## Step 2 — route the moon phase into the background draw

`frac` is currently computed inside `drawMoon` (`MoonPhaseAnalogView.mc:262`), but
`Dial.drawBackground` is called earlier at line 134. Hoist it so both share one value —
this also means `DebugTimeOffsetDays` scrubs the starfield along with the moon, which is
how the fade gets tested.

In `onUpdate`, after `var now = ...` (line 107):

```monkeyc
// The starfield fades with moonlight, so the background needs the same phase
// the disc draws - off the same astro clock, so a debug offset moves both.
var frac = MoonPhase.fractionAt(astroTime(now));
```

Then at line 134: `Dial.drawBackground(dc, clock.sec, frac);`
and at line 142: `drawMoon(dc, awake, now, frac);`

In `drawMoon`, add the `frac` parameter and delete the local computation at line 262,
keeping the comment above it (it now explains the hoist).

`Dial.drawBackground` takes and forwards `frac` to `drawStarfield`; the zodiac branch
ignores it.

---

## Step 3 — the arced band and the magnitude distribution (`Dial.buildStars`)

Add module constants near the other `Dial` geometry constants:

```monkeyc
// --- Milky Way band -----------------------------------------------------
const MW_ANGLE   = 0.52;   // band axis, radians clockwise from vertical
const MW_BOW     = 0.55;   // arc depth across the dial; 0 would be a straight band
const MW_WIDTH   = 0.30;   // half-width either side of the spine, in radius units
const MW_SHARE   = 0.62;   // fraction of stars drawn from the band
const MW_SPAN    = 0.86;   // band reaches this fraction of the radius

const STAR_R_MIN = 0.20;   // keep the hub clear for the hands and the moon
const STAR_R_MAX = 0.86;
```

Rewrite `buildStars` (`Dial.mc:387-415`). Key structural change: **band membership is a
per-star variate, not an array split**, so star `i` is identical at every count and
raising `StarCount` purely adds stars.

Six LCG draws per star (`c` band class, `u`/`v`/`v2` position, `w` magnitude, `w2`
brightness class), same `seed * 75 + 74 mod 65537` generator and same `20260822` seed.
Hoist `Math.cos(MW_ANGLE)` / `Math.sin(MW_ANGLE)` out of the loop.

**Band branch** (`c < MW_SHARE`) — parabolic spine, triangular density across it:

```monkeyc
var s  = -1.0 + 2.0 * u;                    // along the band, -1..1
var d  = MW_WIDTH * (v + v2 - 1.0);         // across: two uniforms -> peaked on the spine
var t  = MW_BOW * (s * s - 0.5) + d;        // the bow is what makes it an arc, not a line
var ux = (s * ca - t * sa) * MW_SPAN;
var uy = (s * sa + t * ca) * MW_SPAN;
```

**Field branch** — today's polar sampling, unchanged:
`rr = STAR_R_MIN + (STAR_R_MAX - STAR_R_MIN) * sqrt(u)`, `aa = v * 2pi`.

**Annulus guard.** A band point can land in the hub or past the rim. Resample that star
up to 5 times (advancing the LCG each try); if it still fails, radially clamp the point
into `STAR_R_MIN..STAR_R_MAX`. This keeps exactly `n` stars — no wasted array slots — and
clamping is rare enough to be invisible.

**Magnitude.** The whole feature depends on magnitude spanning a wide range with far more
faint stars than bright ones. Band stars are mostly faint haze; both populations get a
small bright minority so full moon does not leave a conspicuous hole where the band was:

```monkeyc
var mag;
if (inBand) {
    mag = (w2 > 0.90) ? 0.78 + 0.22 * w        // rare bright anchor inside the band
                      : 0.12 + 0.56 * w * w * w;  // cubed: the haze, overwhelmingly faint
} else {
    mag = (w2 > 0.72) ? 0.72 + 0.28 * w        // the named stars
                      : 0.26 + 0.46 * w * w;
}
```

**Tier follows magnitude** rather than being drawn independently, so sprite size and
brightness agree. Tier 3 is the twinkling variant of tier 2 (Step 5):

```monkeyc
var tier = 0;
if (mag >= 0.85)      { tier = (w2 > 0.72) ? 3 : 2; }
else if (mag >= 0.62) { tier = 1; }
```

Storage stays the stride-4 flat array `[x, y, tier, mag]` — same layout, same convention
as `_zodiacPts`, no per-star memory increase.

---

## Step 4 — the moonlight fade (`Dial.drawStarfield` / `drawStar`)

Constants:

```monkeyc
const MOON_FLOOR     = 0.80;  // magnitude cutoff at full moon
const STAR_LEVEL_MIN = 0.35;  // rendered brightness of a star right at the cutoff
```

`drawStarfield` computes the cutoff once per frame, then skips or scales each star:

```monkeyc
(:typecheck(false))
function drawStarfield(dc, sec, frac) {
    if (_stars == null) { return; }

    // Moonlight raises the faintest magnitude that still shows. Stars below it
    // are skipped before any Dc call, so a full moon is also the cheapest frame.
    var floorMag = MOON_FLOOR * MoonPhase.illumination(frac);
    var span = 1.0 - floorMag;

    var n = _stars.size() / 4;
    for (var i = 0; i < n; i += 1) {
        var mag = _stars[i * 4 + 3];
        if (mag <= floorMag) { continue; }

        // Fade in from black as a star clears the cutoff, rather than popping.
        var level = STAR_LEVEL_MIN
                  + (1.0 - STAR_LEVEL_MIN) * ((mag - floorMag) / span);

        var tier = _stars[i * 4 + 2];        // 3 == bright + twinkling, see Step 5
        var base = (tier >= 2) ? Theme.STAR_BRIGHT
                 : (tier == 1) ? Theme.STAR
                 : Theme.STAR_DIM;

        drawStar(dc, _stars[i * 4] + _ox, _stars[i * 4 + 1] + _oy,
            tier, level, sec, i, base);
    }
}
```

`MoonPhase.illumination(frac)` (`MoonPhase.mc:39-41`) already returns exactly the 0-at-new,
1-at-full value needed — no new astronomy.

`drawStar` gains a `base` parameter, replacing the dead ternary at `Dial.mc:438-439`
(where tiers 1 and 0 both resolved to `Theme.STAR`). This finally gives `Theme.STAR_DIM`
(`Theme.mc:73`, currently defined but never referenced) its purpose. The sprite geometry —
arms, diagonals, `RainbowWave.tint` — is untouched.

---

## Step 5 — keep the twinkle animation

The existing tier-2 pulse stays exactly as it is: an 8-second sine on the free 1 Hz
redraw, phase-offset per star by `index * 7` so they are not in lockstep
(`Dial.mc:433-436`). It multiplies whatever brightness it is handed, so it now composes
with the moonlight fade for free — a twinkling star near the cutoff pulses dimly, one at
full magnitude pulses brightly.

**One gate has to be added.** Today ~8% of 44 stars are tier 2, so about **3-4 stars
twinkle**, matching the original design note ("two or three tier-2 stars twinkle",
`plans/dial-redesign-animation-options.md` §7). Under the new distribution tier 2 is ~12
of 120 — and because the full-moon survivors are almost all tier 2, *every star in the
sky* would be pulsing at full moon. That reads as a busy shimmer, not a night sky.

So twinkle becomes a per-star property rather than a synonym for tier 2. Reuse the `w2`
variate already drawn in `buildStars` — no extra state, no extra array slot — and fold the
flag into the stored tier, as shown in Step 3: **tier 3 is tier 2 that also twinkles.**
The star record stays four wide.

In `drawStar`, only tier 3 drives the pulse:

```monkeyc
if (tier == 3) {
    var phase = ((sec + index * 7) % 8) / 8.0;
    b = b * (0.72 + 0.28 * Math.sin(phase * 2.0 * Math.PI));
}
```

Every other `tier == 2` test in `drawStar` becomes `tier >= 2`, so a tier-3 star draws the
identical sprite: the `arm` length (`Dial.mc:448`), the `fillCircle` radius
(`Dial.mc:452`), and the faint-diagonals block (`Dial.mc:454-460`). Only the pulse
distinguishes them.

That yields ~4 twinkling stars at the default count of 120 — the same feel as today — and
scales gently with `StarCount` rather than exploding. At full moon roughly 4-5 of the ~16
survivors twinkle, so the sky still moves without shimmering all over.

`drawZodiac` passes tier straight from `Zodiac.tierFor` (max 2), so **no constellation
star ever twinkles** — unchanged from today, where a zodiac tier-2 star did pulse. If you
want zodiac twinkle preserved exactly, promote its tier 2 to 3 at the call site instead;
the plan assumes the calmer version, since the moonlight rules already leave zodiac mode
alone.

`drawZodiac` (`Dial.mc:496-499`) passes the **old** base expression, so zodiac mode renders
byte-identically to today:

```monkeyc
var zbase = (ztier == 2) ? Theme.STAR_BRIGHT : Theme.STAR;
drawStar(dc, ..., ztier, 1.0, sec, j, zbase);
```

### What this produces

| | new moon | half | full moon |
|---|---|---|---|
| band haze (mag ~0.12-0.68) | all visible, dim | mostly gone | gone |
| mid stars (mag ~0.7) | visible | faint | gone |
| anchors (mag ~0.95) | full white | full white | full white |
| **drawn, of 120** | **120** | **~55** | **~16 (13%)** |

Because the survivors are almost all `mag >= 0.85`, full moon leaves a sky of a dozen
tier-2 sparkles — which is what a real full-moon sky looks like.

---

## Performance

The tight budget is real: Venu 3 has a **123.9 kB** memory ceiling and a watchdog that
already killed the first moon gradient (`docs/redesign-recap.md:112-131`). The starfield
tripling its star count is the main risk in this plan, so it gets mitigations up front and
a measurement step, not an assurance.

### Budget

| | today (44) | proposed (120) | cap (200) |
|---|---|---|---|
| tier-0 dots | ~31 | ~88 | ~146 |
| tier-1 sprites (3 calls ea.) | ~10 | ~20 | ~33 |
| tier-2/3 sprites (5-7 calls ea.) | ~4 | ~12 | ~20 |
| **total `dc` calls/frame** | **~126** | **~340** | **~570** |
| `Math.sin`/frame | ~4 | ~4 | ~7 |

~2.7x today's shipped cost at the default, once per second, still one to two orders of
magnitude below the ~1,900-sample gradient that tripped the watchdog.

### What is already free

- **The fade is a win, not a cost.** Sub-cutoff stars are skipped on a float compare before
  any `Dc` call, so the field gets *cheaper* as the moon fills. New moon is the worst case.
- **`RainbowWave.tint` early-returns on `!_active`** (`RainbowWave.mc:130`), so the per-star
  `Math.sqrt` is only paid during a wave — seconds every few hours, not every frame.
- **Twinkle is gated to tier 3** (Step 5), so `Math.sin` stays at ~4/frame regardless of
  star count. Without that gate it would have scaled with the field.
- **`buildStars` is not on the draw path** — `onLayout` and `StarCount` changes only. The
  extra LCG draws, `sqrt` and resampling there cost nothing per frame.
- **Starfield stays awake-only** (`MoonPhaseAnalogView.mc:133`), so none of this touches
  always-on battery.
- **Memory**: 480 array slots at 120, 800 at the cap, against 176 today. Kilobytes, not
  tens of kilobytes — the flat stride-4 array is what keeps it that way.

### Two optimizations to apply with the feature

**1. Drop antialiasing for the starfield pass.** `setAntiAlias(true)` is set globally at
`MoonPhaseAnalogView.mc:126`, and an antialiased `fillCircle(r=1)` is markedly more
expensive than an aliased one — at ~120 of them this is the single biggest line item.
Stars are 1-3 px sprites where antialiasing buys almost nothing:

```monkeyc
// Two state changes to make ~120 tiny fills cheap. The sprites are 1-3 px;
// there is nothing here for antialiasing to smooth.
var aa = (dc has :setAntiAlias);
if (aa) { dc.setAntiAlias(false); }
... draw the field ...
if (aa) { dc.setAntiAlias(true); }
```

Do this in `drawStarfield` only, so the zodiac path and everything after it are unaffected.

**2. `drawPoint` for tier 0.** Replaces the `fillCircle(x, y, 1)` at `Dial.mc:444` — one
pixel instead of a fill, for ~88 of the ~120 stars. Faint stars *should* be single pixels,
so this arguably improves the look as well. Apply it after optimization 1 and compare
screenshots; if the faintest stars read as too subtle on the real panel, revert this one
and keep the AA change.

### Measure, then decide

Run the **Connect IQ simulator profiler** on `onUpdate` with `StarCount` at 120 and at 200,
parked at new moon (worst case) with `WaveTestMode` on so a wave is active. Compare against
the same profile on the current `v2` build at density 3. If the starfield's share of frame
time is what the table predicts, ship it.

**If it does not hold**, in order of preference: apply optimization 2 if it was skipped →
lower the `max` in `settings.xml` from 200 to ~150 → lower `MW_SHARE` so fewer faint dots
are drawn → last resort, cache the field to a `BufferedBitmap` and blit it, rebuilding only
when the phase cutoff moves (about once a day). The last option costs memory against a
123.9 kB ceiling, which is why it is last.

---

## Files touched

| File | Change |
|---|---|
| `source/Dial.mc` | band constants; rewrite `buildStars`; fade + AA toggle in `drawStarfield`; `base` param and tier-3 twinkle in `drawStar`; `frac` through `drawBackground`; `drawZodiac` call site |
| `source/MoonPhaseAnalogView.mc` | hoist `frac`; pass to `drawBackground`/`drawMoon`; `_lastStarCount` |
| `source/Settings.mc` | `starDensity` → `starCount`, default 120, range 0-200 |
| `resources/properties.xml` | `StarDensity` → `StarCount`; `Background` comment |
| `resources/settings/settings.xml` | list → `numeric min=0 max=200` |
| `resources/strings/strings.xml` | drop 5 density strings, add 2 |
| `docs/redesign-recap.md` | document the band + fade in the star section |

Not touched: `Theme.mc` (all needed colours and `dim`/`blend` already exist),
`MoonPhase.mc`, `Zodiac.mc`, `RainbowWave.mc`.

---

## Verification

**Build.** `monkeyc` against `venu3` and `venu3s` — the `_scale` factor
(`MoonPhaseAnalogView.mc:67`) means the band must be checked on both radii (227 / 195).
Confirm the type checker passes; `buildStars` and `drawStarfield` keep `(:typecheck(false))`.

**Walk the synodic month.** This is the main test. In the simulator, set
`DebugTimeOffsetDays` and watch the sky between screenshots:

| offset (days) | phase | expected sky |
|---|---|---|
| tuned to nearest new moon | new | full band, arc clearly visible, faint haze present |
| +3.7 | crescent | haze thinning, band still readable |
| +7.4 | first quarter | band mostly gone, ~half the stars |
| +14.8 | **full** | ~16 stars, all sparkles, no band |
| +22.1 | last quarter | band returning |

Step in ~1-day increments across new moon to confirm stars **fade** rather than pop —
that was the explicit design choice.

**Star count.** Set `StarCount` to 0 (empty sky, no crash — `new [0]`), 1, 120, 200.
Confirm the field rebuilds without an app restart (`refreshCaches`). Set 120 → 160 and
verify the original 120 stars **do not move** — that is what the per-star band variate buys.

**Animation.** Watch a stationary face for ~15 s at new moon and count the pulsing stars —
expect about 4 at `StarCount` 120, drifting in and out of phase with each other, the same
rhythm as today. Then jump to full moon: the sky drops to ~16 stars and ~4-5 should still
pulse. Confirm no faint dot pulses (twinkle is tier 3 only) and that a star fading near the
moonlight cutoff pulses *dimly* rather than at full brightness.

**Regressions.**
- `Background` = 1 and 2: zodiac constellations pixel-identical to before at every phase,
  except that their bright stars no longer twinkle — see Step 5 if that should be kept.
- Always-on: background still skipped, burn-in shift still applies to the stars via `_ox/_oy`.
- Rainbow wave: fires across the denser field without visible stutter.
- Eclipse: a lunar eclipse drops illumination — confirm the sky behaves sensibly.

**Performance.** Profile before shipping — see *Measure, then decide* above. The worst-case
frame is `StarCount` 200 + new moon + an active wave (`WaveTestMode`), so profile exactly
that, not a default idle frame.

**On-device.** Side-load at `StarCount` 200 and leave it through several wrist-raise
cycles, watching for a watchdog reset. Back the cap down if it trips.

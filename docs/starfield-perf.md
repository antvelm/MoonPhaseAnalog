# Starfield cost on a Venu 3

What `Dial.drawStarfield` actually costs on hardware, which optimisations paid,
which did not, and what is left. Measured 2026-08-23 on branch `v2`.

---

## How to reproduce a measurement

`build.ps1 -Perf` compiles the overlay in `source/Perf.mc`. Read the `bg` line
(that section is `Dial.drawBackground` plus the orbit ring; with the ring off it
is the starfield alone) and the `cur/peak ms` total.

Measure at **new moon**. That is the worst case: the moonlight cutoff is at zero,
so every star is above it. At 80% lit only about a fifth of the field draws and
the number means nothing.

Getting a build to actually land there is the fiddly part — see
[Gotchas](#gotchas) below. Editing `resources/properties.xml` does **not** work.

---

## The cost model

At new moon, every star drawn:

| StarCount | `bg` | total |
|---|---|---|
| 200 | 98 ms | 160 ms |
| 120 | 56 ms | 122 ms |

**`bg ≈ 0.52 × StarCount − 7` ms** — dead linear, which works out at roughly
**0.26 ms per Dc draw call**. Draw calls are the entire cost. The Monkey C
arithmetic around them, the array indexing, the loop itself: all noise.

Two consequences that are easy to get wrong:

- **There is a ~66 ms floor that is not the starfield** — track 15, cplx 16, plus
  marks, moon and hands. Even a free field leaves the total near 66 ms, so the
  starfield is not the only thing to cut if the target is below that.
- `onUpdate` runs at 1 Hz while awake, so the total is directly a CPU duty cycle:
  122 ms is 12% of every waking second, and that percentage is what the battery
  pays. The hard ceiling is the watchdog's 240,000 VM instructions per callback,
  which draw-heavy code does not approach — this is a battery problem, not a
  crash risk.

### Where the calls go

The sprite tiers, and what each costs, at 200 stars / new moon:

| tier | count | sprite | Dc calls each |
|---|---|---|---|
| 0 | 156 | 3 px cross | 2 strokes |
| 1 | 21 | 5 px cross + centre dot | 3 |
| 2 | 15 | sparkle with diagonals | 6 |
| 3 | 8 | sparkle, twinkles — recoloured per frame | ~8 |

Tier 0 is **78% of the field and 60% of the calls**. Any real saving has to come
from there.

---

## What paid, and what did not

### 1. A per-star `setPenWidth` — real bug

`dc.setPenWidth(1)` had been left above the `tier == 0` branch when the cross
sprite went in, so all 156 faint stars paid a pen-width call they never used. It
is now set once for the whole field, in `drawStarfield`.

### 2. Colour grouping — 10 ms, and that is all

`starLevel` is continuous in magnitude, so every star ended up with a colour of
its own and paid its own `setColor`. The fade is now quantised to
`Dial.LEVEL_STEPS = 10`, and `buildStarColors` counting-sorts the visible stars
into (tier, brightness step) buckets so the draw loop walks the field colour by
colour and sets each colour once. Tier is part of the sort key because it picks
the base colour, and keying it first puts the twinkling tier last where its
per-star recolour cannot split a run.

Distinct star colours on screen: **200 → 39**, rendering unchanged.

`drawStarShape` was split for this: it stays the colour-setting entry point for
the zodiac and the twinkle path, and `drawStarSprite` draws the strokes alone
with the colour and pen already on the Dc.

**Together (1) and (2) stripped about 380 Dc calls and bought 10 ms** — 108 ms
down to 98 at 200 stars. `setColor` and `setPenWidth` are nearly free; only calls
that rasterise cost anything. **This well is dry. Do not spend more effort on
state calls.**

### 3. Star count — the honest lever

Strokes scale linearly with the count, so this is the one knob that reliably
moves the number. 200 → 120 took `bg` from 98 to 56.

### Rejected: tier 0 as a single dash

A 3 px dash instead of a two-stroke cross halves the strokes on 78% of the field
— about 28 ms at 200 stars, the largest saving available without new machinery.

**Rejected on looks.** A field of dashes reads as scratches rather than stars,
whether they all lie the same way or the orientation alternates per star. There
is a comment in `Dial.drawStarSprite` recording this so it does not get
re-derived.

The two strokes are also what makes the faint tier visible at all: a 1×1 sprite
on an AMOLED black is below the size the eye resolves at any brightness the
moonlight fade leaves it, which is why a 200-star field used to read as the
forty-odd cross and sparkle sprites and nothing else.

---

## Not every Dc call costs the same

The model above treats draw calls as interchangeable at ~0.26 ms each. That is
true as an average and false as a rule, and the difference turned out to be
worth more than everything in the section above put together.

Benchmarked in the **Venu 3 simulator** (`Perf.bench`, six arms of 3,600 calls
each, all running identical coordinate arithmetic so the difference between
them is the Dc call alone; the arithmetic-only arm timed at 0 ms):

| primitive | per call |
|---|---|
| `drawLine` (3–7 px) | **6.4 µs** |
| `setColor` / `setPenWidth` | ~0 |
| `drawBitmap` 3×3 | 39 µs |
| `drawBitmap2` + `:tintColor`, 3×3 / 5×5 / 7×7 | 39 / 44 / 43 µs |
| `fillCircle` r=1 | **126 µs** |
| `fillCircle` r=2 | **139 µs** |

**`fillCircle` is ~20× a `drawLine` and 3× a whole tinted blit.** Every star in
tiers 1, 2 and 3 drew exactly one, and that single call was about 90% of what
those sprites cost:

| tier sprite | was | is |
|---|---|---|
| 0 — 2 strokes | 12.8 µs | unchanged |
| 1 — 2 strokes + `fillCircle` r1 | 138.6 µs | **43.6 µs** |
| 2/3 — 4 strokes + `fillCircle` r2 + 2 `setColor` | 165 µs | **42.8 µs** |

A blit's cost is **per call, not per pixel** — 3×3, 5×5 and 7×7 all time within
noise of each other. That is what splits the decision cleanly:

- **Tiers 1–3 are now one `drawBitmap2` with `:tintColor`**, from
  `resources/drawables/star_5x5.png` and `star_7x7.png`. 3–4× cheaper.
- **Tier 0 stays two strokes.** At 12.8 µs it is already cheaper than the ~39 µs
  floor any blit costs, so a sprite there is a 3× *loss* — and it is 78% of the
  field, so getting that half of the split wrong would have undone the rest.

Tinting is free (`blit 141` vs `tint 139` over the same 3,600 calls), so
per-star brightness costs nothing. The sprites are grayscale on opaque black:
`:tintColor` scales by luminance, which also folds the sparkle's 45% diagonals
into the same call instead of a `setColor` and two more strokes. They need
`automaticPalette="false"` — `drawBitmap2` rejects a palettised source with
*"Source must not use a color palette"*, the same restriction `renderLabel`
hits.

The sprites are **opaque**, which is only safe where nothing is underneath.
The starfield draws straight onto a cleared `Theme.BG`, so it qualifies; the
zodiac does not — it lays its joining lines down first, and a blit over one
erases the pixels where the line meets the star. `drawStar` therefore takes an
explicit `sprite` flag, true from the starfield and false from `drawZodiac`. A
dozen constellation stars on the stroke path cost nothing worth having.

Sprite sizes are fixed pixels rather than `scaled()`: `scaled(2)` and
`scaled(3)` round to the same value on venu3 (r=227) and venu3s (r=195), so one
sprite per tier serves both watches.

**Measured with anti-aliasing off, which the frame is not.** `onUpdate` calls
`setAntiAlias(true)` right after `clear`, and re-running these arms in that
state changes the answer: a 3 px `drawLine` goes from 12.7 µs to 85.4 µs and a
`fillCircle` r=2 from 124 µs to 393 µs. The *ratio* above survives — a circle is
still the expensive one — but the tier 0 decision below does not. See
[track-perf.md](track-perf.md), "The bigger fish this turned up".

**These are simulator numbers and want confirming on the watch.** The ordering
is stark enough (20×) that it is unlikely to invert, but the ratios will not
transfer exactly — the whole rest of this document was measured on hardware and
this section was not. Build with `-Perf` and read the `base / t0 / t1 / t2 /
p3 / t3 / t5 / t7` lines the overlay adds.

### The same lever, unpulled: the second track

`drawSecondTrack` draws ~48 `fillCircle`s a frame (`Dial.mc:287`), and
`drawOrbitRing` another 72 (`Dial.mc:445`) when it is on — it is off by
default. On device that is the `track` section at **~15 ms**, so the same fix
is worth single-digit milliseconds, not the frame. See `docs/track-perf.md`.

(An earlier draft of this section claimed 15–31 ms and "larger than the
starfield ever was". That came from the simulator overlay, whose section
timings are quantised to 15.6 ms and mean nothing — see the gotcha below.)

---

## The remaining lever, superseded

This section predates the measurement above and is kept for the reasoning, not
the plan: a `BufferedBitmap` cache is no longer the shape of the answer, because
static resources turned out to be enough and a blit is too expensive for tier 0
at any level of caching. What it got right was the question — *what does a blit
cost against a stroke* — and the answer is 39 µs against 6.4.

A **sprite cache**. `LEVEL_STEPS = 10` already collapses the field to exactly
3 tiers × 10 brightness steps = **30 distinct sprites**, ≤7×7 each. Pre-render
them into `BufferedBitmap`s and each star becomes one `drawBitmap` instead of
2–6 strokes:

| | 120 stars now | with sprites |
|---|---|---|
| tier 0 × 91 | 182 strokes | 91 blits |
| tier 1 × 15 | 45 | 15 |
| tier 2 × 14 | 84 | 14 |
| tier 3 × 5 | ~40 | ~40 — twinkles, no cache possible |
| **total** | **~350** | **~160** |

If a blit costs about what a stroke does, `bg` 56 → ~26 ms.

Three things make it easier than it sounds:

- **No transparency needed.** The field draws immediately after `dc.clear` onto
  solid `Theme.BG`, so an opaque sprite with a black surround is correct —
  nothing behind it needs preserving. That sidesteps palette and
  `COLOR_TRANSPARENT` entirely.
- **The API is proven on this device** — `MoonDial.mc:106` and `Dial.mc:170`
  already use `Gfx.createBufferedBitmap`.
- **Memory fits.** 30 sprites of ≤7×7 is a few hundred bytes of pixels; even with
  per-object overhead that is low single-digit kB against ~46 kB of headroom
  (53 k live of 99 k free).

**The unknown that decided it:** `drawBitmap`'s per-call cost versus `drawLine`.
Everything above assumed they were comparable. They are not — a blit runs **6×**
a stroke, so tier 0 does get worse, exactly as feared, and it is 78% of the
field. Measured, and the answer is above. The table's premise ("if a blit costs
about what a stroke does") is false; what rescued the idea was that the *bright*
tiers were never paying for strokes in the first place, they were paying for a
`fillCircle`.

Also note the cache must be re-rendered whenever the illumination bucket changes
(`ILLUM_STEPS = 64`, so a few times a day). That happens inside an `onUpdate`, so
one frame will occasionally spike.

---

## Gotchas

**The simulator cannot time a section of `onUpdate`.** `System.getTimer()`
there resolves to ~15.6 ms (the Windows tick), so every section reads as 0, 15,
16, 31 or 32 and nothing else — whichever ticks happened to land inside it.
Which sections even appear changes at random between frames. Four consecutive
new-moon samples read `clear 16 / track 16 / marks 15`, `clear 15 / track 32 /
cplx 15`, `bg 15 / track 16 / cplx 16`, `bg 15 / track 31`. **Take section
timings on the watch only.** To measure anything in the simulator, batch it:
loop the operation a few thousand times and time the batch, which is what the
per-primitive table above did.

**`loadResource` hands back a `ResourceReference`, not the bitmap.** Bitmaps and
fonts load into the graphics pool, which "dynamically caches, unloads and
reloads your resources behind the scenes based on available memory". Keeping
only the reference means every `drawBitmap`/`drawBitmap2` pays a pool resolve,
and the bitmap can be purged and reloaded underneath you. Call `.get()` and hold
what it returns — that locks it in the pool. `Dial.renderLabel` and
`MoonDial.mc:107` already did this; the star sprites did not, and the first
device reading was ~1.3 ms per blit against ~0.26 ms for an ordinary Dc call.
`Dial.lockedBitmap` is the fix.

**A reading taken at the wrong phase means nothing, and 80% lit is the trap.**
The cutoff at 78% illumination is `0.88 × 0.78 = 0.686`, and every tier-0 star
has a magnitude below 0.62 — so *the entire faint tier vanishes* and only ~41 of
200 stars draw, all of them tier 1 or above. That is not a smaller version of
the new-moon frame, it is a different frame with a different mix:

| | visible | tier 0 | tier 1 | tier 2/3 |
|---|---|---|---|---|
| new moon | 200 | 156 | 21 | 23 |
| 78% lit | 41 | 0 | 18 | 23 |

Useful in its own right — it isolates the bright tiers perfectly — but never
compare it against the new-moon numbers at the top of this document.


**Connect IQ keeps stored property values across a sideload of the same app ID.**
Changing a default in `resources/properties.xml` does nothing on a watch that
already has the face installed — it silently keeps the old value. This is the
device-side twin of `docs/simulator-property-reset.md`. It burned two
measurement rounds: `StarCount` went 200 → 120, `bg` came back identical at
108 ms, and the count had simply never changed.

For a test build, patch the assignments in `Settings.load` directly and restore
the file after the build. Nothing stored can then win:

```powershell
$c = $c -replace 'starCount\s*=\s*numberOr\("StarCount",[^;]*;',  "starCount = 200;"
$c = $c -replace 'background\s*=\s*numberOr\("Background",[^;]*;', "background = 0;"
$c = $c -replace 'debugTimeOffsetDays\s*=\s*floatOr\("DebugTimeOffsetDays",[^;]*;', "debugTimeOffsetDays = $offset;"
```

**`DebugTimeOffsetDays` shifts only the astronomy clock, not the displayed date**
(`MoonPhaseAnalogView.mc:310`). A build parked on new moon still shows today's
real date — that is correct, not a failed offset. The comment in
`properties.xml` claiming "the displayed time moves with it" is wrong.

**The offset is relative to the watch's clock, not the build machine's.** A watch
whose clock was 12 days behind turned a new-moon build into a 92%-lit one, which
looked exactly like the offset having failed. If the phase looks wrong, read the
date complication first.

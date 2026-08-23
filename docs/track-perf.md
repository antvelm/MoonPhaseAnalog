# The `track` section — measured

What `Dial.drawSecondTrack` costs, what the candidate fixes actually cost, and
why the fix this document used to propose would have made the frame **three to
five times worse**. Measured 2026-08-23 on branch `v2`, in the Venu 3
simulator, with `source/TrackBench.mc`.

---

## The number

**`track` ≈ 15 ms on a Venu 3.** Whole frame is **84 ms at full moon, 140 ms at
new moon** (device, current release code). So the track is ~11% of the worst
frame and ~18% of the best one.

## What it draws

`Dial.drawSecondTrack`, 60 positions round the rim at `R_SECOND = 0.94`:

- `dc.fillCircle(x, y, r)` per position
- `r` is `scaled(DOT_MINOR=2)` or `scaled(DOT_MAJOR=3)`; both round to 2 and 3
  on venu3 (r=227) *and* venu3s (r=195)
- with `ShowSecondNumerals` on — the default — the twelve five-marks draw a
  rotated label instead of a dot, so the baseline is **48 circles + 12 label
  blits**
- the comet trail and the rainbow wave recolour dots per second, so whatever
  replaces the circle still has to take an arbitrary per-dot colour

`Dial.drawOrbitRing` is the same primitive: **72** `fillCircle`s at r=1. It is
**off by default** (`ShowOrbitRing=false`) and lands in the `bg` section.

---

## What each primitive costs

`source/TrackBench.mc`, Venu 3 simulator, 21 rounds × the per-arm call budget
(18,900 calls for most arms). Set `TrackBench.ENABLED = true` and build with
`.\run-simulator.ps1 -Perf` to reproduce; it runs on the watch too.

| primitive | µs per call |
|---|---|
| `setColor` | **4.2** |
| `fillRectangle` 4×4 or 5×3 | **11.9** |
| `drawBitmap` 5×5 sprite | **13.5** |
| `drawLine` 3 px, **anti-alias off** | **12.7** |
| `drawLine` 3 px, **anti-alias on** | **85.4** |
| `fillCircle` r=2, **anti-alias off** | **124** |
| `fillCircle` r=2, **anti-alias on** | **393** ← what ships |
| `fillCircle` r=3, anti-alias on | 441 |
| `fillRoundedRectangle` 5×5 r=2 | 145 |
| `drawBitmap2` + transform + bilinear (a numeral) | 166 |
| `drawBitmap` 64×64 | 414 |
| `drawBitmap` 227×227 | ~5,300 |
| `drawBitmap` 454×454 (full screen) | **21,600** |

Composite discs, per dot:

| dot as | calls | µs |
|---|---|---|
| `fillCircle` r=2, AA | 1 | 393 |
| 5 × `drawLine` rows, AA | 5 | 403 |
| 7 × `drawLine` rows, AA (r=3) | 7 | 567 |
| 3 × `fillRectangle` spans | 3 | 36 |
| 1 × `fillRectangle` 4×4 | 1 | 12 |

Three things fall out of this:

1. **Anti-aliasing is most of what a primitive costs**, and `onUpdate` turns it
   on for the whole frame (`dc.setAntiAlias(true)`, right after `clear`). It is
   6.7× on a stroke and 3.2× on a filled circle.
2. **`drawLine` is not the cheap primitive.** With AA on it is only 4.6× cheaper
   than a whole `fillCircle`, so a five-row stroked disc costs *the same as the
   circle it replaces* and a seven-row one costs more.
3. **A blit is per-call up to about 64 px and per-pixel above it** —
   0.10 µs/px, dead linear from 64×64 to 454×454.

---

## The fix this document used to propose is a regression

The previous draft said: rasterise the disc as horizontal `drawLine` rows
instead of calling `fillCircle`, on the strength of a benchmark arm that had
timed a stroked r=2 disc at 4.7× cheaper than a sprite.

**Do not do this.** Rows are 403 µs against `fillCircle`'s 393 — no cheaper at
all in pixel terms — and they turn 48 draw calls into 240. On the watch, where
cost is per call (below), that is the `track` section going from 15 ms to
somewhere near 60.

The old arm was not wrong, it was measured **with anti-aliasing off**. Same for
the primitive table in [starfield-perf.md](starfield-perf.md): its `drawLine`
6.4 µs and `fillCircle` r=2 139 µs line up with the AA-off column here, not
with the frame the code actually draws in.

---

## The device is per Dc call, not per pixel

There is no watch in this loop, so this is inferred rather than measured — but
it is inferred from two numbers this repo already took on hardware, and they
only fit one model.

| section | device | draw calls | µs per call |
|---|---|---|---|
| `bg`, starfield at 200 stars, new moon | 98 ms | 312 strokes + 44 blits = 356 | **275** |
| `track`, default settings | 15 ms | 48 `fillCircle` + 12 label blits = 60 | **250** |

In the simulator those same two workloads differ by 4.6× per call. On the watch
they come out **within 10% of each other**. Try to fit
`device = C + k × simulator` to both and `k` comes out negative — there is no
positive per-pixel term that satisfies them. The Venu 3 is an AMOLED with
hardware 2D acceleration, so the plausible reading is that the rasterising is
free and what you pay for is crossing from the VM into the driver, about a
quarter of a millisecond a time, whatever you asked it to draw.

State calls are the exception and are much cheaper: the starfield work stripped
~380 `setColor`/`setPenWidth` calls for 10 ms, which is ~26 µs each.

**Consequence for the track: no change of primitive helps.** One
`fillRectangle` instead of one `fillCircle` is one call either way. Three
rectangles, or five strokes, is three or five times the calls. The only lever on
this section is *drawing fewer things*, and 60 marks round the rim is the
design.

---

## What the alternatives look like

Four builds, same crop of the ring at 12 o'clock, magnified 5×:
[screenshots/track-dots/compare-dots.png](../screenshots/track-dots/compare-dots.png).

- **`fillCircle`, AA on** (ships) — round, soft-edged, reads as ~6 px.
- **`fillCircle`, AA off** — visibly *smaller and weaker*. The anti-aliased
  fringe is carrying real apparent size on an AMOLED; taking it away shrinks the
  mark. This is the look cost the old draft warned about, and it is worse than
  expected.
- **Rectangle spans** — round, hard-edged, holds its weight. The best-looking
  of the cheap options, and the one to reach for if a future device turns out to
  be per-pixel after all.
- **Square** — plainly square at this magnification. A different design, not a
  cheaper version of this one.

---

## What changed

One thing, and it is small: `drawSecondTrack` now sets the colour only when it
changes, instead of once per dot.

Almost the whole ring is one colour — everything the comet is not lighting is
`Theme.TICK_DIM` — so this takes the ring from 48 `setColor` calls to a dozen or
so awake, and from 60 to **one** in low power, where the comet is off and the
numerals are hidden. At ~26 µs a state call that is around 1 ms awake and 1.5 ms
always-on. The rainbow wave gives every position its own colour and the check
simply never fires there.

No visual change: verified by screenshot, including the dots either side of a
numeral, which is where it would show if `drawBitmap2` disturbed the Dc colour.
It does not.

Static footprint: +19 bytes.

---

## The bigger fish this turned up: starfield tier 0

Not the track, but it came out of the same table and it is worth more than
everything above put together.

`drawStarSprite` draws tier 0 — **156 of 200 stars, 312 of the field's 356 draw
calls** — as two `drawLine`s. [starfield-perf.md](starfield-perf.md) rejected a
sprite there on the grounds that "at 12.8 µs it is already cheaper than the
~39 µs any blit costs, so a sprite there is a 3× *loss*".

That comparison was made with anti-aliasing off. In the frame as it actually
draws:

| tier 0 as | calls | µs (sim) |
|---|---|---|
| 2 × `drawLine`, AA on | 2 | **171** |
| 1 × `drawBitmap` 3×3 or 5×5 | 1 | **13.5** |

**Both cost models agree this is a win**, which is what makes it worth trying:
12× on the simulator's per-pixel model, and still 2× on the device's per-call
model, because it halves tier 0's call count. On the per-call model that is
`bg` going from ~98 ms to ~57 ms at 200 stars — bigger than the entire track
section, twice over.

It costs nothing in looks: a 3 px cross sprite is the same shape as the two
strokes. `resources/drawables/small_star_3x3.png` already exists. The dash that
was rejected on looks was a *different* proposal — one stroke instead of two —
and that rejection still stands.

Unverified on hardware. Do this one next, and read `bg` on the watch.

---

## Before you measure anything

Five ways to waste a round, all of them already paid for:

1. **The simulator cannot time a section.** `System.getTimer()` there resolves
   to ~15.6 ms, so every section reads 0/15/16/31/32 and nothing else. Section
   timings are **device-only**. To measure in the simulator, batch it — which
   is what `TrackBench` does.
2. **The watchdog is enforced in the simulator too.** 240,000 VM instructions
   per callback. A batch big enough to time in one frame trips it and the app
   dies with *"Watchdog Tripped Error - Code Executed Too Long"*. `TrackBench`
   runs one arm per frame and accumulates across frames for this reason.
3. **Benchmark in the state the frame draws in.** `onUpdate` sets
   `setAntiAlias(true)` before anything else. An arm that runs without it will
   tell you strokes are six times cheaper than they are, which is exactly how
   the wrong fix got into this document.
4. **Sideloading keeps stored property values.** Editing
   `resources/properties.xml` does nothing on a watch that already has the face.
   Patch the assignments in `Settings.load` directly for a test build.
5. **`loadResource` returns a `ResourceReference`, not the bitmap.** Call
   `.get()` and hold that, or every draw pays a graphics-pool resolve. See
   `Dial.lockedBitmap`.

## Order of work

1. **Tier 0 as a sprite** (above). Read `bg` on the watch before and after.
2. Confirm the per-call model directly while you have the watch in hand: build
   with `TrackBench.ENABLED = true` and compare `ln3aa` against `bl5` and
   `c2aa` on the wrist. If the watch reproduces the simulator's spread, the
   per-call model is wrong and the rectangle-span disc is worth 10 ms on the
   track after all.
3. Leave the track dots alone otherwise.

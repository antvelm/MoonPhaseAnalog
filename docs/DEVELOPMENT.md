# Development

How Moon Phase Astro is put together: the module map, the constants worth
turning, what the frame costs on hardware, and the Connect IQ limits that shaped
all of it. [`README.md`](../README.md) is the user-facing description; this is
the one to read before changing code.

State as of 2026-08-25, branch `v2`. Both sizes build clean at **31.9 kB static,
24.3% of the 131,072-byte limit**, leaving ~99 kB of runtime heap.

---

## Layout

| Path | Purpose |
|---|---|
| `manifest.xml` | App metadata: venu3 + venu3s, min API 5.2.0, `Positioning` permission |
| `monkey.jungle` | Build config; excludes `:perf` so the overlay is off by default |
| `perf.jungle` | Layered on top to turn the overlay on |
| `source/MoonPhaseAnalogApp.mc` | App entry point; invalidates `Settings` on change |
| `source/MoonPhaseAnalogView.mc` | Layout, frame order, complications, hands geometry |
| `source/Dial.mc` | Second track, numerals, hour marks, comet, starfield, zodiac |
| `source/Hands.mc` | The hand silhouette, its colour and its hollow |
| `source/MoonDial.mc` | Moon shading, eclipse looks, the phase-bucket cache |
| `source/MoonPhase.mc` | Phase and eclipse detection — no UI |
| `source/EclipseData.mc` | **Generated**: 93 eclipses, 2025-01-01 to 2045-08-27 |
| `source/SkyPosition.mc` | Solar/lunar altitude and the GPS visibility gate |
| `source/Zodiac.mc` | Star patterns and joins for the 12 constellations |
| `source/RainbowWave.mc` | The recurring wave and its schedule |
| `source/Settings.mc` | Cached, range-guarded property access |
| `source/Complications.mc` | Date and heart-rate lookups, each guarded |
| `source/Theme.mc` | The whole palette, plus HSV and dimming helpers |
| `source/Perf.mc` | Optional on-screen frame breakdown (`:perf` / `:noperf`) |
| `source/TrackBench.mc` | Primitive-cost benchmark; source of the perf docs' numbers |
| `source/EclipseTest.mc` | 9 on-watch unit tests (`:test` builds) |
| `source/WaveTest.mc` | 3 on-watch unit tests for the wave schedule |
| `resources/` | Strings, drawables, `properties.xml`, `settings.xml` |
| `tools/` | Generators, validators, screenshot automation |
| `docs/` | This file, the perf write-ups, the eclipse catalogue |

### The frame

`MoonPhaseAnalogView.onUpdate` runs once a second while awake and owns the
order; everything else draws. The sections match `Perf.SECTIONS` one for one, so
adding a `Perf.mark()` means adding a label there too — the pairing is
positional.

```
setup → phase → wave → clear → bg → track → marks → cplx → moon → hands
```

Two things are deliberately taken once at the top and threaded down: the epoch
second, and the phase fraction. The starfield and the moon disc must agree about
the phase, and the eclipse lookup must agree with both — taking the clock twice
is how a debug time offset ends up moving the moon but not the sky.

---

## Tuning

The proportions are gathered into `TUNING` blocks rather than scattered.

| What | Where |
|---|---|
| Ring radii (`R_SECOND` 0.94, `R_HOUR` 0.78, `R_ORBIT` 0.60) | `Dial.mc`, top |
| Second-numeral font and scale (`SEC_LABEL_FONT`, `SEC_LABEL_SCALE`) | `Dial.mc` |
| Hour fonts and tick lengths (`HOUR_FONT`, `HOUR_TICK_*_LEN`) | `Dial.mc` |
| Tick dot radii (`DOT_MINOR`, `DOT_MAJOR`) | `Dial.mc` |
| Milky Way band shape (`MW_ANGLE`, `MW_BOW`, `MW_WIDTH`, `MW_SHARE`, `MW_SPAN`) | `Dial.mc` |
| Moonlight wash (`MOON_FLOOR`, `MOON_WASH`, `STAR_LEVEL_MIN`) | `Dial.mc` |
| Complication placement (`R_SIDE`, `R_MOON`) and fonts | `MoonPhaseAnalogView.mc`, top |
| Hand lengths and widths | `MoonPhaseAnalogView.drawHands` |
| Hollow floors (`MIN_RIM`, `MIN_CORE`), low-power dimming (`LOW_POWER_LEVEL`) | `Hands.mc` |
| Moon gradient (`LEVELS`, `STEP_PX`, `LIMB_FLOOR`, `RIM_FADE`) | `MoonDial.mc` |
| Every colour | `Theme.mc` |

`FONT_XTINY` is the smallest built-in font. To go below it, lower
`Dial.SEC_LABEL_SCALE` — the labels are pre-rendered once and blitted through an
affine transform, so the scale costs nothing at runtime.

### Features currently switched off

Three flags are `false` in the shipped source. Each is a one-line change, and
each is off for a reason worth knowing before flipping it back.

| Flag | Effect while false |
|---|---|
| `RainbowWave.ENABLED` | The view skips `setup()`/`update()`, so the wave never goes active and every `tint()` falls straight through. The schedule logic and its unit tests are untouched. |
| `Dial.TWINKLE` | Tier-3 stars keep their sprite and hold still instead of pulsing per second — and, since the pulse was the only thing keeping them off the colour cache, they rejoin the cached path. |
| `TrackBench.ENABLED` | The primitive benchmark does not run. It only compiles into `:perf` builds anyway. |

The wave and the twinkle were both switched off in the same pass while trimming
the frame; the settings for the wave remain visible in Garmin Connect, so the
README says plainly that toggling it does nothing in this build.

---

## Performance

A watch face gets one `onUpdate` per second while the screen is awake, so the
frame time *is* a CPU duty cycle: 100 ms is 10% of every waking second, and that
percentage is what the battery pays. The hard ceiling is elsewhere — Connect
IQ's watchdog counts **240,000 VM instructions per callback** — and draw-heavy
code does not approach it. This is a battery problem, not a crash risk.

Current budget on a Venu 3, at the default `StarCount` of 120:

| | |
|---|---|
| Whole frame, full moon | **60 ms** |
| Whole frame, new moon (every star drawn) | **100 ms** |

The 40 ms between them is the starfield and nothing else. Moonlight is the only
thing that differs: at full moon about a dozen stars survive the cutoff, at new
moon all 120 draw. Everything else on the dial costs the same either way, which
makes the full-moon figure the floor the rest of the face sits on.

**Draw calls are the entire cost.** The Monkey C arithmetic around them — array
indexing, the loops, the trigonometry — is noise by comparison. Any optimisation
that does not remove a `dc.` call is not an optimisation. The cost is linear in
the number of stars, so `StarCount` is the one setting that moves the budget.

> The per-section model in [`starfield-perf.md`](starfield-perf.md) and
> [`track-perf.md`](track-perf.md) — a ~66 ms non-starfield floor,
> `bg ≈ 0.52 × StarCount − 7` ms, ~0.26 ms per draw call — was measured
> 2026-08-23, before the frame came down to the figures above. The shape still
> holds; the constants have moved, and re-deriving them means another overlay
> run. The per-primitive µs table below is a property of the hardware and is
> unaffected.

The corollaries that took measurement to learn:

- `fillCircle` r=2 with anti-aliasing on costs **393 µs**; the same call with AA
  off costs 124 µs, and a 5×5 `drawBitmap` costs 13.5 µs. An earlier version of
  `docs/track-perf.md` proposed a "fix" that would have made the frame three to
  five times worse, on the strength of a table measured with AA off.
- A full-screen `drawBitmap` is ~21,600 µs. Compositing the dial into an
  offscreen buffer is not available at this budget.
- `setColor` is 4.2 µs, so runs of same-coloured dots are worth grouping —
  `drawSecondTrack` takes the ring from 60 `setColor` calls to about a dozen.

Three caches carry most of the weight:

- **The moon disc** is a pure function of phase, eclipse and awake state, and the
  terminator moves one pixel every 3.3 hours. It renders into a bitmap bucketed
  at `PHASE_STEPS` = 256, which is roughly **nine re-renders a day** instead of
  86,400. Eclipses stay uncached on purpose: rare, genuinely changing minute to
  minute, and the corona would size the bitmap for a case that almost never runs.
- **The second numerals** are rasterised once in `onLayout` and blitted.
- **The hue wheel** is a 60-entry constant table; `hsvToColor` never runs on the
  draw path for the track.

### The overlay

`source/Perf.mc` draws a per-section millisecond breakdown, a cur/peak total and
the live heap. It costs 62 bytes of data and no code in a normal build — every
entry point exists twice, `(:perf)` and `(:noperf)`, and one annotation is
excluded at compile time.

```powershell
.\build.ps1 -Perf            # both sizes, overlay compiled in
.\run-simulator.ps1 -Perf    # same, in the simulator
build-perf.bat               # the same thing, double-clickable
```

> The `.prg` files these leave in `bin\` have the overlay drawn across the dial.
> Run a plain `.\build.ps1` to overwrite them before sideloading to a watch you
> actually wear.

Measure the starfield **at new moon** — that is the worst case, with the
moonlight cutoff at zero and every star above it. At 80% lit only about a fifth
of the field draws and the number means nothing.

---

## Tests

```powershell
.\tools\run-tests.ps1              # 12 on-watch unit tests in the simulator
.\tools\check-eclipse-math.ps1     # validate the computed eclipse fallback
```

`EclipseTest.mc` drives off every row of the table rather than a hand-picked
few, and includes a strictly-ascending check on `DAYS[]` — a transcription typo
is the likeliest failure mode, and the binary search misbehaves silently without
it. `WaveTest.mc` walks a whole day an hour at a time and pins the slot
behaviour, including the fact that a slot is only spent once its wave has run
end to end.

### Eclipse math

The computed fallback is validated, not assumed. `check-eclipse-math.ps1` runs
the same algorithm over all 93 catalogued events and diffs it against the table:

| Check | Result |
|---|---|
| Events detected | 92 / 93 |
| Correct type | 89 / 92 |
| Max timing error | 1.1 min |
| Max lunar magnitude error | 0.011 |
| False positives | 0 of 14,945 samples |

The miss is 2027-07-18, a very shallow penumbral outside Meeus' node test, which
is not rendered either way. The three type disagreements are boundary cases
(annular vs hybrid, total vs partial) where gamma sits within a thousandth of
the limit.

Inside the table's span the table is authoritative: a date in range with no
table hit genuinely has no eclipse, so the computed path is never consulted
there.

---

## Generated files

Never edit these by hand:

| File | Generator |
|---|---|
| `source/EclipseData.mc` | `tools\gen-eclipse-data.ps1` from `docs/eclipse-events.tsv` |
| `docs/eclipse-test-dates.md` | `tools\gen-eclipse-doc.ps1` from the same TSV |
| `resources/drawables/star_*.png` | `tools\gen-star-sprites.py` |

---

## Screenshots

`tools\gen-feature-screenshots.ps1` shoots every user-facing setting value in the
simulator, cropped to the 454×454 display so the PNGs drop straight into the
README.

```powershell
.\tools\gen-feature-screenshots.ps1 -VerifyOnly            # 2 shots, sanity check
.\tools\gen-feature-screenshots.ps1                        # the full batch, ~60 shots
.\tools\gen-feature-screenshots.ps1 -Only "^zodiac-"       # one group
.\tools\gen-phase-walk.ps1                                 # 8 steps round the month
.\tools\montage.ps1                                        # stitch the walk into strips
```

The four shots the README uses are the four `-Only` can name explicitly:

```powershell
.\tools\gen-feature-screenshots.ps1 -Only "^(half-moon|new-moon-stars|eclipse-lunar|eclipse-solar)$"
```

Both generators park the hands at **10:10** via the `DebugClock` property — the
classic watch-photography pose, where the hands frame the dial instead of
covering it. `DebugClock` is read as decimal digits (`HHMMSS`), moves nothing but
the hands and the comet, and is `-1` for the real time.

The seconds differ per shot on purpose. Spectrum hands take their colour from
`Theme.hueForSecond`, which is `sec / 60 × 360°`, so the second in the frozen
clock *is* the hand colour: the README's four shots sit at :05, :20, :35 and :45
and come out orange, green, blue and violet. There is no other way to show that
sweep in a still.

A phase is pinned the same way, through `DebugTimeOffsetDays`: the script works
out how many days ahead the target phase fraction falls, mirroring
`MoonPhase.fractionAt`, so `half-moon` and `new-moon-stars` are exact rather than
"about a week from now".

Two traps, both learned the hard way and written up in
[`simulator-property-reset.md`](simulator-property-reset.md):

1. **The simulator caches property defaults forever.** A fresh read needs
   `simulator.exe` *and* `shell.exe` killed and `simulator.ini` deleted before
   each relaunch. Both generators do this per shot, which is most of why a full
   batch takes half an hour.
2. **The window is briefly narrower than the display it is about to render.**
   Screenshot it there and you get a sliver of chrome. The capture retries until
   the face box fits, which is also exactly the condition the crop needs.

Both scripts rewrite `resources/properties.xml` while they run and restore it on
exit — including on failure, but *not* if the process is killed. If a run is
interrupted, `git checkout -- resources/properties.xml` before building anything
else.

The crop geometry (face centre 327,481 at r=227 inside the window) is fixed, and
shared with `montage.ps1` and `crop-track.ps1`. If the simulator ever moves the
face, the crop lands off-centre rather than failing — check the first shot of a
batch by eye.

---

## Settings plumbing

Adding a setting means touching four files, in this order:

1. `resources/properties.xml` — the property and its **default**, with a comment
   explaining what the value means. This is the reference documentation for the
   setting; nothing else in the tree explains it as fully.
2. `resources/settings/settings.xml` — the Garmin Connect entry.
3. `resources/strings/strings.xml` — its title and prompt.
4. `source/Settings.mc` — a `var`, plus a guarded read in `load()` with the same
   range the settings entry allows.

`Settings` caches every value at module level and only reloads when
`App.onSettingsChanged` invalidates it: a watch face reads these 86,400 times a
day, and an unguarded read of a missing property takes the face down on-watch
rather than falling back.

> Note: a few `Settings.load` fallbacks do not match the defaults in
> `properties.xml` (`CometMode`, `HourMarkStyle`, `HandHollow`). The fallback
> only applies when a stored value is missing or malformed, so a normal install
> never sees the difference — but they are documented as being the same value
> and should be reconciled.

Settings that change cached geometry cannot rebuild it in `onSettingsChanged` —
there is no `Dc` there. `MoonPhaseAnalogView.refreshCaches` handles that on the
next draw instead.

### Sideloading and property defaults

Sideloading a `.prg` **never applies new `properties.xml` defaults** — the watch
keeps whatever it stored the first time the app was installed. For a test build
that must start from a known state, patch `Settings.load` directly rather than
trusting the XML.

---

## Platform limits worth knowing

Every one of these cost real time to discover.

1. **One frame per second.** `onUpdate` is called once a second while awake. The
   rainbow wave is an 8-frame sequence, not a smooth animation, and its band is
   made wide enough that each step reads as motion rather than a jump.
2. **`drawBitmap2` refuses palettised bitmaps when a transform is supplied** —
   *"Source must not use a color palette"*. The rotated second labels and the
   star sprites therefore need `automaticPalette="false"`.
3. **The watchdog kills per-pixel work.** The first moon gradient tested 6 maria
   per sample across ~1,900 samples and tripped it; it was restructured into
   run-length spans plus a separate maria pass.
4. **Monkey C float literals are 32-bit `Float`.** Julian dates need `Double`
   (`2451550.09766d`) and angles must be folded into 0–360 before `Math.sin`.
   Without this, eclipse detection silently found 46 of 93 events.
5. **`Number` is 32-bit**, so raw epoch-second arithmetic overflows in 2038 while
   the table runs to 2045. All eclipse math runs in days-since-2000.
6. **The memory budget is 128 kB** for code, data and heap combined. `build.ps1`
   prints the static half; the overlay prints what is live on top of it.
7. **`Dc` has no clipping and no `drawPolygon`.** The hollow hand is painted back
   in the dial's black rather than left see-through, and outline mode walks the
   polygon edges by hand.
8. **Hold resources, not `ResourceReference`s.** The graphics pool unloads and
   reloads references as memory moves, so a bare reference makes every
   `drawBitmap2` pay a pool resolve — invisible in the simulator, expensive on
   the watch.
9. The manifest permission id is `Positioning`, not `Positions`.

---

## Further reading

| Doc | What it covers |
|---|---|
| [`starfield-perf.md`](starfield-perf.md) | The starfield's cost model, what paid and what did not |
| [`track-perf.md`](track-perf.md) | Per-primitive costs on a Venu 3, and the "fix" that would have hurt |
| [`milky-way-starfield.md`](milky-way-starfield.md) | The band's design, and the plan it came from |
| [`milky-way-starfield-summary.md`](milky-way-starfield-summary.md) | What shipped, with the stars-per-phase table |
| [`eclipse-test-dates.md`](eclipse-test-dates.md) | Generated: every catalogued eclipse, with the offsets to park on it |
| [`simulator-property-reset.md`](simulator-property-reset.md) | Why the simulator serves stale properties, and the sequence that fixes it |
| [`redesign-recap.md`](redesign-recap.md) | The 2026-08-22 dial rework. Describes the seven hand styles, which have since been replaced by the single baton — read it as history |
| [`../plans/dial-redesign-animation-options.md`](../plans/dial-redesign-animation-options.md) | Animation options explored for the dial |

# Dial redesign — recap

Session of 2026-08-22. Covers the dial rework, the hand selector, the eclipse
system, the rainbow wave, and the zodiac backgrounds.

Status: both sizes build clean (debug and release), all 9 on-watch unit tests
pass, runs in the simulator at **40.8 / 123.9 kB**. Nothing is committed — all
changes are in the working tree.

---

## What was built

### Dial

- 12 bright white **hour numerals** at 0.76R.
- Grey **five-second numerals** oriented radially on the **outermost** ring at
  0.94R, sharing that ring with the tick dots: a numeral replaces the dot it
  would have sat on, so there is one ring, not two.
- `dc.drawText` cannot rotate, so the 12 labels are rasterised **once** into
  buffered bitmaps in `onLayout` and blitted through an `AffineTransform`
  thereafter. Nothing is re-rendered per frame.

### Moon

- Hard terminator with a smooth **limb-darkening gradient** toward the edge, so
  the disc reads as a sphere.
- The lit span is computed exactly (`x = w·cos(phase)`, the terminator ellipse)
  rather than found by sampling, which keeps the day/night edge crisp instead of
  quantised to the sample grid.
- Maria are clipped on the same line and shaded with the surface, so they darken
  toward the limb instead of sitting on top as flat patches.

### Hands

Seven silhouettes — Dauphine, Baton, Syringe, Skeleton, Breguet, Alpha, Sword —
selected by a setting, so the final look can be picked by eye on the watch.

### Eclipses

- All **93 events, 2025–2045**, from the NASA GSFC catalogue, generated into
  `source/EclipseData.mc` as three flat parallel arrays.
- Past 2045 the face computes them on the watch (Meeus, *Astronomical
  Algorithms* 2nd ed., ch. 49 and 54).
- The table is authoritative inside its span: a date in range with no table hit
  genuinely has no eclipse, so the computed path is never consulted there.
- Optional **GPS visibility gate** using the last known fix only — it never
  requests one, so there is no battery cost — and it **fails open**: no position
  means show the eclipse rather than hide it.
- Result is cached and only recomputed when the minute rolls over.
- Penumbral lunar eclipses are detected but deliberately not rendered; they look
  like nothing in the sky.

### Also

`FRI 27` date, larger heart-rate block, layered star sprites, 12 zodiac
constellations (star patterns only — no glyphs or figures), the daily rainbow
wave, and three comet-trail modes.

---

## Tuning knobs

| Knob | File | Constant |
|---|---|---|
| Second-numeral size | `source/Dial.mc` | `SEC_LABEL_SCALE`, `SEC_LABEL_FONT` |
| Second-track radius | `source/Dial.mc` | `R_SECOND` |
| Hour numerals | `source/Dial.mc` | `R_HOUR`, `HOUR_FONT` |
| Tick dot sizes | `source/Dial.mc` | `DOT_MINOR`, `DOT_MAJOR` |
| Date number | `source/MoonPhaseAnalogView.mc` | `DATE_FONT`, `DOW_FONT` |
| Pulse number + icon | `source/MoonPhaseAnalogView.mc` | `HR_FONT`, `HR_ICON` |
| Complication positions | `source/MoonPhaseAnalogView.mc` | `R_SIDE`, `R_MOON` |
| Moon gradient | `source/MoonDial.mc` | `LEVELS`, `STEP_PX`, `LIMB_FLOOR` |
| All colours | `source/Theme.mc` | |

`FONT_XTINY` is the smallest built-in font. To go below it, lower
`Dial.SEC_LABEL_SCALE` — the labels are pre-rendered, so scaling is free at
runtime.

---

## Verification

The fallback eclipse math is **validated, not assumed**.
`tools/check-eclipse-math.ps1` runs the same algorithm over all 93 known events
and diffs it against the table:

| Check | Result |
|---|---|
| Events detected | 92 / 93 |
| Correct type | 89 / 92 |
| Max timing error | 1.1 min |
| Max lunar magnitude error | 0.011 |
| False positives | 0 of 14,945 samples |

The one miss is 2027-07-18, a very shallow penumbral that falls outside Meeus'
node test and is not rendered either way. The three type disagreements are
boundary cases (annular vs hybrid, total vs partial) where gamma sits within a
thousandth of the limit.

```powershell
.\tools\run-tests.ps1              # 9 on-watch unit tests in the simulator
.\tools\check-eclipse-math.ps1     # validate the computed fallback
```

The unit tests drive off every row of the table rather than a hand-picked few,
and include a strictly-ascending check on `DAYS[]` — a transcription typo is the
likeliest failure mode and the binary search misbehaves silently without it.

---

## Platform limits hit along the way

Worth knowing before changing this code:

1. **Animation ceiling is 1 frame per second.** Garmin calls `onUpdate` on a
   watch face once per second. The rainbow wave is a 12-frame sequence, not a
   smooth animation.
2. **`drawBitmap2` refuses palettised bitmaps when a transform is supplied.**
   The rotated second labels therefore cannot use `:palette`. This crashed the
   first build with *"Source must not use a color palette"*.
3. **The watchdog kills per-pixel work in `onUpdate`.** The first moon gradient
   tested 6 maria per sample across ~1,900 samples and tripped it. It was
   restructured into run-length spans plus a separate maria pass.
4. **Monkey C float literals are 32-bit `Float`.** Julian dates need `Double`
   (`2451550.09766d`), and angles must be folded into 0–360 before `Math.sin`.
   Without this the eclipse detection silently found 46/93 events.
5. **Memory budget on Venu 3 is 123.9 kB**, not the ~256 kB I had assumed.
6. **`Number` is 32-bit**, so raw epoch-second arithmetic overflows in 2038
   while the table runs to 2045. All eclipse math runs in days-since-2000.
7. The manifest permission id is `Positioning`, not `Positions`.

---

## Open items

Raised near the end of the session and deferred:

- Heart-rate glyph could be larger relative to the now-smaller number.
- General visual tuning of the complication block.

Both new booleans default off as requested: **Comet crosses the numerals** and
**Show orbit ring**.

---

## Generated files

`source/EclipseData.mc` and `docs/eclipse-test-dates.md` are generated. Edit
`docs/eclipse-events.tsv` and re-run:

```powershell
.\tools\gen-eclipse-data.ps1
.\tools\gen-eclipse-doc.ps1
```

# Handoff — 2026-08-22 evening session

## What was asked
Screenshot every feature (zodiac signs × styles, hand styles, eclipse art,
etc.) as proof each works, using the Connect IQ simulator.

## What actually happened
Spent most of the session chasing a test-rig bug, not an app bug: property
changes in `resources/properties.xml` appeared to have no effect no matter
how the simulator was rebuilt/restarted, across three different automated
batch attempts. Root cause found and fixed — full writeup in
**[`docs/simulator-property-reset.md`](simulator-property-reset.md)**. Short
version: delete `%APPDATA%\Garmin\ConnectIQ\simulator.ini` before every
relaunch, or the simulator silently restores stale property values forever.
Also: kill `shell.exe` alongside `simulator.exe` (it holds the actual
runtime state), and use `PrintWindow` instead of `CopyFromScreen` for
screenshots (foreground-focus screen-scraping is flaky from a script).

**Read that doc before automating any more simulator screenshots** — it has
the exact reset sequence and two other traps (monkeydo blocks if called
directly; must use `Start-Process`).

## Confirmed working (verified visually, not just asserted)
- The property-reset fix itself (round-tripped a boolean true→false→true).
- Forced lunar eclipse now renders the copper/red moon correctly.
- Hand-style property changes render correctly (compared Dauphine vs
  Skeleton zoomed crops — real shape differences, not noise).

## Also done this session
- **Layout fix in `source/MoonPhaseAnalogView.mc`**: `drawHeartRate()`
  rewritten so the heart icon + number sit inline on one line (same
  height as the "SAT 22" date), matching `drawDay()`'s layout style
  instead of stacking the icon above the number. Verified visually.

## Not done — still pending
**No full screenshot set has been produced yet.** The one attempted
39-shot batch (hand styles × 7, zodiac × 24, starfield, eclipse × 2, comet
× 3, orbit ring, rainbow wave) was generated *before* the property-reset
fix, so it's invalid — do not reuse those files. None currently exist in
`screenshots/features/` that can be trusted; check whether that folder
still has the stale copies and either delete or clearly caveat them before
showing to the user again.

To regenerate correctly: reuse the scripting approach from this session
(build → kill simulator.exe + shell.exe → delete simulator.ini → launch →
wait for window handle → `Start-Process monkeydo` → wait → PrintWindow
screenshot) but this time it should actually vary the rendered output
between scenarios — verify at least one before/after pair before running
the full batch unattended, since that's the step that was skipped last
time and cost the whole session.

## State of the repo right now
- `resources/properties.xml`: restored to exactly what it was at session
  start (byte-identical) — still has the pre-existing uncommitted dev
  toggles `WaveTestMode=true`, `DebugEclipse=1` (not mine, were already
  there, left as found).
- `source/MoonPhaseAnalogView.mc`: has the intentional heart-rate layout
  change described above. No leftover debug `System.println` calls (all
  temporary debug logging added during investigation was removed).
- `source/MoonDial.mc`, `source/SkyPosition.mc`: untouched this session,
  pre-existing uncommitted WIP from before.
- Nothing was committed. Nothing pushed.
- `simulator.exe`/`shell.exe` killed clean at end of session.

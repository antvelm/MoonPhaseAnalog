# Connect IQ simulator: property defaults don't reload — here's why

If you change a default in `resources/properties.xml`, rebuild, and push to
the simulator, **the new default does not take effect**, even after fully
killing the simulator. This cost a long debugging session; here's the fix
and how it was found.

## Symptom

Rebuilding with a new property default (e.g. `HandStyle`, `DebugEclipse`,
`ShowHourNumerals`) and relaunching shows the *old* value, no matter how the
simulator is restarted. This affects **every property type** — number,
float, and boolean all showed it once tested with an actual before/after
value flip (not just "it looks the same," which is easy to misjudge from a
watch-face screenshot at a glance).

## Why killing `simulator.exe` isn't enough

`simulator.exe` (the GUI window) is not the whole story. Pushing an app
(`monkeydo`) spawns a separate `shell.exe` — the actual on-device runtime
that holds `Application.Properties` in memory. Killing only `simulator.exe`
leaves `shell.exe` running, and a new simulator window can end up talking to
that orphaned instance. **Kill both `simulator.exe` and `shell.exe`** before
every push if you need a truly fresh app state:

```powershell
Stop-Process -Name simulator -Force -ErrorAction SilentlyContinue
Stop-Process -Name shell -Force -ErrorAction SilentlyContinue
```

This is necessary but **not sufficient** — see the next section.

## The actual root cause: `simulator.ini`

Even after killing both processes and confirming (via `Get-Process`) that
neither exists before relaunching, the old property values still came
back. The fix: delete this file before relaunching the simulator:

```
%APPDATA%\Garmin\ConnectIQ\simulator.ini
```

It contains a line like:

```
DC041C900FA5428A96717905B5EC31DD=venu3
```

(the hex string is this app's id from `manifest.xml`, mapped to the last
device it ran on). As long as that line exists, the simulator treats the
app as "already installed" on that device and restores whatever property
values it saw the *first* time — exactly the real-device behavior where
`properties.xml` defaults only apply on a genuine first install, and later
rebuilds preserve the user's existing settings. Deleting `simulator.ini`
before each relaunch forces every push to be treated as a fresh install, so
new defaults actually take effect. No other file or registry key was found
to hold this state — extensive searches under
`%APPDATA%\Garmin`, `%LOCALAPPDATA%\Garmin`, and `HKCU` turned up nothing
that changed between test cycles.

Confirmed with a controlled round-trip: `ShowHourNumerals` true → false →
true, each with a full rebuild + `simulator.ini` deletion + relaunch in
between, read back correctly every time.

## The correct reset sequence, in order

1. Edit `resources/properties.xml`.
2. `.\build.ps1 -Debug` (or single-device build).
3. Kill `simulator.exe` and `shell.exe`, wait until both are actually gone.
4. Delete `%APPDATA%\Garmin\ConnectIQ\simulator.ini`.
5. Launch `simulator.exe`, wait for its window handle.
6. Push with `monkeydo.bat <prg> venu3` (via `Start-Process`, **not** a
   direct blocking call — see next section).
7. Wait a few seconds for the first render, then screenshot.

## Two more traps hit along the way

- **`monkeydo.bat` blocks forever if invoked directly** (`& $monkeydo ...`).
  It's designed to be fired and left running, not waited on synchronously.
  Always launch it with `Start-Process` (fire-and-forget); never call it
  with `&` or backticks and expect it to return.
- **Screen-scraping the simulator window (`CopyFromScreen` +
  `SetForegroundWindow`) is unreliable from an unattended script.** Windows
  can silently refuse `SetForegroundWindow` for a background-driven
  process, and when that happens the "screenshot" is just whatever was
  already on screen (sometimes a stale frame, sometimes solid black).
  Use `PrintWindow` with `PW_RENDERFULLCONTENT` (flag `2`) against the
  window handle instead — it captures the window's own content directly,
  regardless of z-order or focus, and was reliable across dozens of
  scripted cycles once adopted.

## Practical takeaway

Any script that cycles `properties.xml` values and expects each build to
render with fresh defaults **must** delete `simulator.ini` as part of the
reset between cycles, not just kill processes. Skipping this step doesn't
error — it just silently serves stale settings forever, which is very easy
to mistake for "this feature doesn't render" when it's actually a test-rig
problem, not an app bug.

# Moon Phase Astro - What to do next

Good morning. The watch face is written, compiles cleanly for both the Venu 3 and Venu 3S, and the moon-phase math is verified against known lunar dates. This file is your checklist to preview it and get it onto your watch.

Everything lives in `i:\Garmin watchfaces\MoonPhaseAnalog\`.

---

## 1. One thing you need to know first: your Java is broken

Your `java` on PATH is an Oracle "javapath" stub that crashes (exit code `0xC0000409`). Because of this:

- The normal `monkeyc` / `monkeydo` commands fail.
- The Garmin Monkey C editor extension (VS Code / Cursor) will also fail to build.

I worked around it by calling the compiler with the Java 8 runtime already on your machine (`C:\Program Files\Java\jre1.8.0_341`), and I baked that workaround into the build scripts below, so **you don't have to fix Java to use this project.**

If you want the editor extension and standard tooling to work later, install a modern JDK (Temurin/Adoptium 17 or 21) and make sure it comes first on PATH. That is optional and not needed for anything below.

---

## 2. Preview it in the simulator (optional, ~30 seconds)

From a PowerShell prompt in the project folder:

```powershell
cd "i:\Garmin watchfaces\MoonPhaseAnalog"
.\run-simulator.ps1            # or:  .\run-simulator.ps1 venu3s
```

This builds the face and opens it in the Connect IQ simulator. Use the simulator's
**Settings > Time** and power-mode toggles to watch the moon phase, the spectrum
second hand, and the always-on (low-power) look.

> If PowerShell blocks the script with an execution-policy error, run this once for
> the session: `Set-ExecutionPolicy -Scope Process -Bypass`

---

## 3. Build the files for your watch

```powershell
cd "i:\Garmin watchfaces\MoonPhaseAnalog"
.\build.ps1
```

This produces two signed files in `bin\`:

- `MoonPhaseAstro-venu3.prg`  - for the Venu 3 (45 mm)
- `MoonPhaseAstro-venu3s.prg` - for the Venu 3S (41 mm)

Use the one that matches your watch. Building for the wrong size produces a file the
watch silently refuses to install, so this is the easiest thing to get wrong.

(There are already working `.prg` files in `bin\` from my build, so if `build.ps1`
gives you any trouble you can sideload `bin\MoonPhaseAnalog.prg` for the Venu 3 right away.)

---

## 4. Put it on the watch

Full detail is in `INSTALL.md`. The short version, for Windows:

1. On the watch: **Settings > System > USB Mode > MTP**.
2. On the PC: **fully quit Garmin Express**, including its system-tray icon. If it is
   running, the watch will not appear.
3. Plug in the watch. It shows up in File Explorer as an MTP device. Enter your watch
   PIN if you use one.
4. Copy your `.prg` into the watch's **`GARMIN\APPS\`** folder.
5. Eject, unplug. Long-press the middle button > **Watch Face** > pick Moon Phase Astro.

**The `.prg` will disappear from `GARMIN\APPS\` after you reconnect. That is normal** -
current firmware moves installed apps into protected storage. It is installed.

---

## 5. If it misbehaves on the watch

The watch writes a crash log to `GARMIN\APPS\LOGS\CIQ_LOG.YML`. Copy it back to the PC
and it will name the file and line. The one thing the simulator does not enforce as
strictly as the watch is the 128 KB memory ceiling, but this face is fully procedural
and uses very little, so that is unlikely.

---

## What the face looks like

- Analog, pure-black background (real black on AMOLED).
- Monochrome geometric hour/minute hands (hollow white blades).
- The only colour is the **second hand**, whose hue sweeps the full spectrum once per
  minute, with a short comet tail of the same hue fading behind it on the tick ring.
- Sparse fixed starfield and a faint dotted orbit ring behind the hands.
- **Day of the month** at 3 o'clock, **heart rate** (with a small heart glyph) at 9 o'clock.
- **Moon-phase subdial** at 6 o'clock: a warm off-white disc with real lunar maria that
  are clipped by the terminator, so the craters appear and vanish correctly as the phase
  changes through the month.
- In always-on/low-power mode the colour and ornament drop away to a dim wireframe, and
  the whole face shifts a few pixels on a slow cycle to protect against burn-in.

To re-theme the whole thing, edit the constants at the top of `source/Theme.mc`.

---

## Project map

| File | Purpose |
|------|---------|
| `manifest.xml` | App metadata, targets venu3 + venu3s, min API 5.2.0 |
| `monkey.jungle` | Build configuration |
| `source/MoonPhaseAnalogApp.mc` | App entry point |
| `source/MoonPhaseAnalogView.mc` | All rendering (dial, hands, moon, complications) |
| `source/MoonPhase.mc` | Lunar phase math (no UI) |
| `source/Complications.mc` | Day + heart rate lookups |
| `source/Theme.mc` | Colour palette + hue helper |
| `resources/` | App name, 70x70 launcher icon |
| `build.ps1` | One-command build (works around broken Java) |
| `run-simulator.ps1` | Build + open in simulator |
| `developer_key.der` | Signing key (git-ignored; keep it, do not share it) |
| `INSTALL.md` | Detailed sideloading guide |

# Installing Moon Phase Astro on your Venu 3

## Build a file for the watch

The simulator build and the on-watch build are the same; the watch just needs a `.prg`
built for its exact device id. Use the provided script (it works around the broken
system Java automatically):

```powershell
cd "i:\Garmin watchfaces\MoonPhaseAnalog"
.\build.ps1
```

Output, in `bin\`:

- `MoonPhaseAstro-venu3.prg`  - Venu 3 (45 mm)
- `MoonPhaseAstro-venu3s.prg` - Venu 3S (41 mm)

Use the one matching your watch. Building for the wrong device id produces a file the
watch silently refuses to install - the most common mistake.

## Transfer it (Windows)

1. On the watch, go to **Settings > System > USB Mode** and set **MTP**. The alternative
   "Garmin" mode also works but prompts you on every connection.
2. **Fully quit Garmin Express on the PC**, including the system-tray icon. If Express is
   running it holds the USB connection and the watch will not appear.
3. Connect the watch by USB. On Windows it shows up in File Explorer as an MTP device -
   no third-party tool needed. (The "use OpenMTP" advice you will find online is a Mac
   problem; ignore it on Windows.)
4. If you use a device PIN, enter it on the watch, otherwise the filesystem stays locked.
5. Copy your `.prg` into the watch's **`GARMIN\APPS\`** folder.
6. Safely eject and unplug.

## Activate it

Long-press the middle button, choose **Watch Face**, and select Moon Phase Astro.

**Expect the `.prg` to vanish from `GARMIN\APPS\` after you reconnect.** This is not a
failure - current firmware moves installed apps into protected storage immediately. The
app is installed even though the file is no longer visible.

## Debugging on the watch

If the face fails to load or crashes, the watch writes a log to
**`GARMIN\APPS\LOGS\CIQ_LOG.YML`**. Copy it back to the PC; it names the offending file
and line. Most on-device-only failures come from the 128 KB memory limit, which the
simulator does not enforce as strictly.

## Removing it

Sideloaded apps cannot be uninstalled from the Connect IQ phone app. Use **Garmin
Express** on the PC, or just reinstall over the top with a rebuilt `.prg` of the same
app id (what you do while iterating).

## Faster iteration

Reflashing over USB for every change is slow. Do layout and rendering work in the
simulator (`.\run-simulator.ps1`), and only push to the watch to confirm the things the
simulator approximates poorly: always-on dimming, real AMOLED colour, and all-day battery.

## If you ever need to regenerate the signing key

The key in `developer_key.der` signs your builds. Keep it; do not share it. If it is ever
lost, make a new one (any watch you sideload to does not care that the key changed):

```powershell
& "C:\Program Files\Git\usr\bin\openssl.exe" genrsa -out developer_key.pem 4096
& "C:\Program Files\Git\usr\bin\openssl.exe" pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem -out developer_key.der -nocrypt
```

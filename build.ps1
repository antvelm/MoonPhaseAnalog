# Build the Moon Phase Astro watch face for both Venu 3 sizes.
#
# Why this script exists: the `java` on this machine's PATH is a broken Oracle
# "javapath" stub that crashes (exit 0xC0000409), so the normal `monkeyc`
# command and the Garmin editor extension fail. This script calls the Connect
# IQ compiler with a known-good JRE directly, sidestepping the broken stub.
#
# Usage:
#   .\build.ps1              # release builds for venu3 and venu3s -> bin\
#   .\build.ps1 -Debug       # debug builds (faster, larger, for the simulator)
#   .\build.ps1 -UnitTest    # debug build with the (:test) functions compiled in;
#                            #   run them with tools\run-tests.ps1
#   .\build.ps1 -Perf        # compile the on-screen frame-time / heap overlay
#                            #   in (source\Perf.mc). Never ship one of these.
#
# Every build prints its static memory footprint. A Venu 3 watch face gets
# 128 kB for code, data and runtime heap combined, so whatever the static
# figure leaves over is all the moon bitmap, the buffered dial and the star
# arrays have to live in.

param(
    [switch]$Debug,
    [switch]$UnitTest,
    [switch]$Perf
)

# The test functions are only emitted into a debug build.
if ($UnitTest) { $Debug = $true }

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- Locate the Connect IQ SDK ---
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$jar = Join-Path $sdk "bin\monkeybrains.jar"
if (-not (Test-Path $jar)) { throw "Compiler not found at $jar" }

# --- Find a working Java ---
# Preference: $env:CIQ_JAVA, then `java` on PATH (e.g. your Temurin install),
# then any JDK/JRE under Program Files. The broken Oracle "javapath" stub is
# auto-rejected because its version probe exits with a crash code. The probe
# output is fully suppressed so it does not print red stderr noise.
function Get-WorkingJava {
    $candidates = @()
    if ($env:CIQ_JAVA) { $candidates += $env:CIQ_JAVA }
    $onPath = (Get-Command java -ErrorAction SilentlyContinue).Source
    if ($onPath) { $candidates += $onPath }
    foreach ($glob in @(
        "C:\Program Files\Eclipse Adoptium\*\bin\java.exe",
        "C:\Program Files\Microsoft\jdk*\bin\java.exe",
        "C:\Program Files\Java\jdk*\bin\java.exe",
        "C:\Program Files\Java\jre*\bin\java.exe")) {
        Get-ChildItem $glob -ErrorAction SilentlyContinue | ForEach-Object { $candidates += $_.FullName }
    }
    foreach ($exe in $candidates) {
        if (-not $exe -or -not (Test-Path $exe)) { continue }
        $ok = $false
        try {
            $old = $ErrorActionPreference
            $ErrorActionPreference = 'SilentlyContinue'
            & $exe -version 2>&1 | Out-Null
            $ok = ($LASTEXITCODE -eq 0)
            $ErrorActionPreference = $old
        } catch { $ok = $false }
        if ($ok) { return $exe }
    }
    return $null
}
$java = Get-WorkingJava
if ($null -eq $java) { throw "No working Java runtime found. Install Temurin (Adoptium) JDK 21 and retry." }
Write-Host "Using Java: $java"
Write-Host "Using SDK:  $sdk"

$key = Join-Path $PSScriptRoot "developer_key.der"
if (-not (Test-Path $key)) { throw "Missing developer_key.der. See HANDOFF.md to regenerate it." }

New-Item -ItemType Directory -Force -Path bin | Out-Null

$modeLabel = if ($UnitTest) { "unit-test" } elseif ($Debug) { "debug" } else { "release" }
if ($Perf) { $modeLabel += "+perf" }

# perf.jungle overrides monkey.jungle's annotation exclusion, swapping the
# overlay's empty stubs for its real implementation.
$jungles = if ($Perf) { "monkey.jungle;perf.jungle" } else { "monkey.jungle" }

# What a watch face gets on both Venu 3 sizes, from the SDK's
# Devices\venu3\compiler.json. Code, data and runtime heap all come out of it.
$memoryLimit = 131072

foreach ($device in @("venu3", "venu3s")) {
    $out = "bin\MoonPhaseAstro-$device.prg"
    Write-Host "`nBuilding $device ($modeLabel) -> $out"
    # Build the argument list explicitly. Splatting a variable set from an `if`
    # expression is unsafe here: a single-element array like @("-r") gets
    # unwrapped to the scalar string "-r", and splatting a string expands it
    # character-by-character ("-", "r"), so the compiler sees a stray source
    # file and rejects -f.
    $javaArgs = @(
        "-cp", $jar, "com.garmin.monkeybrains.Monkeybrains",
        "-f", $jungles, "-o", $out, "-y", $key, "-d", $device, "-w",
        "--build-stats", "0"
    )
    if (-not $Debug) { $javaArgs += "-r" }
    if ($UnitTest) { $javaArgs += "--unit-test" }
    # Capture rather than pipe straight through, so the build stats can be
    # totalled below. Windows PowerShell wraps a native command's stderr lines
    # in ErrorRecords, which the script-wide "Stop" preference would turn into
    # a terminating error the moment they land in a variable -- so relax the
    # preference across the call and stringify what comes back.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $java @javaArgs 2>&1 | ForEach-Object { "$_" }
    $ErrorActionPreference = $prevEap
    $output | Select-String -Pattern "BUILD SUCCESSFUL|BUILD FAILED|ERROR|WARNING"
    if (-not (Test-Path $out)) { throw "Build failed for $device" }

    # The stats block reports data and code separately, in that order, each on
    # its own "Foreground:" line. Their sum is what the app costs before it has
    # allocated anything at all.
    $bytes = @([regex]::Matches(($output -join "`n"), "Foreground:\s+(\d+)") |
        ForEach-Object { [int]$_.Groups[1].Value })
    if ($bytes.Count -ge 2) {
        $static = $bytes[0] + $bytes[1]
        $pct = [math]::Round(100.0 * $static / $memoryLimit, 1)
        Write-Host ("  data {0:N0} + code {1:N0} = {2:N0} bytes static, {3}% of the {4:N0} byte limit" -f `
            $bytes[0], $bytes[1], $static, $pct, $memoryLimit)
        Write-Host ("  {0:N0} bytes left for the runtime heap" -f ($memoryLimit - $static))
    }
}

Write-Host "`nDone. Sideload the .prg matching your watch:"
Write-Host "  Venu 3  (45mm) -> bin\MoonPhaseAstro-venu3.prg"
Write-Host "  Venu 3S (41mm) -> bin\MoonPhaseAstro-venu3s.prg"

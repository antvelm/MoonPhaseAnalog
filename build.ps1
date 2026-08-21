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

param(
    [switch]$Debug
)

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

$modeLabel = if ($Debug) { "debug" } else { "release" }

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
        "-f", "monkey.jungle", "-o", $out, "-y", $key, "-d", $device, "-w"
    )
    if (-not $Debug) { $javaArgs += "-r" }
    & $java @javaArgs 2>&1 |
        Select-String -Pattern "BUILD|ERROR|WARNING"
    if (-not (Test-Path $out)) { throw "Build failed for $device" }
}

Write-Host "`nDone. Sideload the .prg matching your watch:"
Write-Host "  Venu 3  (45mm) -> bin\MoonPhaseAstro-venu3.prg"
Write-Host "  Venu 3S (41mm) -> bin\MoonPhaseAstro-venu3s.prg"

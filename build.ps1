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

# --- Find a working Java (the PATH one is broken on this machine) ---
$javaCandidates = @(
    "C:\Program Files\Java\jre1.8.0_341\bin\java.exe",
    "C:\Program Files\Eclipse Adoptium\*\bin\java.exe",
    "C:\Program Files\Microsoft\*\bin\java.exe",
    "C:\Program Files\Java\*\bin\java.exe"
)
$java = $null
foreach ($pattern in $javaCandidates) {
    $found = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) {
        & $found.FullName -version *> $null
        if ($LASTEXITCODE -eq 0) { $java = $found.FullName; break }
    }
}
if ($null -eq $java) { throw "No working Java runtime found. Install a JDK (17+ recommended) and retry." }
Write-Host "Using Java: $java"
Write-Host "Using SDK:  $sdk"

$key = Join-Path $PSScriptRoot "developer_key.der"
if (-not (Test-Path $key)) { throw "Missing developer_key.der. See HANDOFF.md to regenerate it." }

New-Item -ItemType Directory -Force -Path bin | Out-Null

$mode = if ($Debug) { @() } else { @("-r") }
$modeLabel = if ($Debug) { "debug" } else { "release" }

foreach ($device in @("venu3", "venu3s")) {
    $out = "bin\MoonPhaseAstro-$device.prg"
    Write-Host "`nBuilding $device ($modeLabel) -> $out"
    & $java -cp $jar com.garmin.monkeybrains.Monkeybrains `
        -f monkey.jungle -o $out -y $key -d $device -w @mode 2>&1 |
        Select-String -Pattern "BUILD|ERROR|WARNING"
    if (-not (Test-Path $out)) { throw "Build failed for $device" }
}

Write-Host "`nDone. Sideload the .prg matching your watch:"
Write-Host "  Venu 3  (45mm) -> bin\MoonPhaseAstro-venu3.prg"
Write-Host "  Venu 3S (41mm) -> bin\MoonPhaseAstro-venu3s.prg"

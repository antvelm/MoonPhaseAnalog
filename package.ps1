# Build the Connect IQ Store package (.iq) for Moon Phase Astro.
#
# This is what you upload to the Connect IQ developer portal
# (https://apps.garmin.com/developer/dashboard). It is NOT the same as the
# per-device .prg files build.ps1 makes for sideloading: a store package is a
# single .iq file that bundles every product listed in manifest.xml (venu3 and
# venu3s) so Garmin can serve the right build to each user.
#
# Same broken-Java workaround as build.ps1: the `java` on PATH is an Oracle
# "javapath" stub that crashes, so this calls the compiler with a known-good JRE.
#
# IMPORTANT: the .iq is signed with developer_key.der. That key permanently
# identifies this app in the store. Every future update MUST be signed with the
# SAME key or Garmin treats it as a different app. Back the key up off-machine.
#
# Usage:
#   .\package.ps1                       # -> MoonPhaseAstro.iq
#   .\package.ps1 -Out MyName.iq        # custom output name

param(
    [string]$Out = "MoonPhaseAstro.iq"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# --- Locate the Connect IQ SDK ---
$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$jar = Join-Path $sdk "bin\monkeybrains.jar"
if (-not (Test-Path $jar)) { throw "Compiler not found at $jar" }

# --- Find a working Java (see build.ps1 for why) ---
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

$key = Join-Path $PSScriptRoot "developer_key.der"
if (-not (Test-Path $key)) { throw "Missing developer_key.der. See HANDOFF.md to regenerate it (but note: a regenerated key cannot update an app already published under the old key)." }

Write-Host "Using Java: $java"
Write-Host "Using SDK:  $sdk"
Write-Host "`nBuilding store package -> $Out"

# -e  : export/package for the store (produces a multi-device .iq)
# -r  : release build
# -w  : show warnings
# Note: no -d <device>; the package covers all products in manifest.xml.
$javaArgs = @(
    "-cp", $jar, "com.garmin.monkeybrains.Monkeybrains",
    "-e", "-f", "monkey.jungle", "-o", $Out, "-y", $key, "-r", "-w"
)
& $java @javaArgs 2>&1 | Select-String -Pattern "BUILD|ERROR|WARNING"
if (-not (Test-Path $Out)) { throw "Packaging failed; $Out was not produced." }

Write-Host "`nDone. Upload this file to the Connect IQ developer portal:"
Write-Host "  $((Resolve-Path $Out).Path)"
Write-Host "`nPortal: https://apps.garmin.com/developer/dashboard"

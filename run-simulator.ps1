# Launch the Connect IQ simulator and load the watch face into it.
#
# Same Java workaround as build.ps1 (the PATH java stub is broken).
#
# Usage:
#   .\run-simulator.ps1            # simulate on venu3
#   .\run-simulator.ps1 venu3s     # simulate on venu3s

param(
    [string]$Device = "venu3"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# Pick a working Java. Order of preference:
#   1. $env:CIQ_JAVA (set this to override)
#   2. `java` on PATH (e.g. your Temurin install)
#   3. any Adoptium / Microsoft / Oracle JDK or JRE under Program Files
# The broken Oracle "javapath" stub is auto-rejected: its version probe exits
# with a crash code, so it never gets picked. The probe output is fully
# suppressed so it does not print red stderr noise.
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

$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$jar = Join-Path $sdk "bin\monkeybrains.jar"
$sim = Join-Path $sdk "bin\simulator.exe"
$shell = Join-Path $sdk "bin\shell.exe"

$java = Get-WorkingJava
if ($null -eq $java) { throw "No working Java runtime found. Install Temurin (Adoptium) JDK 21 and retry." }
Write-Host "Using Java: $java"

# Build a fresh debug .prg for the simulator.
$prg = "bin\MoonPhaseAstro-$Device.prg"
New-Item -ItemType Directory -Force -Path bin | Out-Null
Write-Host "Building $Device (debug) ..."
& $java -cp $jar com.garmin.monkeybrains.Monkeybrains `
    -f monkey.jungle -o $prg -y developer_key.der -d $Device -w 2>&1 |
    Select-String -Pattern "BUILD|ERROR|WARNING"
if (-not (Test-Path $prg)) { throw "Build failed." }

# Start the simulator if it is not already running.
if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
    Write-Host "Starting simulator ..."
    Start-Process -FilePath $sim
    Start-Sleep -Seconds 6
}

# Push the app to the simulator.
Write-Host "Loading watch face into simulator ($Device) ..."
& $java -cp $jar com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f $prg -d $Device -s $shell

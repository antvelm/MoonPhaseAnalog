# Walk the synodic month in 8 steps and screenshot the face at each one.
#
# Proof that the moon disc and the moonlit starfield both track the phase:
# the moon should grow new -> full -> new without jumping, and the star field
# should be densest at new moon and near-empty at full.
#
# Each step picks the DebugTimeOffsetDays that lands today's clock on the
# target phase fraction, so the shots are exact rather than "about a week".
#
# Follows the reset sequence in docs/simulator-property-reset.md: kill
# simulator.exe AND shell.exe and delete simulator.ini before every launch,
# or the simulator serves stale property values forever.
#
# Usage:
#   .\tools\gen-phase-walk.ps1
#   .\tools\gen-phase-walk.ps1 -Steps 8 -OutDir screenshots\phase-walk
#
# resources/properties.xml is restored on exit, success or failure.

param(
    [int]$Steps = 8,
    [string]$Device = "venu3",
    [string]$OutDir = "screenshots\phase-walk",
    [int]$StarCount = 120
)

$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\.."

$propsPath = "resources\properties.xml"
$original = Get-Content $propsPath -Raw
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

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
$monkeydo = Join-Path $sdk "bin\monkeydo.bat"
$key = "developer_key.der"
$iniPath = "$env:APPDATA\Garmin\ConnectIQ\simulator.ini"
$prg = "bin\MoonPhaseAstro-$Device.prg"

$java = Get-WorkingJava
if ($null -eq $java) { throw "No working Java runtime found." }
Write-Host "Using Java: $java"

# --- Phase arithmetic, mirroring MoonPhase.fractionAt ---
$SYNODIC = 29.530588853
$REF_NEW = 2451550.1
$UNIX_JD = 2440587.5

function Get-Frac([double]$epochSeconds) {
    $jd = $epochSeconds / 86400.0 + $UNIX_JD
    $age = ($jd - $REF_NEW) - $SYNODIC * [Math]::Floor(($jd - $REF_NEW) / $SYNODIC)
    return $age / $SYNODIC
}

$nowSec = [double][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$nowFrac = Get-Frac $nowSec
Write-Host ("Now: frac {0:N4} ({1:N0}% lit)" -f $nowFrac, (100 * (1 - [Math]::Cos(2 * [Math]::PI * $nowFrac)) / 2))

$names = @{
    0.000 = "new"; 0.125 = "waxing-crescent"; 0.250 = "first-quarter"
    0.375 = "waxing-gibbous"; 0.500 = "full"; 0.625 = "waning-gibbous"
    0.750 = "last-quarter"; 0.875 = "waning-crescent"
}

function Set-Prop([string]$content, [string]$id, [string]$value) {
    $pattern = '(<property id="' + [regex]::Escape($id) + '" type="[^"]+">)[^<]*(</property>)'
    return [regex]::Replace($content, $pattern, ('${1}' + $value + '${2}'))
}

function Write-Properties([hashtable]$overrides) {
    $content = $original
    foreach ($id in $overrides.Keys) { $content = Set-Prop $content $id ([string]$overrides[$id]) }
    Set-Content -Path $propsPath -Value $content -NoNewline
}

function Wait-ProcessGone([string]$name, [int]$timeoutSec = 10) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process -Name $name -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

# Everything that could distract from the moon and the stars is turned off:
# no comet, no wave, no orbit ring, and no eclipse art on the new/full steps.
$baseline = @{
    CometMode           = 0
    CometOnFiveSec      = "false"
    ShowOrbitRing       = "false"
    Background          = 0
    StarCount           = $StarCount
    EnableRainbowWave   = "false"
    WaveTestMode        = "false"
    EclipseEffects      = "false"
    DebugEclipse        = 0
    DebugClock          = 101035
    DebugLatitude       = "999.0"
    DebugLongitude      = "999.0"
}

$failures = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $Steps; $i++) {
    $target = [Math]::Round($i / [double]$Steps, 3)
    $label = if ($names.ContainsKey($target)) { $names[$target] } else { "frac-$target" }
    $name = "{0:d2}-{1:N3}-{2}" -f $i, $target, $label

    # Days to add so the astro clock lands on the target fraction.
    $delta = $target - $nowFrac
    if ($delta -lt 0) { $delta += 1.0 }
    $offset = [Math]::Round($delta * $SYNODIC, 4)

    Write-Host ("[{0}/{1}] {2}  offset {3} d" -f ($i + 1), $Steps, $name, $offset)
    try {
        $o = @{}
        foreach ($k in $baseline.Keys) { $o[$k] = $baseline[$k] }
        $o["DebugTimeOffsetDays"] = $offset
        Write-Properties $o

        & $java -cp $jar com.garmin.monkeybrains.Monkeybrains `
            -f monkey.jungle -o $prg -y $key -d $Device -w 2>&1 |
            Select-String -Pattern "ERROR" | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        if (-not (Test-Path $prg)) { throw "build failed" }

        Wait-ProcessGone "simulator" 10
        Wait-ProcessGone "shell" 10
        Remove-Item $iniPath -Force -ErrorAction SilentlyContinue

        Start-Process -FilePath $sim
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $proc = $null
        while ($sw.Elapsed.TotalSeconds -lt 20) {
            $proc = Get-Process simulator -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }
            if ($proc) { break }
            Start-Sleep -Milliseconds 400
        }
        if (-not $proc) { throw "simulator window never appeared" }
        Start-Sleep -Seconds 2

        Start-Process -FilePath $monkeydo -ArgumentList @($prg, $Device) -WindowStyle Hidden
        Start-Sleep -Seconds 7

        & "$PSScriptRoot\screenshot.ps1" -Out (Join-Path $OutDir "$name.png") | Write-Host
    }
    catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failures.Add($name)
    }
}

Set-Content -Path $propsPath -Value $original -NoNewline
Wait-ProcessGone "simulator" 10
Wait-ProcessGone "shell" 10
Remove-Item $iniPath -Force -ErrorAction SilentlyContinue

Write-Host "`nDone. $($Steps - $failures.Count)/$Steps succeeded. Shots in $OutDir"
if ($failures.Count -gt 0) { $failures | ForEach-Object { Write-Host "  failed: $_" } }
Write-Host "properties.xml restored."

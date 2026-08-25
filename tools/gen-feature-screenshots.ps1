# Screenshot every user-facing property value combination in the Connect IQ
# simulator, as visual proof each setting renders correctly.
#
# Follows the reset sequence documented in docs/simulator-property-reset.md:
# every scenario gets a fresh property-default read by killing simulator.exe
# AND shell.exe, then deleting simulator.ini, before each relaunch - otherwise
# the simulator silently keeps serving stale property values forever.
#
# Usage:
#   .\tools\gen-feature-screenshots.ps1 -VerifyOnly       # 2 shots, sanity check
#   .\tools\gen-feature-screenshots.ps1                   # full ~60-shot batch
#   .\tools\gen-feature-screenshots.ps1 -Only "^hand-"    # just the hand shots
#
# Each shot is cropped to the 454x454 display, so the PNGs drop straight into a
# README. Pass -NoCrop to keep the whole simulator window instead.
#
# resources/properties.xml is restored to its original (on-disk at script
# start) content when the script exits, success or failure.

param(
    [switch]$VerifyOnly,
    [string]$Only = "",
    [switch]$NoCrop,
    [string]$Device = "venu3",
    [string]$OutDir = "screenshots\features"
)

$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\.."

$propsPath = "resources\properties.xml"
$original = Get-Content $propsPath -Raw
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --- Java / SDK plumbing (same as build.ps1 / run-simulator.ps1) ---
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
$monkeydo = Join-Path $sdk "bin\monkeydo.bat"
$key = "developer_key.der"
$iniPath = "$env:APPDATA\Garmin\ConnectIQ\simulator.ini"
$prg = "bin\MoonPhaseAstro-$Device.prg"

$java = Get-WorkingJava
if ($null -eq $java) { throw "No working Java runtime found." }
Write-Host "Using Java: $java"
Write-Host "Using SDK:  $sdk"

# --- Property file helpers ---
function Set-Prop([string]$content, [string]$id, [string]$value) {
    $pattern = '(<property id="' + [regex]::Escape($id) + '" type="[^"]+">)[^<]*(</property>)'
    $replacement = '${1}' + $value + '${2}'
    return [regex]::Replace($content, $pattern, $replacement)
}

function Write-Properties([hashtable]$overrides) {
    $content = $original
    foreach ($id in $overrides.Keys) {
        $content = Set-Prop $content $id ([string]$overrides[$id])
    }
    Set-Content -Path $propsPath -Value $content -NoNewline
}

# Neutral baseline: every scenario merges its own overrides on top of this,
# so each shot isolates the setting(s) it's demonstrating. Keys must match
# resources/properties.xml exactly - Set-Prop below silently does nothing for a
# key that no longer exists, which is how this drifted out of date the last
# time properties were renamed.
$baseline = @{
    CometMode           = 1
    CometOnFiveSec      = "false"
    ShowOrbitRing       = "false"
    ShowHourNumerals    = "true"
    HourNumeralsOuter   = "false"
    HourMarkStyle       = 1
    ShowSecondNumerals  = "true"
    HandColor           = 8
    HandHollow          = 50
    Background          = 0
    ZodiacSign          = 0
    StarCount           = 120
    EnableRainbowWave   = "false"
    WaveHour            = 0
    WaveIntervalHours   = 3
    EclipseEffects      = "true"
    EclipseVisibility   = 0
    EclipseSource       = 0
    WaveTestMode        = "false"
    DebugEclipse        = 0
    DebugTimeOffsetDays = "0.0"
    DebugClock          = 101035
    DebugLatitude       = "999.0"
    DebugLongitude      = "999.0"
}

function Merge([hashtable]$overrides) {
    $m = @{}
    foreach ($k in $baseline.Keys) { $m[$k] = $baseline[$k] }
    foreach ($k in $overrides.Keys) { $m[$k] = $overrides[$k] }
    return $m
}

$zodiacSigns = @("aries","taurus","gemini","cancer","leo","virgo",
                 "libra","scorpio","sagittarius","capricorn","aquarius","pisces")

$scenarios = New-Object System.Collections.Generic.List[object]

# The face as it ships, for the README's hero shot.
$scenarios.Add(@{ Name = "hero"; Overrides = (Merge @{}) })

$handColorNames = @("white","cool","lume","ice","amber","orange","red","magenta","spectrum")
foreach ($c in @(0,2,3,4,6,8)) {
    $scenarios.Add(@{ Name = "hand-color-$c-$($handColorNames[$c])"; Overrides = (Merge @{ HandColor = $c }) })
}

foreach ($h in @(0,50,80)) {
    $scenarios.Add(@{ Name = "hand-hollow-$h"; Overrides = (Merge @{ HandHollow = $h; HandColor = 0 }) })
}

$hourMarkNames = @("numerals","lines","lines-cardinal")
for ($i = 0; $i -lt 3; $i++) {
    $scenarios.Add(@{ Name = "hour-mark-$i-$($hourMarkNames[$i])"; Overrides = (Merge @{ HourMarkStyle = $i }) })
}

foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "hour-numerals-outer-$v"; Overrides = (Merge @{ HourNumeralsOuter = $v; HourMarkStyle = 0 }) })
}

$cometNames = @("classic","spectrum-trail","spectrum-ring")
for ($i = 0; $i -lt 3; $i++) {
    $scenarios.Add(@{ Name = "comet-mode-$i-$($cometNames[$i])"; Overrides = (Merge @{ CometMode = $i }) })
}

foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "comet-five-sec-$v"; Overrides = (Merge @{ CometOnFiveSec = $v; ShowSecondNumerals = "true" }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "orbit-ring-$v"; Overrides = (Merge @{ ShowOrbitRing = $v }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "hour-numerals-$v"; Overrides = (Merge @{ ShowHourNumerals = $v }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "second-numerals-$v"; Overrides = (Merge @{ ShowSecondNumerals = $v }) })
}

# StarCount is a count now, not a density enum. 200 is the settings maximum.
foreach ($n in @(0,40,120,200)) {
    $scenarios.Add(@{ Name = ("star-count-{0:d3}" -f $n); Overrides = (Merge @{ StarCount = $n }) })
}

# How far moonlight washes the field out is the phase walk's job, not this
# script's: see tools\gen-phase-walk.ps1.
for ($s = 1; $s -le 12; $s++) {
    $scenarios.Add(@{ Name = "zodiac-stars-$s-$($zodiacSigns[$s-1])"; Overrides = (Merge @{ Background = 1; ZodiacSign = $s }) })
}
for ($s = 1; $s -le 12; $s++) {
    $scenarios.Add(@{ Name = "zodiac-lines-$s-$($zodiacSigns[$s-1])"; Overrides = (Merge @{ Background = 2; ZodiacSign = $s }) })
}

# The rainbow wave is compiled out while RainbowWave.ENABLED is false, so this
# scenario renders an ordinary dial until that flag goes back to true.
$scenarios.Add(@{ Name = "rainbow-wave-on"; Overrides = (Merge @{ EnableRainbowWave = "true"; WaveTestMode = "true" }) })

$scenarios.Add(@{ Name = "eclipse-lunar"; Overrides = (Merge @{ EclipseEffects = "true"; DebugEclipse = 1; DebugClock = 101035 }) })
$scenarios.Add(@{ Name = "eclipse-solar"; Overrides = (Merge @{ EclipseEffects = "true"; DebugEclipse = 2; DebugClock = 101045 }) })

# New moon, where the sky is at its fullest: moonlight is what thins the field,
# so this is the only phase that shows all StarCount of them. The offset that
# lands the astro clock on a given fraction is worked out the same way
# tools\gen-phase-walk.ps1 does it, mirroring MoonPhase.fractionAt.
$SYNODIC = 29.530588853
$REF_NEW = 2451550.1
$UNIX_JD = 2440587.5
$nowJd   = [double][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() / 86400.0 + $UNIX_JD
$nowFrac = (($nowJd - $REF_NEW) - $SYNODIC * [Math]::Floor(($nowJd - $REF_NEW) / $SYNODIC)) / $SYNODIC

function Offset-ToPhase([double]$target) {
    $d = $target - $nowFrac
    if ($d -lt 0) { $d += 1.0 }
    return [Math]::Round($d * $SYNODIC, 4)
}

$scenarios.Add(@{ Name = "new-moon-stars"; Overrides = (Merge @{ DebugTimeOffsetDays = (Offset-ToPhase 0.0); DebugClock = 101020 }) })
$scenarios.Add(@{ Name = "half-moon";      Overrides = (Merge @{ DebugTimeOffsetDays = (Offset-ToPhase 0.25); DebugClock = 101005 }) })

if ($VerifyOnly) {
    $scenarios = $scenarios | Where-Object { $_.Name -eq "hero" -or $_.Name -eq "eclipse-lunar" }
} elseif ($Only -ne "") {
    $scenarios = $scenarios | Where-Object { $_.Name -match $Only }
    if (-not $scenarios) { throw "-Only '$Only' matched no scenario." }
}

Write-Host "`n$($scenarios.Count) scenario(s) queued.`n"

# Cut the round display out of the simulator window screenshot, in place, and
# report whether it could. The simulator renders the 454 px face 1:1, so the
# geometry is fixed - the same constants tools\montage.ps1 and
# tools\crop-track.ps1 use. If the window ever moves the face somewhere else the
# crop lands off-centre rather than failing, so check the first shot of a batch
# by eye.
Add-Type -AssemblyName System.Drawing
$faceX = 327; $faceY = 481; $faceR = 227

function Crop-Face([string]$path) {
    $full = (Resolve-Path $path).Path
    $src = [System.Drawing.Bitmap]::FromFile($full)
    try {
        $side = $faceR * 2
        $left = $faceX - $faceR
        $top  = $faceY - $faceR
        if ($left -lt 0 -or $top -lt 0 -or
            ($left + $side) -gt $src.Width -or ($top + $side) -gt $src.Height) {
            Write-Host "  crop skipped: face box is outside the $($src.Width)x$($src.Height) window" -ForegroundColor Yellow
            return $false
        }
        $dst = New-Object System.Drawing.Bitmap $side, $side
        $g = [System.Drawing.Graphics]::FromImage($dst)
        $g.DrawImage($src, (New-Object System.Drawing.Rectangle 0, 0, $side, $side),
                     (New-Object System.Drawing.Rectangle $left, $top, $side, $side),
                     [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
    } finally {
        $src.Dispose()
    }
    $dst.Save($full, [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose()
    Write-Host "  cropped to ${side}x${side}"
    return $true
}

function Wait-ProcessGone([string]$name, [int]$timeoutSec = 10) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process -Name $name -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

$failures = New-Object System.Collections.Generic.List[string]
$i = 0
foreach ($scn in $scenarios) {
    $i++
    $name = $scn.Name
    Write-Host "[$i/$($scenarios.Count)] $name"
    try {
        Write-Properties $scn.Overrides

        Write-Host "  building..."
        & $java -cp $jar com.garmin.monkeybrains.Monkeybrains `
            -f monkey.jungle -o $prg -y $key -d $Device -w 2>&1 |
            Select-String -Pattern "ERROR" | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        if (-not (Test-Path $prg)) { throw "build failed" }

        Write-Host "  resetting simulator state..."
        Wait-ProcessGone "simulator" 10
        Wait-ProcessGone "shell" 10
        Remove-Item $iniPath -Force -ErrorAction SilentlyContinue

        Write-Host "  launching simulator..."
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

        Write-Host "  pushing app..."
        Start-Process -FilePath $monkeydo -ArgumentList @($prg, $Device) -WindowStyle Hidden
        Start-Sleep -Seconds 6

        $outPath = Join-Path $OutDir "$name.png"

        # The simulator window is briefly narrower than the display it is about
        # to render - catch it there and the shot is a sliver of chrome with no
        # face in it. Retry until the face box fits, which is also exactly the
        # condition the crop needs.
        $captured = $false
        for ($try = 1; $try -le 4; $try++) {
            & "$PSScriptRoot\screenshot.ps1" -Out $outPath | Write-Host
            if ($NoCrop) { $captured = $true; break }
            if (Crop-Face $outPath) { $captured = $true; break }
            Write-Host "  window not sized yet, retrying ($try/4)..."
            Start-Sleep -Seconds 4
        }
        if (-not $captured) { throw "simulator window never reached full size" }
    }
    catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failures.Add($name)
    }
}

# --- Restore original properties.xml ---
Set-Content -Path $propsPath -Value $original -NoNewline
Wait-ProcessGone "simulator" 10
Wait-ProcessGone "shell" 10
Remove-Item $iniPath -Force -ErrorAction SilentlyContinue

Write-Host "`nDone. $($scenarios.Count - $failures.Count)/$($scenarios.Count) succeeded."
if ($failures.Count -gt 0) {
    Write-Host "Failed scenarios:" -ForegroundColor Yellow
    $failures | ForEach-Object { Write-Host "  - $_" }
}
Write-Host "properties.xml restored to its original content."

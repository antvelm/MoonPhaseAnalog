# Screenshot every user-facing property value combination in the Connect IQ
# simulator, as visual proof each setting renders correctly.
#
# Follows the reset sequence documented in docs/simulator-property-reset.md:
# every scenario gets a fresh property-default read by killing simulator.exe
# AND shell.exe, then deleting simulator.ini, before each relaunch - otherwise
# the simulator silently keeps serving stale property values forever.
#
# Usage:
#   .\tools\gen-feature-screenshots.ps1 -VerifyOnly   # 2 shots, sanity check
#   .\tools\gen-feature-screenshots.ps1               # full ~50-shot batch
#
# resources/properties.xml is restored to its original (on-disk at script
# start) content when the script exits, success or failure.

param(
    [switch]$VerifyOnly,
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
# so each shot isolates the setting(s) it's demonstrating.
$baseline = @{
    HandStyle           = 1
    CometMode           = 0
    CometOnFiveSec      = "false"
    ShowOrbitRing       = "false"
    ShowHourNumerals    = "true"
    ShowSecondNumerals  = "true"
    Background          = 2
    ZodiacSign          = 1
    StarDensity         = 2
    EnableRainbowWave   = "false"
    WaveHour            = 0
    EclipseEffects      = "true"
    EclipseVisibility   = 0
    EclipseSource       = 0
    WaveTestMode        = "false"
    DebugEclipse        = 0
    DebugTimeOffsetDays = "0.0"
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

$handNames = @("dauphine","baton","syringe","skeleton","breguet","alpha","sword")
for ($i = 0; $i -lt 7; $i++) {
    $scenarios.Add(@{ Name = "hand-style-$i-$($handNames[$i])"; Overrides = (Merge @{ HandStyle = $i; Background = 0 }) })
}

$cometNames = @("classic","spectrum-trail","spectrum-ring")
for ($i = 0; $i -lt 3; $i++) {
    $scenarios.Add(@{ Name = "comet-mode-$i-$($cometNames[$i])"; Overrides = (Merge @{ CometMode = $i; Background = 0 }) })
}

foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "comet-five-sec-$v"; Overrides = (Merge @{ CometOnFiveSec = $v; ShowSecondNumerals = "true"; Background = 0 }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "orbit-ring-$v"; Overrides = (Merge @{ ShowOrbitRing = $v; Background = 0 }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "hour-numerals-$v"; Overrides = (Merge @{ ShowHourNumerals = $v; Background = 0 }) })
}
foreach ($v in @("false","true")) {
    $scenarios.Add(@{ Name = "second-numerals-$v"; Overrides = (Merge @{ ShowSecondNumerals = $v; Background = 0 }) })
}

$densityNames = @("off","sparse","normal","dense")
foreach ($d in @(0,1,3)) {
    $scenarios.Add(@{ Name = "starfield-density-$d-$($densityNames[$d])"; Overrides = (Merge @{ Background = 0; StarDensity = $d }) })
}

for ($s = 1; $s -le 12; $s++) {
    $scenarios.Add(@{ Name = "zodiac-stars-$s-$($zodiacSigns[$s-1])"; Overrides = (Merge @{ Background = 1; ZodiacSign = $s }) })
}
for ($s = 1; $s -le 12; $s++) {
    $scenarios.Add(@{ Name = "zodiac-lines-$s-$($zodiacSigns[$s-1])"; Overrides = (Merge @{ Background = 2; ZodiacSign = $s }) })
}

$scenarios.Add(@{ Name = "rainbow-wave-on"; Overrides = (Merge @{ EnableRainbowWave = "true"; WaveTestMode = "true"; Background = 0 }) })

$scenarios.Add(@{ Name = "eclipse-lunar"; Overrides = (Merge @{ EclipseEffects = "true"; DebugEclipse = 1; Background = 0 }) })
$scenarios.Add(@{ Name = "eclipse-solar"; Overrides = (Merge @{ EclipseEffects = "true"; DebugEclipse = 2; Background = 0 }) })

if ($VerifyOnly) {
    $scenarios = $scenarios | Where-Object { $_.Name -eq "hand-style-0-dauphine" -or $_.Name -eq "hand-style-3-skeleton" }
}

Write-Host "`n$($scenarios.Count) scenario(s) queued.`n"

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
        & "$PSScriptRoot\screenshot.ps1" -Out $outPath | Write-Host
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

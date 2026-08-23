# Launch the Connect IQ simulator and load the watch face into it.
#
# Same Java workaround as build.ps1 (the PATH java stub is broken).
#
# Always fully resets simulator state before launching (kills simulator.exe
# and shell.exe, deletes simulator.ini) so property defaults from
# resources/properties.xml actually take effect instead of the simulator
# silently restoring stale values from a prior run. See
# docs/simulator-property-reset.md for why this is necessary.
#
# Usage:
#   .\run-simulator.ps1            # simulate on venu3
#   .\run-simulator.ps1 venu3s     # simulate on venu3s
#   .\run-simulator.ps1 -Perf      # with the frame-time / heap overlay from
#                                  #   source\Perf.mc drawn on the dial
#
# With -Perf, read the overlay alongside the simulator's own File > View
# Memory window: the overlay gives you per-frame cost and live heap, the
# memory viewer gives you the peak and the per-class breakdown behind it.

param(
    [string]$Device = "venu3",
    [switch]$Perf
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
$iniPath = "$env:APPDATA\Garmin\ConnectIQ\simulator.ini"

function Wait-ProcessGone([string]$name, [int]$timeoutSec = 10) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ((Get-Process -Name $name -ErrorAction SilentlyContinue) -and $sw.Elapsed.TotalSeconds -lt $timeoutSec) {
        Stop-Process -Name $name -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 300
    }
}

$java = Get-WorkingJava
if ($null -eq $java) { throw "No working Java runtime found. Install Temurin (Adoptium) JDK 21 and retry." }
Write-Host "Using Java: $java"

# Build a fresh debug .prg for the simulator.
$prg = "bin\MoonPhaseAstro-$Device.prg"
New-Item -ItemType Directory -Force -Path bin | Out-Null
# perf.jungle overrides monkey.jungle's annotation exclusion, swapping the
# overlay's empty stubs for its real implementation.
$jungles = if ($Perf) { "monkey.jungle;perf.jungle" } else { "monkey.jungle" }

$modeLabel = if ($Perf) { "debug+perf" } else { "debug" }
Write-Host "Building $Device ($modeLabel) ..."
& $java -cp $jar com.garmin.monkeybrains.Monkeybrains `
    -f $jungles -o $prg -y developer_key.der -d $Device -w 2>&1 |
    Select-String -Pattern "BUILD|ERROR|WARNING"
if (-not (Test-Path $prg)) { throw "Build failed." }

# Reset simulator state so properties.xml defaults actually take effect.
# simulator.ini remembers the last device this app ran on; as long as that
# line exists, the simulator treats the app as "already installed" and
# restores whatever property values it saw on first install, ignoring any
# new defaults from a rebuild. Killing shell.exe (the process that actually
# holds Application.Properties in memory) is also required -- killing only
# simulator.exe is not enough. See docs/simulator-property-reset.md.
Write-Host "Resetting simulator state ..."
Wait-ProcessGone "simulator" 10
Wait-ProcessGone "shell" 10
Remove-Item $iniPath -Force -ErrorAction SilentlyContinue

Write-Host "Starting simulator ..."
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

# Push the app to the simulator.
Write-Host "Loading watch face into simulator ($Device) ..."
& $java -cp $jar com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f $prg -d $Device -s $shell

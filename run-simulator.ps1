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

$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$jar = Join-Path $sdk "bin\monkeybrains.jar"
$sim = Join-Path $sdk "bin\simulator.exe"
$shell = Join-Path $sdk "bin\shell.exe"

# Find a working Java (PATH java is broken on this machine).
$java = $null
foreach ($pattern in @(
    "C:\Program Files\Java\jre1.8.0_341\bin\java.exe",
    "C:\Program Files\Eclipse Adoptium\*\bin\java.exe",
    "C:\Program Files\Microsoft\*\bin\java.exe",
    "C:\Program Files\Java\*\bin\java.exe")) {
    $found = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { & $found.FullName -version *> $null; if ($LASTEXITCODE -eq 0) { $java = $found.FullName; break } }
}
if ($null -eq $java) { throw "No working Java runtime found." }

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

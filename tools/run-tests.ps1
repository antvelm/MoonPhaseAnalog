# Build with the unit tests compiled in and run them in the Connect IQ simulator.
#
#   powershell -File tools\run-tests.ps1            # venu3
#   powershell -File tools\run-tests.ps1 venu3s
#
# The simulator must be able to start; the tests themselves need no interaction.
param(
    [string]$Device = "venu3"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

& (Join-Path $root 'build.ps1') -UnitTest

$sdk = (Get-Content "$env:APPDATA\Garmin\ConnectIQ\current-sdk.cfg").Trim()
$sim = Join-Path $sdk 'bin\simulator.exe'
$run = Join-Path $sdk 'bin\monkeydo.bat'
$prg = Join-Path $root "bin\MoonPhaseAstro-$Device.prg"

if (-not (Test-Path $prg)) { throw "Not built: $prg" }

if (-not (Get-Process -Name 'simulator' -ErrorAction SilentlyContinue)) {
    Write-Host "Starting simulator..."
    Start-Process -FilePath $sim | Out-Null
    Start-Sleep -Seconds 6
}

Write-Host "`nRunning tests on $Device`n"
& $run $prg $Device /t

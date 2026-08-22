# Validates the eclipse fallback in source/MoonPhase.mc against the exact NASA
# table in docs/eclipse-events.tsv.
#
# The fallback is what runs outside 2025..2045, so this is the only way to know
# how far it can be trusted. tools\eclipse-lib.ps1 is the reference
# implementation of the same algorithm; keep the two in step.
#
# Run from the repo root:  powershell -File tools\check-eclipse-math.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'eclipse-lib.ps1')

$tsv   = Join-Path $root 'docs\eclipse-events.tsv'
$epoch = [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)

$events = @()
foreach ($line in Get-Content $tsv) {
    if ($line.StartsWith('#') -or $line.Trim() -eq '') { continue }
    $f  = $line -split "`t"
    $dt = [datetime]::Parse("$($f[0])T$($f[1])Z").ToUniversalTime()
    $events += [pscustomobject]@{
        Date = $f[0]
        Day  = ($dt - $epoch).TotalDays
        Kind = if ([int]$f[2] -le 3) { 'solar' } else { 'lunar' }
        Type = [int]$f[2]
        Mag  = [double]$f[3]
    }
}

# --- 1. fires on every real event, with the right kind and type? ------------
$hit = 0; $typeOk = 0; $miss = @(); $typeBad = @(); $dtMax = 0.0; $magMax = 0.0
foreach ($e in $events) {
    $got = EclipseAt $e.Day
    if ($null -ne $got -and $got.Kind -eq $e.Kind) {
        $hit++
        $err = [math]::Abs(($got.Jde - $script:JD_2000) - $e.Day) * 1440
        if ($err -gt $dtMax) { $dtMax = $err }
        if ($got.Type -eq $e.Type) { $typeOk++ }
        else { $typeBad += "  $($e.Date) table=$($e.Type) computed=$($got.Type) (mag $($e.Mag) vs $([math]::Round($got.Mag,3)))" }
        if ($e.Kind -eq 'lunar' -and $e.Mag -gt 0) {
            $dm = [math]::Abs($got.Mag - $e.Mag)
            if ($dm -gt $magMax) { $magMax = $dm }
        }
    } else {
        $miss += "  $($e.Date) $($e.Kind) type=$($e.Type) mag=$($e.Mag)"
    }
}

# --- 2. quiet on non-eclipse days? ------------------------------------------
# Sweep the table's span; anything claimed more than a day from a real event of
# the same kind is a false positive.
$fp = 0; $checked = 0; $examples = @()
$byDay = @{}
foreach ($e in $events) {
    for ($o = -1; $o -le 1; $o++) { $byDay[[string]([int]$e.Day + $o) + $e.Kind] = 1 }
}
for ($d = [int]$events[0].Day; $d -le [int]$events[-1].Day; $d += 0.5) {
    $checked++
    $got = EclipseAt $d
    if ($null -eq $got) { continue }
    if ($byDay.ContainsKey([string][int]$d + $got.Kind)) { continue }
    $fp++
    if ($examples.Count -lt 8) {
        $examples += ('    {0} claims {1} type={2}' -f $epoch.AddDays($d).ToString('yyyy-MM-dd HH:mm'), $got.Kind, $got.Type)
    }
}

Write-Output ''
Write-Output "Events detected      : $hit / $($events.Count)"
if ($miss.Count -gt 0) { Write-Output 'MISSED:'; $miss | ForEach-Object { Write-Output $_ } }
Write-Output "Correct type         : $typeOk / $hit detected"
if ($typeBad.Count -gt 0) { Write-Output 'TYPE MISMATCH:'; $typeBad | ForEach-Object { Write-Output $_ } }
Write-Output ("Max timing error     : {0:N1} min" -f $dtMax)
Write-Output ("Max lunar mag error  : {0:N3}" -f $magMax)
Write-Output "False positives      : $fp (over $checked 12-hourly samples)"
if ($examples.Count -gt 0) { Write-Output '  e.g.'; $examples | ForEach-Object { Write-Output $_ } }
Write-Output ''

# Regenerates source/EclipseData.mc from docs/eclipse-events.tsv.
# Run from the repo root:  powershell -File tools\gen-eclipse-data.ps1
$ErrorActionPreference = 'Stop'

$root  = Split-Path -Parent $PSScriptRoot
$tsv   = Join-Path $root 'docs\eclipse-events.tsv'
$out   = Join-Path $root 'source\EclipseData.mc'
$epoch = [datetime]::new(2000, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc)

$days = @(); $mins = @(); $tmag = @(); $rows = @()

foreach ($line in Get-Content $tsv) {
    if ($line.StartsWith('#') -or $line.Trim() -eq '') { continue }
    $f = $line -split "`t"
    $dt  = [datetime]::Parse("$($f[0])T$($f[1])Z").ToUniversalTime()
    $d   = [int][math]::Floor(($dt - $epoch).TotalDays)
    $m   = $dt.Hour * 60 + $dt.Minute
    $ty  = [int]$f[2]
    $mag = [double]$f[3]
    if ($mag -lt 0) { $mag = 0 }
    if ($mag -gt 9.99) { $mag = 9.99 }
    $tm = $ty * 1000 + [int][math]::Round($mag * 100)

    $days += $d; $mins += $m; $tmag += $tm
    $rows += "$($f[0]) $($f[1]) type=$ty mag=$($f[3])"
}

# Fail loudly rather than shipping a table binary search cannot use.
for ($i = 1; $i -lt $days.Count; $i++) {
    if ($days[$i] -le $days[$i - 1]) {
        throw "docs\eclipse-events.tsv is not strictly ascending at row $($i + 1): $($rows[$i])"
    }
}

function Wrap([int[]]$values, [int]$perLine) {
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $values.Count; $i++) {
        if ($i % $perLine -eq 0) { [void]$sb.Append("`n        ") }
        [void]$sb.Append($values[$i])
        if ($i -lt $values.Count - 1) { [void]$sb.Append(', ') }
    }
    return $sb.ToString()
}

$n     = $days.Count
$first = ([datetime]::Parse('2000-01-01Z').AddDays($days[0])).ToString('yyyy-MM-dd')
$last  = ([datetime]::Parse('2000-01-01Z').AddDays($days[$n - 1])).ToString('yyyy-MM-dd')

$body = @"
using Toybox.Lang;

// GENERATED FILE -- do not edit by hand.
// Regenerate with:  powershell -File tools\gen-eclipse-data.ps1
// Source of truth:  docs\eclipse-events.tsv (NASA GSFC eclipse catalogue)
//
// Every solar and lunar eclipse from $first to $last ($n events), stored as
// three flat parallel arrays. Flat Number arrays rather than an array of arrays:
// nested arrays each carry object overhead in Monkey C, and this table is
// resident for the life of the watch face.
module EclipseData {

    // Eclipse type codes, also the high digits of TYPEMAG.
    const PARTIAL_SOLAR  = 0;
    const ANNULAR        = 1;
    const TOTAL_SOLAR    = 2;
    const HYBRID         = 3;
    const PENUMBRAL      = 4;
    const PARTIAL_LUNAR  = 5;
    const TOTAL_LUNAR    = 6;

    // Days from 2000-01-01 UTC to the instant of greatest eclipse. Ascending.
    const DAYS = [$(Wrap $days 12)
    ];

    // Minute of day (UTC) of greatest eclipse, 0..1439.
    const MINUTES = [$(Wrap $mins 16)
    ];

    // type * 1000 + round(magnitude * 100). Penumbral lunar magnitudes are
    // negative by definition and are stored as 0.
    const TYPEMAG = [$(Wrap $tmag 12)
    ];

    const COUNT      = $n;
    const FIRST_DAY  = $($days[0]);
    const LAST_DAY   = $($days[$n - 1]);
    const LAST_LABEL = "$last";

    function isSolar(type) {
        return type <= HYBRID;
    }

    function isLunar(type) {
        return type >= PENUMBRAL;
    }
}
"@

[System.IO.File]::WriteAllText($out, $body, (New-Object System.Text.UTF8Encoding $false))
Write-Output "wrote $out : $n events, $first .. $last"

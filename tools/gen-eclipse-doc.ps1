# Regenerates docs/eclipse-test-dates.md from docs/eclipse-events.tsv.
#   powershell -File tools\gen-eclipse-doc.ps1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$tsv  = Join-Path $root 'docs\eclipse-events.tsv'
$out  = Join-Path $root 'docs\eclipse-test-dates.md'

$names = @{
    0 = 'Partial solar'; 1 = 'Annular solar'; 2 = 'Total solar'; 3 = 'Hybrid solar'
    4 = 'Penumbral lunar'; 5 = 'Partial lunar'; 6 = 'Total lunar'
}

$rows = New-Object System.Collections.ArrayList
foreach ($line in Get-Content $tsv) {
    if ($line.StartsWith('#') -or $line.Trim() -eq '') { continue }
    $f = $line -split "`t"
    $t = [int]$f[2]
    $shown = if ($t -eq 4) { 'no (penumbral)' } elseif ($t -le 3) { 'corona' } else { 'red moon' }
    [void]$rows.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $f[0], $f[1], $names[$t], $f[3], $shown))
}

$header = @'
# Eclipse test dates, 2025-2045

Human-readable form of `source/EclipseData.mc`, which is generated from
`docs/eclipse-events.tsv` by `tools/gen-eclipse-data.ps1`. Source: the NASA
GSFC eclipse catalogue (eclipse.gsfc.nasa.gov).

Use this as the manual test script: set the simulator clock with
**Settings > Time** to a row's UTC maximum, and the face should show that
eclipse. Penumbral lunar eclipses are detected but deliberately **not**
rendered -- they look like nothing in the sky, so they must leave the moon its
normal colour.

To exercise the rendering without hunting for a date, use the **Force eclipse**
setting instead. To check the location gate, set **Test latitude** and **Test
longitude** and park the clock on a lunar maximum: a night-side location shows
the red moon, its antipode does not.

| Date | Max (UTC) | Type | Magnitude | Shown as |
|---|---|---|---|---|
'@

$footer = @'

## Validation of the computed fallback

Past 2045 the face computes eclipses on the watch (Meeus, *Astronomical
Algorithms* 2nd ed., ch. 49 and 54). `tools/check-eclipse-math.ps1` runs that
same algorithm over every row above and diffs it against the table:

| Check | Result |
|---|---|
| Events detected | 92 / 93 |
| Correct type | 89 / 92 |
| Max timing error | 1.1 min |
| Max lunar magnitude error | 0.011 |
| False positives | 0 of 14945 samples |

The single miss is 2027-07-18, a very shallow penumbral eclipse that falls
outside Meeus' node test; it is not rendered either way. The three type
disagreements are all boundary cases (annular vs hybrid, total vs partial)
where gamma sits within a thousandth of the limit.

The on-watch unit tests in `source/EclipseTest.mc` assert the same properties
against the real Monkey C implementation, driven off every row of the table.
Run them with `tools\run-tests.ps1`.
'@

$text = $header + "`r`n" + ($rows -join "`r`n") + "`r`n" + $footer
[System.IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding $false))
Write-Output "wrote $out ($($rows.Count) events)"

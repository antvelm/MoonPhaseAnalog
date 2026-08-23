# Replay Dial.buildStars outside the watch and report how many stars survive
# each moon phase, so the moonlight fade can be tuned without a build/sim
# round trip. Mirrors source/Dial.mc exactly: same LCG, same seed, same
# constants. Keep the constants below in step with Dial.mc.
#
#   .\tools\starcheck.ps1
#   .\tools\starcheck.ps1 -StarCount 160 -MoonFloor 0.90 -LevelMin 0.55

param(
    [int]$StarCount = 120,
    [double]$MoonFloor = 0.88,
    [double]$LevelMin = 0.55,
    [double]$MoonWash = 0.45,
    [double]$MwShare = 0.62
)

$stars = @()
$bright = 0
[int64]$seed = 20260822
function Next {
    $script:seed = ($script:seed * 75 + 74) % 65537
    return $script:seed / 65537.0
}

for ($i = 0; $i -lt $StarCount; $i++) {
    $c = Next
    $inBand = ($c -lt $MwShare)
    # Position draws are consumed so the magnitude draws land on the same
    # values the watch sees; the positions themselves are not needed here.
    for ($a = 0; $a -lt 1; $a++) { $null = Next; $null = Next; $null = Next }
    $w = Next
    $w2 = Next
    if ($inBand) {
        $mag = if ($w2 -gt 0.90) { 0.78 + 0.22 * $w } else { 0.04 + 0.62 * $w * $w * $w }
    } else {
        $mag = if ($w2 -gt 0.72) { 0.72 + 0.28 * $w } else { 0.18 + 0.54 * $w * $w }
    }
    $tier = 0
    if ($mag -ge 0.85) { $tier = if ($bright % 3 -eq 0) { 3 } else { 2 }; $bright++ }
    elseif ($mag -ge 0.62) { $tier = 1 }
    $stars += [pscustomobject]@{ Mag = $mag; Tier = $tier; Band = $inBand }
}

"StarCount $StarCount   MoonFloor $MoonFloor   MoonWash $MoonWash   LevelMin $LevelMin"
"tier mix: t0 {0}  t1 {1}  t2 {2}  t3 {3}" -f `
    ($stars | Where-Object Tier -eq 0).Count, ($stars | Where-Object Tier -eq 1).Count,
    ($stars | Where-Object Tier -eq 2).Count, ($stars | Where-Object Tier -eq 3).Count
""
"{0,-16} {1,6} {2,6} {3,6} {4,6} {5,6} {6,8}" -f "phase","illum","drawn","t0","t1","t2+","dimmest"
$phases = @(
    @("new", 0.0), @("crescent", 0.125), @("first quarter", 0.25),
    @("gibbous", 0.375), @("full", 0.5)
)
foreach ($p in $phases) {
    $frac = $p[1]
    $illum = (1.0 - [Math]::Cos(2 * [Math]::PI * $frac)) / 2.0
    $floor = $MoonFloor * $illum
    $span = 1.0 - $floor
    $vis = $stars | Where-Object { $_.Mag -gt $floor }
    $wash = 1.0 - $MoonWash * $illum
    $levels = $vis | ForEach-Object { $wash * ($LevelMin + (1.0 - $LevelMin) * (($_.Mag - $floor) / $span)) }
    $dimmest = if ($levels) { ($levels | Measure-Object -Minimum).Minimum } else { 0 }
    "{0,-16} {1,6:N2} {2,6} {3,6} {4,6} {5,6} {6,8:N2}" -f $p[0], $illum, $vis.Count,
        ($vis | Where-Object Tier -eq 0).Count, ($vis | Where-Object Tier -eq 1).Count,
        ($vis | Where-Object { $_.Tier -ge 2 }).Count, $dimmest
}

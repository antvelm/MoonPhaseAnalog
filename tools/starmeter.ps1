# Count how many star pixels the starfield actually puts on screen at each
# phase-walk shot, so "do the stars fade with the moon" has a number behind it
# instead of an impression from a downscaled montage.
#
# Stars are the only thing on the dial drawn in the cool grey family
# (R == G, B a little higher - Theme.STAR_DIM / STAR / STAR_BRIGHT, scaled).
# Hands, numerals, tick marks and the moon are all either warm, neutral or
# far brighter, so a colour test plus the moon mask isolates the field.
#
# NOTE: PowerShell variable names are case-insensitive - $r and $R are the same
# variable. Hence radiusPx / not $R.
param([string]$Dir = "screenshots\phase-walk")
$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\.."
Add-Type -AssemblyName System.Drawing

$faceX = 327.0; $faceY = 481.0; $radiusPx = 200.0
$moonX = 327.0; $moonY = 585.0; $moonR = 45.0

"{0,-32} {1,7} {2,7} {3,7}" -f "shot", "starpx", "faint", "bright"
foreach ($f in (Get-ChildItem $Dir -Filter *.png | Where-Object { $_.Name -match '^\d\d-' } | Sort-Object Name)) {
    $bmp = [System.Drawing.Bitmap]::FromFile($f.FullName)
    $total = 0; $faint = 0; $strong = 0
    for ($y = [int]($faceY - $radiusPx); $y -le [int]($faceY + $radiusPx); $y++) {
        $dy = $y - $faceY
        for ($x = [int]($faceX - $radiusPx); $x -le [int]($faceX + $radiusPx); $x++) {
            $dx = $x - $faceX
            if ($dx * $dx + $dy * $dy -gt $radiusPx * $radiusPx) { continue }
            $mdx = $x - $moonX; $mdy = $y - $moonY
            if ($mdx * $mdx + $mdy * $mdy -le $moonR * $moonR) { continue }
            $c = $bmp.GetPixel($x, $y)
            $cr = [int]$c.R; $cg = [int]$c.G; $cb = [int]$c.B
            if ($cb -le $cr) { continue }
            $dg = $cg - $cr; $db = $cb - $cr
            if ($dg -lt -1 -or $dg -gt 10) { continue }
            if ($db -lt 3 -or $db -gt 24) { continue }
            if ($cr -lt 12 -or $cr -gt 175) { continue }
            $total++
            if ($cr -lt 60) { $faint++ } else { $strong++ }
        }
    }
    $bmp.Dispose()
    "{0,-32} {1,7} {2,7} {3,7}" -f $f.BaseName, $total, $faint, $strong
}

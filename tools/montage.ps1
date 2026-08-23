# Stitch the phase-walk screenshots into two review images:
#   moon-strip.png  - the moon subdial from each step, magnified, in order
#   dial-strip.png  - the whole dial from each step, so the starfield can be
#                     compared new-vs-full at a glance
#
# The simulator renders the 454 px display 1:1 inside its window, so the crop
# geometry below is fixed rather than detected.
param(
    [string]$Dir = "screenshots\phase-walk",
    [string]$OutDir = "screenshots\phase-walk"
)
$ErrorActionPreference = "Stop"
Set-Location "$PSScriptRoot\.."
Add-Type -AssemblyName System.Drawing

$faceX = 327; $faceY = 481          # display centre in the simulator window
$moonY = 585                        # moon subdial centre
$moonHalf = 46
$dialHalf = 205

$files = Get-ChildItem $Dir -Filter *.png | Where-Object { $_.Name -match '^\d\d-' } | Sort-Object Name

function Build([int]$half, [int]$centreY, [int]$zoom, [string]$out) {
    $side = $half * 2
    $cell = $side * $zoom
    $pad = 4
    $labelH = 22
    $w = ($cell + $pad) * $files.Count + $pad
    $h = $cell + $labelH + $pad * 2
    $canvas = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.Clear([System.Drawing.Color]::FromArgb(24,24,28))
    $font = New-Object System.Drawing.Font "Consolas", 11
    $brush = [System.Drawing.Brushes]::White
    $i = 0
    foreach ($f in $files) {
        $src = [System.Drawing.Bitmap]::FromFile($f.FullName)
        $rect = New-Object System.Drawing.Rectangle ($faceX - $half), ($centreY - $half), $side, $side
        $dst = New-Object System.Drawing.Rectangle (($cell + $pad) * $i + $pad), $pad, $cell, $cell
        $g.DrawImage($src, $dst, $rect, [System.Drawing.GraphicsUnit]::Pixel)
        $label = ($f.BaseName -replace '^\d\d-', '')
        $g.DrawString($label, $font, $brush, (($cell + $pad) * $i + $pad), ($cell + $pad + 2))
        $src.Dispose()
        $i++
    }
    $g.Dispose()
    $path = Join-Path $OutDir $out
    $canvas.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Output "saved $path"
}

# The starfield only reads at 1:1 or better - the faint tier is single pixels,
# and any downscale averages it into the background - so the star comparison is
# a 2x grid of one dial quadrant rather than a row of whole faces.
function BuildGrid([int]$x0, [int]$y0, [int]$side, [int]$zoom, [int]$cols, [string]$out) {
    $cell = $side * $zoom
    $pad = 4
    $labelH = 20
    $rows = [Math]::Ceiling($files.Count / [double]$cols)
    $w = ($cell + $pad) * $cols + $pad
    $h = ($cell + $labelH + $pad) * $rows + $pad
    $canvas = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($canvas)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $g.Clear([System.Drawing.Color]::FromArgb(24,24,28))
    $font = New-Object System.Drawing.Font "Consolas", 10
    $i = 0
    foreach ($f in $files) {
        $cx = $i % $cols
        $cy = [Math]::Floor($i / $cols)
        $src = [System.Drawing.Bitmap]::FromFile($f.FullName)
        $rect = New-Object System.Drawing.Rectangle $x0, $y0, $side, $side
        $dst = New-Object System.Drawing.Rectangle (($cell + $pad) * $cx + $pad), `
            (($cell + $labelH + $pad) * $cy + $pad), $cell, $cell
        $g.DrawImage($src, $dst, $rect, [System.Drawing.GraphicsUnit]::Pixel)
        $g.DrawString(($f.BaseName -replace '^\d\d-', ''), $font, [System.Drawing.Brushes]::White,
            (($cell + $pad) * $cx + $pad), (($cell + $labelH + $pad) * $cy + $cell + $pad + 1))
        $src.Dispose()
        $i++
    }
    $g.Dispose()
    $path = Join-Path $OutDir $out
    $canvas.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose()
    Write-Output "saved $path"
}

Build $moonHalf $moonY 2 "moon-strip.png"
Build $dialHalf $faceY 1 "dial-strip.png"
BuildGrid 150 300 205 2 4 "star-grid.png"

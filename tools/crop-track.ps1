# Crop and magnify the top of the second track out of a simulator screenshot,
# so two dot styles can be compared pixel for pixel instead of by impression.
#
#   powershell -File tools\crop-track.ps1 -In shot.png -Out crop.png
#
# The simulator renders the 454 px display 1:1 in its window, so the geometry
# is fixed (same constants as tools\montage.ps1).
param(
    [Parameter(Mandatory=$true)][string]$In,
    [Parameter(Mandatory=$true)][string]$Out,
    [int]$Zoom = 5,
    [string]$Label = ""
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$faceX = 327; $faceY = 481      # display centre inside the simulator window
$w = 210; $h = 56               # band across the top of the ring
$left = $faceX - [int]($w / 2)
$top  = $faceY - 227 + 2        # 12 o'clock, just inside the bezel

$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $In))
$labelH = if ($Label -ne "") { 22 } else { 0 }
$dst = New-Object System.Drawing.Bitmap ($w * $Zoom), ($h * $Zoom + $labelH)
$g = [System.Drawing.Graphics]::FromImage($dst)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$g.Clear([System.Drawing.Color]::FromArgb(24,24,28))
$srcRect = New-Object System.Drawing.Rectangle $left, $top, $w, $h
$dstRect = New-Object System.Drawing.Rectangle 0, $labelH, ($w * $Zoom), ($h * $Zoom)
$g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
if ($Label -ne "") {
    $font = New-Object System.Drawing.Font "Consolas", 12
    $g.DrawString($Label, $font, [System.Drawing.Brushes]::White, 6, 3)
}
$g.Dispose()
$path = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$dst.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$dst.Dispose(); $src.Dispose()
Write-Output "saved $path"

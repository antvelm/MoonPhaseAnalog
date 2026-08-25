# Capture the Connect IQ simulator window to a PNG.
#
#   powershell -File tools\screenshot.ps1 out.png
#
# The simulator has no command-line screenshot, so this grabs the window
# directly via PrintWindow (PW_RENDERFULLCONTENT). Unlike CopyFromScreen +
# SetForegroundWindow, this does not require the window to be focused or on
# top - Windows can silently refuse SetForegroundWindow for a
# background-driven process, which made the old approach flaky when run
# unattended from a script (see docs/simulator-property-reset.md).
param(
    [string]$Out = "sim.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, int nFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    public struct RECT { public int L, T, R, B; }
}
"@

$proc = Get-Process -Name 'simulator' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $proc) { throw "Simulator is not running (or has no window)." }

$h = $proc.MainWindowHandle
$rect = New-Object Win+RECT
[void][Win]::GetWindowRect($h, [ref]$rect)
$w = $rect.R - $rect.L
$hgt = $rect.B - $rect.T
if ($w -le 0 -or $hgt -le 0) { throw "Bad window size ${w}x${hgt}" }

$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[void][Win]::PrintWindow($h, $hdc, 2)   # PW_RENDERFULLCONTENT
$g.ReleaseHdc($hdc)
$g.Dispose()

$path = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved $path (${w}x${hgt})"

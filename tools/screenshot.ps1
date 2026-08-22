# Capture the Connect IQ simulator window to a PNG.
#
#   powershell -File tools\screenshot.ps1 out.png
#
# The simulator has no command-line screenshot, so this grabs the window from
# the desktop. It must be visible and not minimised.
param(
    [string]$Out = "sim.png"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    public struct RECT { public int L, T, R, B; }
    public struct POINT { public int X, Y; }
}
"@

$proc = Get-Process -Name 'simulator' -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
if ($null -eq $proc) { throw "Simulator is not running (or has no window)." }

$h = $proc.MainWindowHandle
[void][Win]::ShowWindow($h, 9)          # SW_RESTORE
[void][Win]::SetForegroundWindow($h)
Start-Sleep -Milliseconds 700

$rect = New-Object Win+RECT
[void][Win]::GetClientRect($h, [ref]$rect)
$origin = New-Object Win+POINT
[void][Win]::ClientToScreen($h, [ref]$origin)

$w = $rect.R - $rect.L
$hgt = $rect.B - $rect.T
if ($w -le 0 -or $hgt -le 0) { throw "Bad window size ${w}x${hgt}" }

$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bmp.Size)
$g.Dispose()

$path = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path (Get-Location) $Out }
$bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved $path (${w}x${hgt})"

param(
  [string]$Open = "",
  [string]$Mode = "",
  [int]$ClientWidth = 1280,
  [int]$ClientHeight = 800,
  [string]$Out = "build\screenshots\shot.png",
  [string]$ExePath = "build\windows\x64\runner\Debug\manhua_reader.exe",
  [int]$LoadWait = 10,
  [switch]$ShowChrome,
  [switch]$TurnPage,
  [switch]$BackToLibrary,
  [switch]$OpenFirstBook,
  [double]$BookTapX = 0.26,
  [double]$BookTapY = 0.47,
  [string]$Clicks = "",
  [string]$SendText = "",
  [string]$ExtraArgs = "",
  [switch]$Rtl
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$exe = Join-Path $root $ExePath
$outPath = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path (Split-Path $outPath) | Out-Null

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class ManhuaShot {
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int cmd);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
}
"@

$argsList = @()
if ($Open -ne "") { $argsList += "--open=$Open" }
if ($Mode -ne "") { $argsList += "--mode=$Mode" }
if ($Rtl) { $argsList += "--rtl" }
if ($ExtraArgs -ne "") { $argsList += $ExtraArgs.Split(' ') }

$env:MANHUA_WINDOW_WIDTH = "$($ClientWidth + 16)"
$env:MANHUA_WINDOW_HEIGHT = "$($ClientHeight + 39)"

$p = $null
try {
  Write-Output "Launching: $exe $($argsList -join ' ')"
  $startParams = @{
    FilePath = $exe
    WorkingDirectory = $root
    PassThru = $true
  }
  if ($argsList.Count -gt 0) { $startParams.ArgumentList = $argsList }
  $p = Start-Process @startParams

  $hwnd = [IntPtr]::Zero
  for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if ($p.HasExited) { throw "App exited early with code $($p.ExitCode)" }
    $p.Refresh()
    $candidate = $p.MainWindowHandle
    if ($candidate -ne [IntPtr]::Zero) {
      $probe = New-Object ManhuaShot+RECT
      [ManhuaShot]::GetClientRect($candidate, [ref]$probe) | Out-Null
      if (($probe.Right -ge 300) -and ($probe.Bottom -ge 300)) {
        $hwnd = $candidate
        break
      }
    }
  }
  if ($hwnd -eq [IntPtr]::Zero) { throw "No main window found" }
  Start-Sleep -Seconds 1
  $p.Refresh()
  if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $hwnd = $p.MainWindowHandle }
  Write-Output "Window handle: $hwnd"

  [ManhuaShot]::ShowWindow($hwnd, 9) | Out-Null
  Start-Sleep -Milliseconds 300

  $wr = New-Object ManhuaShot+RECT
  $cr = New-Object ManhuaShot+RECT
  [ManhuaShot]::GetWindowRect($hwnd, [ref]$wr) | Out-Null
  [ManhuaShot]::GetClientRect($hwnd, [ref]$cr) | Out-Null
  Write-Output "Initial window: $($wr.Right - $wr.Left)x$($wr.Bottom - $wr.Top), client: $($cr.Right)x$($cr.Bottom)"

  # Only move and pin on top; the initial size is supplied through the
  # MANHUA_WINDOW_* environment variables at window creation time.
  [ManhuaShot]::SetWindowPos($hwnd, [IntPtr](-1), 20, 20, 0, 0, 0x0041) | Out-Null
  [ManhuaShot]::BringWindowToTop($hwnd) | Out-Null
  [ManhuaShot]::SetForegroundWindow($hwnd) | Out-Null

  Write-Output "Waiting ${LoadWait}s for the reader to settle"
  Start-Sleep -Seconds $LoadWait

  [ManhuaShot]::GetClientRect($hwnd, [ref]$cr) | Out-Null
  $origin = New-Object ManhuaShot+POINT
  $origin.X = 0; $origin.Y = 0
  [ManhuaShot]::ClientToScreen($hwnd, [ref]$origin) | Out-Null
  $cw = $cr.Right; $ch = $cr.Bottom
  if ($cw -lt 300 -or $ch -lt 300) {
    throw "Unexpected client size ${cw}x${ch}; window did not reach the requested size"
  }

  function Click-At([double]$fx, [double]$fy) {
    $x = $origin.X + [int]($cw * $fx)
    $y = $origin.Y + [int]($ch * $fy)
    [ManhuaShot]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 100
    [ManhuaShot]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [ManhuaShot]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
    Write-Output "Clicked at $x,$y"
  }

  if ($OpenFirstBook) {
    Click-At $BookTapX $BookTapY
    Write-Output "Opened the book at $BookTapX,$BookTapY"
    Start-Sleep -Seconds 12
  }
  if ($SendText -ne "") {
    # Re-assert topmost/foreground immediately before typing: another topmost
    # window may have taken focus while the password dialog was loading.
    [ManhuaShot]::SetWindowPos($hwnd, [IntPtr](-1), 20, 20, 0, 0, 0x0041) | Out-Null
    [ManhuaShot]::BringWindowToTop($hwnd) | Out-Null
    [ManhuaShot]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 500
    # The password dialog's field is centered around 53% of the reader height;
    # clicking it also makes sure the app window has keyboard focus.
    Click-At 0.5 0.53
    Start-Sleep -Milliseconds 500
    [System.Windows.Forms.SendKeys]::SendWait($SendText)
    Write-Output "Sent text to the active dialog"
    Start-Sleep -Seconds 3
  }
  if ($ShowChrome) {
    # Two taps five seconds apart leave the chrome visible regardless of its
    # initial state (the reader auto-hides after four seconds).
    Click-At 0.5 0.5
    Start-Sleep -Seconds 5
    Click-At 0.5 0.5
    Start-Sleep -Milliseconds 900
  }
  if ($Clicks -ne "") {
    foreach ($pair in $Clicks.Split(';')) {
      $parts = $pair.Split(',')
      if ($parts.Count -eq 2) {
        Click-At ([double]$parts[0]) ([double]$parts[1])
        Start-Sleep -Milliseconds 800
      }
    }
    Start-Sleep -Seconds 2
  }
  if ($BackToLibrary) {
    Click-At 0.05 0.045
    Start-Sleep -Seconds 3
  }
  if ($TurnPage) {
    Click-At 0.86 0.5
    Start-Sleep -Milliseconds 1200
  }

  [ManhuaShot]::GetClientRect($hwnd, [ref]$cr) | Out-Null
  $origin.X = 0; $origin.Y = 0
  [ManhuaShot]::ClientToScreen($hwnd, [ref]$origin) | Out-Null
  $cw = $cr.Right; $ch = $cr.Bottom
  [ManhuaShot]::SetCursorPos($origin.X + 3, $origin.Y + $ch - 3) | Out-Null
  [ManhuaShot]::BringWindowToTop($hwnd) | Out-Null
  [ManhuaShot]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 500

  $bmp = New-Object System.Drawing.Bitmap($cw, $ch)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($origin.X, $origin.Y, 0, 0, $bmp.Size)
  $g.Dispose()
  $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Output "Saved $outPath"
}
finally {
  if ($p -ne $null -and -not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-Output "Stopped app $($p.Id)"
  }
}

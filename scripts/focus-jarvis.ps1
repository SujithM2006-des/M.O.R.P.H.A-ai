# Only one J.A.R.V.I.S. at a time. start-jarvis.bat asks this first: if the
# J.A.R.V.I.S. window is already open (a Chrome running on its own profile,
# %USERPROFILE%\.jarvis\face-profile, which nothing else uses), it is brought
# to the front - or, in popup mode, the popup is shown - and the exit code
# 0 tells the .bat not to open another one. Exit code 1: none open.
$ErrorActionPreference = 'SilentlyContinue'
$data = Join-Path $env:USERPROFILE '.jarvis'

# Chrome's main process for that profile (its helpers carry --type=...).
$main = Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
  Where-Object { $_.CommandLine -like '*face-profile*' -and $_.CommandLine -notlike '*--type=*' } |
  Select-Object -First 1
if (-not $main) { exit 1 }

if ((Test-Path (Join-Path $data 'popup-mode')) -and (Test-Path (Join-Path $data 'profile.json'))) {
  # Popup mode: the popup is the face; the main window stays in the background.
  try {
    $token = (Get-Content (Join-Path $data 'bridge-token') -Raw).Trim()
    Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8787/popup/show' -Headers @{ 'x-jarvis-token' = $token } -TimeoutSec 3 | Out-Null
  } catch {}
  exit 0
}

Add-Type @'
using System; using System.Runtime.InteropServices; using System.Text;
public class JarvisWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
}
'@
$target = [uint32]$main.ProcessId
$script:win = [IntPtr]::Zero
$cb = [JarvisWin+EnumProc]{
  param($h, $l)
  $id = [uint32]0; [void][JarvisWin]::GetWindowThreadProcessId($h, [ref]$id)
  if ($id -eq $target -and [JarvisWin]::IsWindowVisible($h) -and [JarvisWin]::GetWindowTextLength($h) -gt 0) { $script:win = $h; return $false }
  return $true
}
[void][JarvisWin]::EnumWindows($cb, [IntPtr]::Zero)
if ($script:win -ne [IntPtr]::Zero) {
  if ([JarvisWin]::IsIconic($script:win)) { [void][JarvisWin]::ShowWindow($script:win, 9) }   # SW_RESTORE
  # A tap of Alt lets this process hand the focus over (Windows otherwise only
  # flashes the taskbar button).
  [JarvisWin]::keybd_event(0x12, 0, 0, [IntPtr]::Zero); [JarvisWin]::keybd_event(0x12, 0, 2, [IntPtr]::Zero)
  [void][JarvisWin]::SetForegroundWindow($script:win)
}
# Open (even if still loading, with no window to show yet): never a second one.
exit 0

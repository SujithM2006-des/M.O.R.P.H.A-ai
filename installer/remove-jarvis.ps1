# Removes J.A.R.V.I.S. from this PC — every copy — but keeps the user's memory
# and personal files (so a reinstall remembers them) and never touches the
# installer. Bundled inside JARVIS-Uninstall.exe (installer\uninstaller.iss),
# which runs it first with -Mode Scan (to show what will go) and then, once
# the user says yes, with -Mode Remove.
#
# Removed:
#   - the copy JARVIS-Setup installed (with its own uninstaller)
#   - any other J.A.R.V.I.S. folder found through its shortcuts, its sign-in
#     entry or the running J.A.R.V.I.S. (a project folder, a second copy).
#     Only folders that really are J.A.R.V.I.S. (its own files inside).
#   - the desktop switches, the "Hey Jarvis" sign-in entry, Start menu entries
#   - in %USERPROFILE%\.jarvis everything that is not memory or personal data:
#     voice models, the Python environment, Chrome logins, logs, caches
# Kept:
#   - memory, profile, reminders, routines, history, AI keys, Flow characters,
#     look, workspace (the $keep list below)
#   - the setup file and anything else that is not a J.A.R.V.I.S. copy
#   - Node.js, Python, Chrome, ffmpeg, Ollama (other programs may use them)
#
# Every location can be overridden (for testing without touching the real ones).

param(
  [ValidateSet('Scan', 'Remove')] [string]$Mode = 'Scan',
  [string]$Report = (Join-Path $env:TEMP 'jarvis-remove-report.txt'),
  [string]$HomeDir = $env:USERPROFILE,
  [string]$DesktopDir = [Environment]::GetFolderPath('Desktop'),
  [string]$StartupDir = [Environment]::GetFolderPath('Startup'),
  [string]$ProgramsDir = [Environment]::GetFolderPath('Programs'),
  [string]$HealthUrl = 'http://127.0.0.1:8787/health',
  [string]$RegistryKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8E2C6F4A-3B1D-4C7E-9A52-6D1F0B7E3A91}_is1',
  # For testing: don't stop anything, and don't look at running processes
  # (those would point at the real J.A.R.V.I.S. on the test PC).
  [switch]$NoStop,
  [switch]$NoProcessScan
)

$ErrorActionPreference = 'SilentlyContinue'
$data = Join-Path $HomeDir '.jarvis'
$lines = New-Object System.Collections.Generic.List[string]
function Say([string]$t) { $lines.Add($t); Write-Host $t }

# What stays in .jarvis: memory and personal data. Everything else goes.
$keep = @(
  'memory.md', 'profile.json', 'reminders.json', 'routines.json', 'named-routines.json', 'history.jsonl',
  'past-events.json', 'flow.json', 'keys.json', 'feedback.jsonl', 'popup-mode', 'brain-choice',
  'ui-styles', 'workspace', 'python-work'
)

# A folder is a J.A.R.V.I.S. copy only if its own files are in it.
function Is-Jarvis([string]$dir) {
  if (-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)) { return $false }
  $pkg = Join-Path $dir 'package.json'
  return (Test-Path (Join-Path $dir 'bridge\server.mjs')) -and (Test-Path (Join-Path $dir 'scripts\jarvis-switch.ps1')) -and
         (Test-Path $pkg) -and ((Get-Content $pkg -Raw) -match '"name"\s*:\s*"jarvis"')
}
function Norm([string]$p) { if ($p) { try { return (Resolve-Path -LiteralPath $p).Path.TrimEnd('\') } catch { return $p.TrimEnd('\') } } }

# --- what is there -----------------------------------------------------------
$installed = $null; $uninst = $null
$rec = Get-ItemProperty $RegistryKey
if ($rec) { $installed = Norm ($rec.InstallLocation.Trim('"')); $uninst = $rec.UninstallString.Trim('"') }

$found = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
$sh = New-Object -ComObject WScript.Shell
$links = @()
foreach ($d in 'JARVIS Kill Switch', 'Popup Kill Switch') { $links += Get-ChildItem (Join-Path $DesktopDir $d) -Filter '*.lnk' }
$links += Get-Item (Join-Path $StartupDir 'JARVIS wake listener.lnk')
$links += Get-ChildItem $DesktopDir -Filter 'J.A.R.V.I.S*.lnk'
foreach ($l in $links | Where-Object { $_ }) {
  $s = $sh.CreateShortcut($l.FullName)
  foreach ($part in @($s.Arguments, $s.TargetPath, $s.WorkingDirectory)) {
    if ($part -match '([A-Za-z]:\\[^"]+?)\\(scripts|installer)\\[^"\\]+\.vbs') { [void]$found.Add((Norm $matches[1])) }
    elseif ($part -and (Test-Path -LiteralPath $part -PathType Container)) { [void]$found.Add((Norm $part)) }
  }
}
$running = $null
try { $running = (Invoke-RestMethod -Uri $HealthUrl -TimeoutSec 3).app } catch {}
if ($running) { [void]$found.Add((Norm $running)) }
if (-not $NoProcessScan) {
  Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match '([A-Za-z]:\\[^"]+?)\\scripts\\wake_listener\.py' } |
    ForEach-Object { if ($_.CommandLine -match '([A-Za-z]:\\[^"]+?)\\scripts\\wake_listener\.py') { [void]$found.Add((Norm $matches[1])) } }
}

$others = @($found | Where-Object { (Is-Jarvis $_) -and ($_ -ine $installed) } | Sort-Object -Unique)
$dataItems = @(Get-ChildItem -LiteralPath $data -Force | Where-Object { $keep -notcontains $_.Name })
$kept = @(Get-ChildItem -LiteralPath $data -Force | Where-Object { $keep -contains $_.Name })

if ($Mode -eq 'Scan') {
  if ($installed) { Say "INSTALLED|$installed" }
  foreach ($o in $others) { Say "COPY|$o" }
  Say "SHORTCUTS|$(@($links | Where-Object { $_ }).Count)"
  Say "DATA_REMOVE|$($dataItems.Count)"
  Say "DATA_KEEP|$(($kept | ForEach-Object Name) -join ', ')"
  $lines | Set-Content -Path $Report -Encoding UTF8
  return
}

# --- remove -------------------------------------------------------------------
if (-not $NoStop) {
  Say 'Stopping J.A.R.V.I.S....'
  $owner = (Get-NetTCPConnection -LocalPort 8787 -State Listen | Select-Object -First 1).OwningProcess
  if ($owner) {
    $node = Get-CimInstance Win32_Process -Filter "ProcessId=$owner"
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($node.ParentProcessId)"
    $top = if ($parent -and $parent.CommandLine -match 'start\.mjs') { $parent.ProcessId } else { $owner }
    & taskkill.exe /T /F /PID $top | Out-Null
  }
  Get-CimInstance Win32_Process | Where-Object {
    ($_.Name -match '^pythonw?\.exe$' -and $_.CommandLine -match 'wake_listener\.py|voice_server\.py') -or
    ($_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'popup\.ps1') -or
    ($_.Name -eq 'chrome.exe' -and $_.CommandLine -like '*face-profile*')
  } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  $pidFile = Join-Path $data 'ollama.pid'
  if (Test-Path $pidFile) { & taskkill.exe /T /F /PID ((Get-Content $pidFile -Raw).Trim()) | Out-Null }
  Start-Sleep 2
}

# The installed copy, with its own uninstaller (quietly: the data is handled below).
if ($installed) {
  Say "Removing the installed J.A.R.V.I.S. ($installed)..."
  if ($uninst -and (Test-Path -LiteralPath $uninst)) {
    Start-Process -FilePath $uninst -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
    # It hands over to a copy of itself: wait for the record to go.
    for ($i = 0; $i -lt 120 -and (Test-Path $RegistryKey); $i++) { Start-Sleep 1 }
  }
  if (Test-Path -LiteralPath $installed) { & cmd.exe /c rd /s /q "`"$installed`"" }
  Remove-Item $RegistryKey -Recurse -Force
}

# Every other J.A.R.V.I.S. copy.
foreach ($o in $others) {
  if (-not (Is-Jarvis $o)) { continue }
  Say "Removing J.A.R.V.I.S. at $o..."
  & cmd.exe /c rd /s /q "`"$o`""
  if (Test-Path -LiteralPath $o) { Say "  could not remove all of $o (a file in use?)" }
}

# Shortcuts: the switches, the sign-in entry, Start menu and desktop entries.
foreach ($d in 'JARVIS Kill Switch', 'Popup Kill Switch') { Remove-Item (Join-Path $DesktopDir $d) -Recurse -Force }
Remove-Item (Join-Path $StartupDir 'JARVIS wake listener.lnk') -Force
Get-ChildItem $DesktopDir -Filter 'J.A.R.V.I.S*.lnk' | Remove-Item -Force
Get-ChildItem $ProgramsDir -Directory -Filter 'J.A.R.V.I.S*' | Remove-Item -Recurse -Force
Say 'Removed the desktop switches, the sign-in entry and the Start menu entries.'

# .jarvis: everything except memory and personal data.
foreach ($i in $dataItems) { Remove-Item -LiteralPath $i.FullName -Recurse -Force }
$left = @(Get-ChildItem -LiteralPath $data -Force | ForEach-Object Name)
Say "Kept your memory and personal files in $data$(if ($left.Count) { ': ' + ($left -join ', ') })."
$lines | Set-Content -Path $Report -Encoding UTF8

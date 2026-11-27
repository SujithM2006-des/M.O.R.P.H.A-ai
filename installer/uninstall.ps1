# Run by the uninstaller (installer\jarvis.iss) before the files go: stops
# J.A.R.V.I.S. and removes what it made outside the install folder — the
# "Hey Jarvis" Startup entry and the desktop switch — but only the ones that
# point into THIS install, never another copy's. The user's settings and
# data (~/.jarvis) are not touched here; the uninstaller asks about them.

param([Parameter(Mandatory = $true)] [string]$App)

$ErrorActionPreference = 'SilentlyContinue'
$app = $App.TrimEnd('\')
$here = '*' + [Management.Automation.WildcardPattern]::Escape($app) + '*'
$data = Join-Path $env:USERPROFILE '.jarvis'

# The listener, the popup and the voice helper run with full paths into the
# install folder. Only those: the uninstaller itself is also started with
# this folder in its command line, and stopping "everything that mentions the
# folder" stopped the uninstall half-way (nothing was removed).
Get-CimInstance Win32_Process |
  Where-Object {
    $_.ProcessId -ne $PID -and $_.Name -match '^(python|pythonw|powershell|pwsh)(\.exe)?$' -and
    $_.CommandLine -like $here -and $_.CommandLine -match 'wake_listener\.py|popup\.ps1|voice_server\.py|transcribe\.py'
  } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

# The brain and the J.A.R.V.I.S. window — only if the J.A.R.V.I.S. running is
# THIS install (its /health says which folder it runs from). Another copy on
# the same PC (a developer's, say) is left alone.
$running = $null
try { $running = (Invoke-RestMethod -Uri 'http://127.0.0.1:8787/health' -TimeoutSec 3).app } catch {}
if ($running -and ($running.TrimEnd('\') -ieq $app)) {
  # The brain: the bridge's port owner and the launcher above it.
  $owner = (Get-NetTCPConnection -LocalPort 8787 -State Listen | Select-Object -First 1).OwningProcess
  $node = Get-CimInstance Win32_Process -Filter "ProcessId=$owner"
  if ($node) {
    $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$($node.ParentProcessId)"
    $top = if ($parent -and $parent.CommandLine -match 'start\.mjs') { $parent.ProcessId } else { $owner }
    & taskkill.exe /T /F /PID $top | Out-Null
  }
  Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
    Where-Object { $_.CommandLine -like '*face-profile*' -and $_.CommandLine -notlike '*--type=*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

# The Ollama server J.A.R.V.I.S. started for the offline model, if any.
$pidFile = Join-Path $data 'ollama.pid'
if (Test-Path $pidFile) {
  $p = (Get-Content $pidFile -Raw).Trim()
  if ($p) { & taskkill.exe /T /F /PID $p | Out-Null }
  Remove-Item $pidFile -Force
}

# Shortcuts made by scripts\jarvis-switch.ps1, when they belong to this install.
$shell = New-Object -ComObject WScript.Shell
function Points-Here([string]$lnk) {
  $s = $shell.CreateShortcut($lnk)
  return ("$($s.TargetPath) $($s.Arguments) $($s.WorkingDirectory)" -like $here)
}
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'JARVIS wake listener.lnk'
if ((Test-Path $startup) -and (Points-Here $startup)) { Remove-Item $startup -Force }
# .jarvis: J.A.R.V.I.S.'s downloads go (voice models, its Python, its Chrome
# logins, logs); memory and personal files stay, so a reinstall remembers the
# user. (The same list as installer\remove-jarvis.ps1.)
$keep = @(
  'memory.md', 'profile.json', 'reminders.json', 'routines.json', 'named-routines.json', 'history.jsonl',
  'past-events.json', 'flow.json', 'keys.json', 'feedback.jsonl', 'popup-mode', 'brain-choice',
  'ui-styles', 'workspace', 'python-work'
)
Get-ChildItem -LiteralPath $data -Force | Where-Object { $keep -notcontains $_.Name } | Remove-Item -Recurse -Force

# Both desktop switches: "JARVIS Kill Switch" and "Popup Kill Switch".
foreach ($name in 'JARVIS Kill Switch', 'Popup Kill Switch') {
  $switchDir = Join-Path ([Environment]::GetFolderPath('Desktop')) $name
  if (Test-Path $switchDir) {
    Get-ChildItem $switchDir -Filter '*.lnk' | Where-Object { Points-Here $_.FullName } | Remove-Item -Force
    if (-not (Get-ChildItem $switchDir -Force)) { Remove-Item $switchDir -Force }
  }
}

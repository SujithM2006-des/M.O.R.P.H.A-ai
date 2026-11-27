# J.A.R.V.I.S. setup — the part a file copy cannot do. Run by the installer
# (installer\jarvis.iss) once the files are in place. Safe to run again: it
# skips what is already there and never overwrites the user's own data, so
# running the setup file again repairs an install.
#
#   powershell -ExecutionPolicy Bypass -File installer\postinstall.ps1 -App "<install folder>" [-Listener] [-Offline] [-Autostart]

param(
  [Parameter(Mandatory = $true)] [string]$App,
  [switch]$Listener,
  [switch]$Offline,
  [switch]$Autostart,
  [switch]$JarvisSwitch,
  [switch]$PopupSwitch,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # downloads are many times faster without the progress bar
try { $Host.UI.RawUI.WindowTitle = 'J.A.R.V.I.S. setup' } catch {}
$log = Join-Path $App 'install-log.txt'
try { Start-Transcript -Path $log -Append | Out-Null } catch {}
$data = Join-Path $env:USERPROFILE '.jarvis'
New-Item -ItemType Directory -Force -Path $data | Out-Null

$problems = New-Object System.Collections.Generic.List[string]
$script:n = 0
function Step([string]$t) { $script:n++; Write-Host ''; Write-Host "[$script:n] $t" -ForegroundColor Cyan }
function Ok([string]$t) { Write-Host "    OK  $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "        $t" }
function Problem([string]$t) { Write-Host "    !!  $t" -ForegroundColor Yellow; $problems.Add($t) }
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
$winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
function Winget-Install([string]$id, [string]$name, [string[]]$more = @()) {
  if (-not $winget) { Problem "$name is missing, and Windows' installer (winget) is not available to get it."; return }
  Info "installing $name (Windows may ask for permission)..."
  & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements @more | Out-Host
  Refresh-Path
}

Write-Host 'J.A.R.V.I.S. setup' -ForegroundColor White
Write-Host 'Copyright (C) 2026 Sujith M. Based on JARVIS by Aditya Dewaskar. MIT License.' -ForegroundColor DarkGray
Write-Host "Installing into $App"
Write-Host 'This window shows the progress - please keep it open until it finishes.' -ForegroundColor DarkGray
Refresh-Path

# 1. Node.js runs JARVIS.
Step 'Node.js (runs J.A.R.V.I.S.)'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Winget-Install 'OpenJS.NodeJS.LTS' 'Node.js LTS' }
if (Get-Command node -ErrorAction SilentlyContinue) { Ok ('Node.js ' + (& node --version)) }
else { Problem 'Node.js is not installed. Get it from https://nodejs.org, then run the setup file again.' }

# 2. Chrome is JARVIS's window.
Step 'Google Chrome (the J.A.R.V.I.S. window)'
function Find-Chrome {
  foreach ($k in 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe') {
    $p = (Get-ItemProperty $k -ErrorAction SilentlyContinue).'(default)'
    if ($p -and (Test-Path $p)) { return $p }
  }
  return $null
}
if (-not (Find-Chrome)) { Winget-Install 'Google.Chrome' 'Google Chrome' }
if (Find-Chrome) { Ok 'Chrome found' }
else { Problem 'Google Chrome is not installed. Get it from https://www.google.com/chrome, then run the setup file again.' }

# 3. ffmpeg edits video and pictures.
Step 'ffmpeg (video and picture editing)'
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Winget-Install 'Gyan.FFmpeg' 'ffmpeg' }
if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { Ok 'ffmpeg found' }
else { Problem 'ffmpeg is not installed: video and picture editing will not work until it is.' }

# 4. JARVIS's own packages.
Step 'J.A.R.V.I.S. packages'
if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
  Push-Location $App
  & npm.cmd ci --no-audit --no-fund 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) { Ok 'packages installed' }
  else { Problem 'The packages could not be installed (npm). Check the internet connection, then run the setup file again.' }
  Pop-Location
} else { Problem 'Skipped the packages: Node.js is missing.' }

# 5. Python: voice, documents, charts, the free AI accounts (LiteLLM).
Step 'Python (voice, documents, free AI accounts)'
$venv = Join-Path $data 'wake-venv'
$vpy = Join-Path $venv 'Scripts\python.exe'
# Python 3.11 is what J.A.R.V.I.S. is built and tested on; 3.12 and 3.10 also
# work for its packages, so one of those already on the PC is used if 3.11
# cannot be installed.
function Find-Python([string[]]$versions) {
  foreach ($v in $versions) {
    $d = $v.Replace('.', '')
    foreach ($p in "$env:LOCALAPPDATA\Programs\Python\Python$d\python.exe", "$env:ProgramFiles\Python$d\python.exe") {
      if (Test-Path $p) { return $p }
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
      $p = & py "-$v" -c "import sys; print(sys.executable)" 2>$null
      if ($LASTEXITCODE -eq 0 -and $p) { return "$p".Trim() }
    }
  }
  return $null
}
if (-not (Test-Path $vpy)) {
  $py = Find-Python @('3.11')
  if (-not $py) { Winget-Install 'Python.Python.3.11' 'Python 3.11' @('--scope', 'user'); $py = Find-Python @('3.11', '3.12', '3.10') }
  if ($py) { Info "creating J.A.R.V.I.S.'s Python environment ($py)..."; & $py -m venv $venv | Out-Host }
}
if (Test-Path $vpy) {
  $pkgs = @('numpy', 'edge-tts', 'litellm[proxy]', 'python-docx', 'python-pptx', 'openpyxl', 'matplotlib', 'pandas',
            'qrcode', 'pillow', 'soundfile', 'yt-dlp', 'youtube-transcript-api')
  if ($Listener -or $Offline) { $pkgs += @('openwakeword', 'sounddevice', 'vosk') }
  if ($Offline) { $pkgs += 'faster-whisper' }
  Info ('installing: ' + ($pkgs -join ', '))
  Info 'This step shows no progress and takes 5-15 minutes - please leave this window open.'
  & $vpy -m pip install --upgrade pip --quiet 2>&1 | Out-Null
  & $vpy -m pip install --quiet @pkgs 2>&1 | Out-Host
  if ($LASTEXITCODE -eq 0) { Ok 'Python packages installed' }
  else { Problem 'Some Python packages did not install (see install-log.txt). Run the setup file again to retry.' }
} else { Problem 'Python 3.11 is not installed. Get it from https://www.python.org (version 3.11), then run the setup file again.' }

function Get-Zip([string]$url, [string]$into, [string]$name) {
  $zip = Join-Path $env:TEMP ('jarvis-' + [IO.Path]::GetFileName($url))
  Info "downloading $name..."
  try {
    New-Item -ItemType Directory -Force -Path $into | Out-Null
    Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $into -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    return $true
  } catch {
    Problem "$name could not be downloaded: $($_.Exception.Message)"
    return $false
  }
}
$vosk = Join-Path $data 'vosk'

# 6. "Hey Jarvis": the small speech model that listens for the name.
if ($Listener -or $Offline) {
  Step '"Hey Jarvis" speech model'
  if (Test-Path (Join-Path $vosk 'vosk-model-small-en-in-0.4')) { Ok 'already there' }
  elseif (Get-Zip 'https://alphacephei.com/vosk/models/vosk-model-small-en-in-0.4.zip' $vosk 'the small Indian-English model (about 40 MB)') { Ok 'downloaded' }
}

# 7. Offline mode: speech (Whisper, large Vosk) and answers (Ollama).
if ($Offline) {
  Step 'Offline speech (Whisper and the large Vosk model)'
  if (Test-Path (Join-Path $vosk 'vosk-model-en-in-0.5')) { Ok 'large Vosk model already there' }
  elseif (Get-Zip 'https://alphacephei.com/vosk/models/vosk-model-en-in-0.5.zip' $vosk 'the large Indian-English model (about 1 GB)') { Ok 'large Vosk model downloaded' }
  $w = Join-Path $data 'whisper\small.en'
  if (Test-Path (Join-Path $w 'model.bin')) { Ok 'Whisper already there' }
  elseif (Test-Path $vpy) {
    Info 'downloading Whisper small.en (about 460 MB)...'
    # The folder goes in through the environment, not the code: a name like
    # O'Brien in the path would break a quoted string.
    $env:JARVIS_WHISPER_DIR = $w
    & $vpy -c "import os; from faster_whisper import download_model as d; d('small.en', output_dir=os.environ['JARVIS_WHISPER_DIR'])" 2>&1 | Out-Host
    if (Test-Path (Join-Path $w 'model.bin')) { Ok 'Whisper downloaded' }
    else { Problem 'Whisper could not be downloaded; offline commands will use the Vosk model instead.' }
  }

  Step 'Offline answers (Ollama and the qwen3 4B model, about 2.5 GB)'
  $exe = (Get-Command ollama -ErrorAction SilentlyContinue).Source
  if (-not $exe) {
    Winget-Install 'Ollama.Ollama' 'Ollama'
    $exe = (Get-Command ollama -ErrorAction SilentlyContinue).Source
    if (-not $exe -and (Test-Path "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe")) { $exe = "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe" }
  }
  if ($exe) {
    $up = { try { (Invoke-WebRequest 'http://127.0.0.1:11434/api/version' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch { $false } }
    $srv = $null
    if (-not (& $up)) {
      $srv = Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden -PassThru
      for ($i = 0; $i -lt 30 -and -not (& $up); $i++) { Start-Sleep 1 }
    }
    Info 'downloading the offline model (qwen3:4b-instruct)...'
    & $exe pull qwen3:4b-instruct 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { Ok 'offline model ready (J.A.R.V.I.S. starts Ollama only when it is needed)' }
    else { Problem 'The offline model could not be downloaded. Later, run:  ollama pull qwen3:4b-instruct' }
    if ($srv) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
  } else { Problem 'Ollama is not installed (offline answers). Get it from https://ollama.com, then run the setup file again.' }
}

# 8. The desktop switches: "JARVIS - ON / OFF" (the kill switch: J.A.R.V.I.S.
#    and the "Hey Jarvis" listener on or off, remembered across restarts) and
#    "JARVIS Popup - ON / OFF" (the small popup as his face, or the main
#    window). The kill switch also keeps the sign-in entry, so listening from
#    sign-in needs it too.
if ($JarvisSwitch -or $Autostart) {
  Step 'JARVIS ON / OFF switch (kill switch)'
  $switch = Join-Path $App 'scripts\jarvis-switch.ps1'
  $flag = Join-Path $data 'disabled'
  # Listening from sign-in not chosen: the switch starts OFF (one double-click turns it on).
  if (-not $Autostart -and -not (Test-Path $flag)) { Set-Content -Path $flag -Value 'off until switched on (setup)' -Encoding utf8 }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $switch -Install | Out-Null
  # Checked, not assumed: the shortcut must really be on the desktop.
  if (Get-ChildItem (Join-Path ([Environment]::GetFolderPath('Desktop')) 'JARVIS Kill Switch') -Filter 'JARVIS - O*.lnk' -ErrorAction SilentlyContinue) {
    Ok 'the "JARVIS - ON / OFF" switch is in the "JARVIS Kill Switch" folder on the desktop (and in the Start menu)'
  } else { Problem 'The "JARVIS - ON / OFF" switch could not be put on the desktop; it is still in the Start menu.' }
  if ($Autostart) {
    Remove-Item $flag -Force -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $switch -Boot | Out-Null
    Ok 'listening for "Hey Jarvis" now, and from every sign-in'
  }
}
if ($PopupSwitch) {
  Step 'JARVIS Popup ON / OFF switch'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $App 'scripts\popup-switch.ps1') -Install | Out-Null
  if (Get-ChildItem (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Popup Kill Switch') -Filter 'JARVIS Popup - O*.lnk' -ErrorAction SilentlyContinue) {
    Ok 'the "JARVIS Popup - ON / OFF" switch is in the "Popup Kill Switch" folder on the desktop (and in the Start menu)'
  } else { Problem 'The "JARVIS Popup - ON / OFF" switch could not be put on the desktop; it is still in the Start menu.' }
}

Write-Host ''
if ($problems.Count) {
  Write-Host 'Setup finished, with some things to fix:' -ForegroundColor Yellow
  foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Yellow }
  Write-Host 'Run the setup file again after fixing them - it skips what is already done.'
  Write-Host "The full log: $log"
} else {
  Write-Host 'Setup finished. J.A.R.V.I.S. is ready.' -ForegroundColor Green
}
try { Stop-Transcript | Out-Null } catch {}
if (-not $NoPause) {
  if ($problems.Count) { Read-Host 'Press Enter to close this window' | Out-Null } else { Start-Sleep 4 }
}

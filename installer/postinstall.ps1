# M.O.R.P.H.A. setup — the part a file copy cannot do. Run by the installer
# (installer\jarvis.iss) once the files are in place: hidden, one step at a
# time (-Only), so the setup window shows the progress like any installer and
# no console window appears. Problems go to -Results ("PROBLEM|..." lines),
# which the setup's Finished page lists; everything goes to install-log.txt.
# Safe to run again: it skips what is already there and never overwrites the
# user's own data, so running the setup file again repairs an install.
#
#   powershell -ExecutionPolicy Bypass -File installer\postinstall.ps1 -App "<install folder>"
#       [-Only Node|Chrome|Ffmpeg|Packages|Python|WakeModel|Offline|Switches|All]
#       [-Listener] [-Offline] [-Autostart] [-JarvisSwitch] [-PopupSwitch] [-Results <file>]

param(
  [Parameter(Mandatory = $true)] [string]$App,
  [ValidateSet('All', 'Node', 'Chrome', 'Ffmpeg', 'Packages', 'Python', 'WakeModel', 'Offline', 'Switches')] [string]$Only = 'All',
  [string]$Results = '',
  [switch]$Listener,
  [switch]$Offline,
  [switch]$Autostart,
  [switch]$JarvisSwitch,
  [switch]$PopupSwitch,
  [switch]$NoPause
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'   # downloads are many times faster without the progress bar
$log = Join-Path $App 'install-log.txt'
try { Start-Transcript -Path $log -Append | Out-Null } catch {}
$data = Join-Path $env:USERPROFILE '.jarvis'
New-Item -ItemType Directory -Force -Path $data | Out-Null

$problems = New-Object System.Collections.Generic.List[string]
function Want([string]$step) { return ($Only -eq 'All' -or $Only -eq $step) }
function Step([string]$t) { Write-Host ''; Write-Host "[$Only] $t" -ForegroundColor Cyan }
function Ok([string]$t) { Write-Host "    OK  $t" -ForegroundColor Green }
function Info([string]$t) { Write-Host "        $t" }
function Problem([string]$t) {
  Write-Host "    !!  $t" -ForegroundColor Yellow
  $problems.Add($t)
  if ($Results) { Add-Content -Path $Results -Value "PROBLEM|$t" -Encoding UTF8 }
}
function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User') }
$winget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
function Winget-Install([string]$id, [string]$name, [string[]]$more = @()) {
  if (-not $winget) { Problem "$name is missing, and Windows' installer (winget) is not available to get it."; return }
  Info "installing $name (Windows may ask for permission)..."
  & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements @more | Out-Host
  Refresh-Path
}
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromHours(4)
# A download that says how far it is ("230 of 460 MB (50%)"), one line per
# percent: the setup window shows the latest line, so a long download
# visibly moves instead of looking stuck. Throws on failure.
function Get-File([string]$url, [string]$out, [string]$name) {
  $r = $http.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
  [void]$r.EnsureSuccessStatusCode()
  $total = $r.Content.Headers.ContentLength
  $name = $name -replace '\s*\(about [^)]*\)', ''   # the sizes are in the line itself
  $in =$r.Content.ReadAsStreamAsync().Result
  $fs = [IO.File]::Create($out)
  try {
    $buf = New-Object byte[] 1048576; $done = 0; $shown = -1
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      $fs.Write($buf, 0, $n); $done += $n
      $mb = [math]::Floor($done / 1MB)
      if ($total) {
        $pc = [math]::Floor(100 * $done / $total)
        if ($pc -ne $shown) { $shown = $pc; Write-Host "        Downloading ${name}: $mb of $([math]::Round($total / 1MB)) MB ($pc%)" }
      } elseif ([math]::Floor($mb / 10) -ne $shown) { $shown = [math]::Floor($mb / 10); Write-Host "        Downloading ${name}: $mb MB" }
    }
  } finally { $fs.Close(); $in.Close() }
}
function Get-Zip([string]$url, [string]$into, [string]$name) {
  $zip = Join-Path $env:TEMP ('jarvis-' + [IO.Path]::GetFileName($url))
  Info "downloading $name..."
  try {
    New-Item -ItemType Directory -Force -Path $into | Out-Null
    Get-File $url $zip $name
    Write-Host "        Unpacking $name..."
    Expand-Archive -Path $zip -DestinationPath $into -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    return $true
  } catch {
    $m = $_.Exception.Message; if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
    Problem "$name could not be downloaded: $m"
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    return $false
  }
}
$venv = Join-Path $data 'wake-venv'
$vpy = Join-Path $venv 'Scripts\python.exe'
$vosk = Join-Path $data 'vosk'
Refresh-Path

if ($Only -eq 'All' -or $Only -eq 'Node') {
  Write-Host 'M.O.R.P.H.A. setup' -ForegroundColor White
  Write-Host 'Copyright (C) 2026 Sujith M. Based on JARVIS by Aditya Dewaskar. MIT License.' -ForegroundColor DarkGray
  Write-Host "Installing into $App"
}

# Node.js runs JARVIS.
if (Want 'Node') {
  Step 'Node.js (runs M.O.R.P.H.A.)'
  if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Winget-Install 'OpenJS.NodeJS.LTS' 'Node.js LTS' }
  if (Get-Command node -ErrorAction SilentlyContinue) { Ok ('Node.js ' + (& node --version)) }
  else { Problem 'Node.js is not installed. Get it from https://nodejs.org, then run the setup file again.' }
}

# Chrome is JARVIS's window.
if (Want 'Chrome') {
  Step 'Google Chrome (the M.O.R.P.H.A. window)'
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
}

# ffmpeg edits video and pictures.
if (Want 'Ffmpeg') {
  Step 'ffmpeg (video and picture editing)'
  if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) { Winget-Install 'Gyan.FFmpeg' 'ffmpeg' }
  if (Get-Command ffmpeg -ErrorAction SilentlyContinue) { Ok 'ffmpeg found' }
  else { Problem 'ffmpeg is not installed: video and picture editing will not work until it is.' }
}

# JARVIS's own packages.
if (Want 'Packages') {
  Step 'M.O.R.P.H.A. packages'
  if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
    Push-Location $App
    & npm.cmd ci --no-audit --no-fund 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { Ok 'packages installed' }
    else { Problem 'The packages could not be installed (npm). Check the internet connection, then run the setup file again.' }
    Pop-Location
  } else { Problem 'Skipped the packages: Node.js is missing.' }
}

# Python: voice, documents, charts, the free AI accounts (LiteLLM).
if (Want 'Python') {
  Step 'Python (voice, documents, free AI accounts)'
  # Python 3.11 is what M.O.R.P.H.A. is built and tested on; 3.12 and 3.10 also
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
    if ($py) { Info "creating M.O.R.P.H.A.'s Python environment ($py)..."; & $py -m venv $venv | Out-Host }
  }
  if (Test-Path $vpy) {
    $pkgs = @('numpy', 'edge-tts', 'litellm[proxy]', 'python-docx', 'python-pptx', 'openpyxl', 'matplotlib', 'pandas',
              'qrcode', 'pillow', 'soundfile', 'yt-dlp', 'youtube-transcript-api')
    if ($Listener -or $Offline) { $pkgs += @('openwakeword', 'sounddevice', 'vosk') }
    if ($Offline) { $pkgs += 'faster-whisper' }
    Info ('installing: ' + ($pkgs -join ', '))
    & $vpy -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    # Not --quiet: each "Collecting ..." / "Installing ..." line shows in the
    # setup window, so this long step visibly moves.
    & $vpy -m pip install --progress-bar off @pkgs 2>&1 | Out-Host
    if ($LASTEXITCODE -eq 0) { Ok 'Python packages installed' }
    else { Problem 'Some Python packages did not install (see the Setup log). Run the setup file again to retry.' }
  } else { Problem 'Python 3.11 is not installed. Get it from https://www.python.org (version 3.11), then run the setup file again.' }
}

# "Hey Morpha": the small speech model that listens for the name.
if ((Want 'WakeModel') -and ($Listener -or $Offline)) {
  Step '"Hey Morpha" speech model'
  if (Test-Path (Join-Path $vosk 'vosk-model-small-en-in-0.4')) { Ok 'already there' }
  elseif (Get-Zip 'https://alphacephei.com/vosk/models/vosk-model-small-en-in-0.4.zip' $vosk 'the small Indian-English model (about 40 MB)') { Ok 'downloaded' }
  # Whisper base.en: checks the name the small model is unsure of ("Morpha"
  # is not a word it knows). The same files faster-whisper's download_model
  # fetches.
  $wb = Join-Path $data 'whisper\base.en'
  if (Test-Path (Join-Path $wb 'model.bin')) { Ok 'name checker (Whisper base.en) already there' }
  else {
    New-Item -ItemType Directory -Force -Path $wb | Out-Null
    try {
      foreach ($f in 'config.json', 'tokenizer.json', 'vocabulary.txt', 'model.bin') {
        $label = if ($f -eq 'model.bin') { 'the name checker (Whisper base.en)' } else { "Whisper base.en $f" }
        Get-File "https://huggingface.co/Systran/faster-whisper-base.en/resolve/main/$f" (Join-Path $wb "$f.part") $label
        Move-Item -Force (Join-Path $wb "$f.part") (Join-Path $wb $f)
      }
      Ok 'name checker (Whisper base.en) downloaded'
    } catch {
      Get-ChildItem $wb -Filter '*.part' -ErrorAction SilentlyContinue | Remove-Item -Force
      Problem "The name checker (Whisper base.en) could not be downloaded; the wake word will be less reliable. Run the setup file again to retry."
    }
  }
}

# Offline mode: speech (Whisper, large Vosk) and answers (Ollama).
if ((Want 'Offline') -and $Offline) {
  Step 'Offline speech (Whisper)'
  # Whisper reads offline commands. The large Vosk model (1 GB) is only the
  # fallback when Whisper is missing, so it is downloaded only then.
  $w = Join-Path $data 'whisper\small.en'
  if (Test-Path (Join-Path $w 'model.bin')) { Ok 'Whisper already there' }
  else {
    # The same files faster-whisper's own download_model('small.en') fetches.
    New-Item -ItemType Directory -Force -Path $w | Out-Null
    try {
      foreach ($f in 'config.json', 'tokenizer.json', 'vocabulary.txt', 'model.bin') {
        $label = if ($f -eq 'model.bin') { 'Whisper (offline speech)' } else { "Whisper $f" }
        Get-File "https://huggingface.co/Systran/faster-whisper-small.en/resolve/main/$f" (Join-Path $w "$f.part") $label
        Move-Item -Force (Join-Path $w "$f.part") (Join-Path $w $f)
      }
    } catch { Info "direct download failed: $($_.Exception.Message)" }
    if (-not (Test-Path (Join-Path $w 'model.bin')) -and (Test-Path $vpy)) {
      Info 'trying again through faster-whisper...'
      # The folder goes in through the environment, not the code: a name like
      # O'Brien in the path would break a quoted string.
      $env:JARVIS_WHISPER_DIR = $w
      & $vpy -c "import os; from faster_whisper import download_model as d; d('small.en', output_dir=os.environ['JARVIS_WHISPER_DIR'])" 2>&1 | Out-Host
    }
    Get-ChildItem $w -Filter '*.part' -ErrorAction SilentlyContinue | Remove-Item -Force
    if (Test-Path (Join-Path $w 'model.bin')) { Ok 'Whisper downloaded' }
  }
  if (-not (Test-Path (Join-Path $w 'model.bin'))) {
    if (Test-Path (Join-Path $vosk 'vosk-model-en-in-0.5')) { Ok 'large Vosk model already there (used instead of Whisper)' }
    elseif (Get-Zip 'https://alphacephei.com/vosk/models/vosk-model-en-in-0.5.zip' $vosk 'the large Vosk speech model (about 1 GB)') { Ok 'Whisper could not be downloaded; the large Vosk model is used instead' }
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
    # Through Ollama's own API, which reports how far it is, one line per
    # percent (the command line's progress bar redraws one line and would
    # show nothing in the setup window until the end).
    $pulled = $false
    try {
      $req = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Post, 'http://127.0.0.1:11434/api/pull')
      $req.Content = New-Object System.Net.Http.StringContent('{"model":"qwen3:4b-instruct","stream":true}', [Text.Encoding]::UTF8, 'application/json')
      $res = $http.SendAsync($req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
      $rd = New-Object IO.StreamReader($res.Content.ReadAsStreamAsync().Result)
      $shown = ''
      while ($null -ne ($line = $rd.ReadLine())) {
        try { $j = $line | ConvertFrom-Json } catch { continue }
        if ($j.error) { Info "Ollama: $($j.error)"; break }
        if ($j.status -eq 'success') { $pulled = $true; break }
        if ($j.total -and $j.total -lt 1MB) { continue }   # the model's small parts: nothing worth showing
        if ($j.total -and $j.completed) {
          $pc = [math]::Floor(100 * $j.completed / $j.total)
          $key = "$($j.digest) $pc"
          $s = "$([math]::Round($j.completed / 1MB)) of $([math]::Round($j.total / 1MB)) MB ($pc%)"
        } else { $key = $j.status; $s = $j.status }
        if ($key -ne $shown) { $shown = $key; Write-Host "        Downloading the offline AI model: $s" }
      }
      $rd.Close()
    } catch { Info "Ollama's API did not answer: $($_.Exception.Message)" }
    if (-not $pulled) { & $exe pull qwen3:4b-instruct 2>&1 | Out-Host; $pulled = ($LASTEXITCODE -eq 0) }
    if ($pulled) { Ok 'offline model ready (M.O.R.P.H.A. starts Ollama only when it is needed)' }
    else { Problem 'The offline model could not be downloaded. Later, run:  ollama pull qwen3:4b-instruct' }
    if ($srv) { Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue }
  } else { Problem 'Ollama is not installed (offline answers). Get it from https://ollama.com, then run the setup file again.' }
}

# The desktop switches: "MORPHA - ON / OFF" (the kill switch: M.O.R.P.H.A.
# and the "Hey Morpha" listener on or off, remembered across restarts) and
# "MORPHA Popup - ON / OFF" (the small popup as its face, or the main
# window). The kill switch also keeps the sign-in entry, so listening from
# sign-in needs it too.
if ((Want 'Switches') -and ($JarvisSwitch -or $Autostart)) {
  Step 'MORPHA ON / OFF switch (kill switch)'
  $switch = Join-Path $App 'scripts\jarvis-switch.ps1'
  $flag = Join-Path $data 'disabled'
  # Listening from sign-in not chosen: the switch starts OFF (one double-click turns it on).
  if (-not $Autostart -and -not (Test-Path $flag)) { Set-Content -Path $flag -Value 'off until switched on (setup)' -Encoding utf8 }
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $switch -Install | Out-Null
  # Checked, not assumed: the shortcut must really be on the desktop.
  if (Get-ChildItem (Join-Path ([Environment]::GetFolderPath('Desktop')) 'MORPHA Kill Switch') -Filter 'MORPHA - O*.lnk' -ErrorAction SilentlyContinue) {
    Ok 'the "MORPHA - ON / OFF" switch is in the "MORPHA Kill Switch" folder on the desktop (and in the Start menu)'
  } else { Problem 'The "MORPHA - ON / OFF" switch could not be put on the desktop; it is still in the Start menu.' }
  if ($Autostart) {
    Remove-Item $flag -Force -ErrorAction SilentlyContinue
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $switch -Boot | Out-Null
    Ok 'listening for "Hey Morpha" now, and from every sign-in'
  }
}
if ((Want 'Switches') -and $PopupSwitch) {
  Step 'MORPHA Popup ON / OFF switch'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File (Join-Path $App 'scripts\popup-switch.ps1') -Install | Out-Null
  if (Get-ChildItem (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Popup Kill Switch') -Filter 'MORPHA Popup - O*.lnk' -ErrorAction SilentlyContinue) {
    Ok 'the "MORPHA Popup - ON / OFF" switch is in the "Popup Kill Switch" folder on the desktop (and in the Start menu)'
  } else { Problem 'The "MORPHA Popup - ON / OFF" switch could not be put on the desktop; it is still in the Start menu.' }
}

if ($Only -eq 'All') {
  Write-Host ''
  if ($problems.Count) {
    Write-Host 'Setup finished, with some things to fix:' -ForegroundColor Yellow
    foreach ($p in $problems) { Write-Host "  - $p" -ForegroundColor Yellow }
  } else { Write-Host 'Setup finished. M.O.R.P.H.A. is ready.' -ForegroundColor Green }
}
try { Stop-Transcript | Out-Null } catch {}
# Run by hand (-Only All) in a console: keep the window to read the result.
if ($Only -eq 'All' -and -not $NoPause -and -not $Results -and $problems.Count) { Read-Host 'Press Enter to close this window' | Out-Null }

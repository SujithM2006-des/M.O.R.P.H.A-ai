@echo off
rem Starts JARVIS: the brain (bridge + interface server) and its window.
rem   start-jarvis.bat        normal start
rem   start-jarvis.bat wake   started by "Hey Jarvis": greets you and listens straight away
rem
rem The window opens at once on the loading screen (scripts\splash.html, read
rem straight from disk), which shows progress and switches to JARVIS by itself
rem the moment the brain and the interface are both up.
cd /d "%~dp0"
rem Gmail, Calendar & Drive (account connectors) are switched on in Customize,
rem not here: their tools ride along with every request and cost usage.

set "SPLASH=%~dp0scripts\splash.html"
set "SPLASH=file:///%SPLASH:\=/%"
if /i "%~1"=="wake" set "SPLASH=%SPLASH%?wake=1"

rem The brain, unless it is already running — hidden: it used to sit on the
rem taskbar as a minimised console. Everything it prints still goes to
rem %USERPROFILE%\.jarvis\jarvis.log, and the JARVIS ON / OFF switch stops it
rem (it finds it by the "npm start -- --writes" in its command line).
curl -s -o nul -m 2 http://127.0.0.1:8787/health || powershell -NoProfile -WindowStyle Hidden -Command "Start-Process cmd.exe -ArgumentList '/c','npm start -- --writes' -WorkingDirectory '%~dp0.' -WindowStyle Hidden"

rem Only one J.A.R.V.I.S.: if his window is already open, it is brought to the
rem front (in popup mode, the popup is shown) and no second one opens.
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0scripts\focus-jarvis.ps1"
if not errorlevel 1 exit /b 0

rem Popup mode (%USERPROFILE%\.jarvis\popup-mode exists): the main window starts
rem minimised and works in the background; the small popup is the face. Not
rem before the first-run setup is done, though: that screen is in the main window.
set "SIZE=--start-maximized"
set "SHOW="
if exist "%USERPROFILE%\.jarvis\popup-mode" if exist "%USERPROFILE%\.jarvis\profile.json" (
  set "SIZE="
  set "SHOW=/min"
)

rem Own Chrome profile so these flags apply even when normal Chrome is open:
rem they stop Chrome pausing the page (and its microphone) when other windows cover it,
rem allow sound without a click, and put the voice model on the NVIDIA GPU.
start "" %SHOW% chrome --user-data-dir="%USERPROFILE%\.jarvis\face-profile" --app="%SPLASH%" %SIZE% --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling --autoplay-policy=no-user-gesture-required --force_high_performance_gpu
